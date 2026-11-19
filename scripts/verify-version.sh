#!/usr/bin/env bash
#
# Verifies the two sides of the versioning rule of PROJECT.md §7: what the tree
# declares and what the running artifacts declare.
#
# The first side is a policy check. A tree that differs from the last release tag
# carries unreleased work and must announce -SNAPSHOT; only a release branch may
# declare a version without the suffix, and that version must be the one in its
# name. Without this check a forgotten bump looks exactly like a clean tree: the
# POM names a released version while develop holds code that tag never had.
#
# The second side is an artifact check, and it is the one that catches a stale
# environment: Compose runs `latest`, so recreating the environment without
# building the images first starts containers of an older commit. The version
# baked into each jar travels to /v3/api-docs as info.version (springdoc reads
# spring.application.version, filled by Maven resource filtering), so the file on
# disk and the jar in the container can be compared from outside.
#
# Usage: scripts/verify-version.sh [--tree] [--running]
#
#   --tree     the version declared by the parent POM agrees with the branch and
#              with the last release tag.
#   --running  the six Java services of the running environment report that same
#              version.
# With no arguments both checks run. Read-only: nothing is built, started,
# fixed or tagged here.
#
# The frontend is not covered by --running: nginx serves a static bundle and has
# no version endpoint. Its artifact is covered by building the images in the
# release battery, which come from the same revision of the tree.
#
# Exit codes: 0 when every check passes, 1 when one fails, 2 on a usage error.

set -euo pipefail

# Resolve the repository root from this script's location: .env lives there, and
# the relative paths of COMPOSE_FILE are resolved from the directory Compose runs
# in, not from the caller's.
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

# The six Java applications publish springdoc. api-gateway is last because it is
# the entry point of the frontend and the one whose failure hides the others.
java_services=(
  auth-service
  user-service
  recipe-service
  media-service
  notification-service
  api-gateway
)

usage() {
  cat <<'USAGE'
Usage: scripts/verify-version.sh [--tree] [--running]

Checks the version of the project against the versioning rule of PROJECT.md §7:

  --tree     the parent POM declares a version coherent with the current branch
             and the last release tag.
  --running  the six Java services of the running environment declare that same
             version in /v3/api-docs.

With no arguments both checks run. Start the environment first with
`docker compose up --wait`; --running reads it over the published ports.

Exit codes: 0 when every check passes, 1 when one fails, 2 on a usage error.
USAGE
}

fail() {
  echo "verify-version: $*" >&2
  exit 1
}

# Every Docker call goes through here: the working directory is the repository
# root because that is where Compose finds .env, no matter where the script was
# launched from.
compose() {
  (cd -- "${repo_root}" && docker compose "$@")
}

# The <version> of the project itself, not the one of the <parent> block it
# inherits from: that element is the single version PROJECT.md §7 makes every
# module inherit, and the springdoc one every service publishes.
tree_version() {
  awk '
    /<parent>/ { in_parent = 1 }
    /<\/parent>/ { in_parent = 0; next }
    !in_parent && /<version>/ {
      gsub(/^[[:space:]]*<version>/, "")
      gsub(/<\/version>[[:space:]]*$/, "")
      print
      exit
    }
  ' "${repo_root}/pom.xml"
}

# The content of the tree against the last release tag. History is not compared
# because squash merges leave develop and main with disjoint histories, so the
# tag is unreachable from develop even when both trees are identical. The version
# files are excluded on purpose: moving the version is what this check allows
# without changing content.
differs_from_tag() {
  local tag="$1"
  ! git -C "${repo_root}" diff --quiet "${tag}" HEAD -- . \
    ':(exclude)pom.xml' \
    ':(exclude)*/pom.xml' \
    ':(exclude)apps/web-frontend/package.json' \
    ':(exclude)apps/web-frontend/package-lock.json'
}

check_tree() {
  local expected branch tag
  expected="$(tree_version)"
  [[ -n "${expected}" ]] || fail "cannot read the project version from ${repo_root}/pom.xml"

  branch="$(git -C "${repo_root}" branch --show-current)"
  [[ -n "${branch}" ]] || fail "detached HEAD: the version rule is checked on a branch"

  # The release branch is the only place allowed to declare a version without
  # -SNAPSHOT before its tag exists, and it must be the version in its name:
  # anything else would tag one number and certify another.
  if [[ "${branch}" == release/* ]]; then
    [[ "${expected}" != *-SNAPSHOT ]] \
      || fail "branch ${branch} declares ${expected}: the release branch fixes the version it releases (PROJECT.md §7)"
    [[ "${expected}" == "${branch#release/}" ]] \
      || fail "branch ${branch} declares ${expected}: the version of a release branch is the one in its name"
    echo "verify-version: OK ${branch} releases ${expected}"
    return
  fi

  # The highest version tag, not the nearest reachable one: with squash merges
  # the tags live on main and are unreachable from develop, so `git describe`
  # would answer v0.1.0 while v0.2.0 is the last release.
  tag="$(git -C "${repo_root}" tag --list 'v[0-9]*' --sort=-v:refname | head -n 1)"
  if [[ -z "${tag}" ]]; then
    echo "verify-version: OK no release tag yet; ${branch} declares ${expected}"
    return
  fi

  if differs_from_tag "${tag}"; then
    [[ "${expected}" == *-SNAPSHOT ]] \
      || fail "${branch} differs from ${tag} but declares ${expected}: unreleased work must carry -SNAPSHOT (PROJECT.md §7)"
    echo "verify-version: OK ${branch} carries work beyond ${tag} and declares ${expected}"
  else
    [[ "${expected}" == "${tag#v}" ]] \
      || fail "${branch} is the content of ${tag} but declares ${expected}; it should declare ${tag#v}"
    echo "verify-version: OK ${branch} matches ${tag} and declares ${expected}"
  fi
}

check_running() {
  local expected service port body version
  local -a mismatched=() unreadable=()
  expected="$(tree_version)"
  [[ -n "${expected}" ]] || fail "cannot read the project version from ${repo_root}/pom.xml"

  for service in "${java_services[@]}"; do
    port="$(compose port "${service}" 8080 2>/dev/null | head -n 1 | sed 's/.*://')"
    if [[ -z "${port}" ]]; then
      unreadable+=("${service}: no published port, is the environment up?")
      continue
    fi
    if ! body="$(curl -fsS --max-time 5 "http://localhost:${port}/v3/api-docs" 2>&1)"; then
      unreadable+=("${service}: ${body}")
      continue
    fi
    if ! version="$(python3 -c 'import json, sys
print(json.load(sys.stdin)["info"]["version"])' <<<"${body}" 2>/dev/null)"; then
      unreadable+=("${service}: info.version not found in /v3/api-docs")
      continue
    fi
    if [[ "${version}" != "${expected}" ]]; then
      mismatched+=("${service} reports ${version}")
      continue
    fi
    echo "verify-version: OK ${service} reports ${version}"
  done

  if (( ${#unreadable[@]} > 0 )); then
    fail "cannot read the version of: ${unreadable[*]}"
  fi
  if (( ${#mismatched[@]} > 0 )); then
    fail "the tree declares ${expected} but ${mismatched[*]}; build the images with scripts/build-images.sh and recreate the environment"
  fi
}

run_tree=false
run_running=false
for argument in "$@"; do
  case "${argument}" in
    -h | --help)
      usage
      exit 0
      ;;
    --tree)
      run_tree=true
      ;;
    --running)
      run_running=true
      ;;
    *)
      echo "verify-version: unexpected argument '${argument}'" >&2
      usage >&2
      exit 2
      ;;
  esac
done
if [[ "${run_tree}" == false && "${run_running}" == false ]]; then
  run_tree=true
  run_running=true
fi

command -v git >/dev/null 2>&1 || fail "git not found in PATH"
if [[ "${run_running}" == true ]]; then
  for tool in docker curl python3; do
    command -v "${tool}" >/dev/null 2>&1 || fail "${tool} not found in PATH"
  done
  # Resolved before probing anything: an empty COMPOSE_FILE would otherwise
  # surface as six unrelated "no configuration file provided" errors.
  compose config --quiet >/dev/null 2>&1 \
    || fail "cannot resolve the Compose configuration; check COMPOSE_FILE (.env or the environment) and that every file it lists exists"
fi

[[ "${run_tree}" == true ]] && check_tree
[[ "${run_running}" == true ]] && check_running

echo "verify-version: OK (version $(tree_version) coherent with the branch, the last tag and the running artifacts)"
