#!/usr/bin/env bash
#
# Guard for the pull-request suite: fails when the tree holds a test that needs a
# Docker daemon, so the gap is reported by name instead of surfacing later as
# "Could not find a valid Docker environment" from inside Testcontainers
# (design D13).
#
# The PR gate has neither a Docker daemon nor a Docker socket (design D1, R3)
# and maven-failsafe-plugin is bound to integration-test/verify in every module,
# so the first *IT.java would run inside ./mvnw verify and die there. The
# integration and e2e levels belong to the release battery of PROJECT.md §7;
# bringing them into CI is the `ci-integration` change, which has to decide how
# the tests reach a daemon first.
#
# Usage: scripts/ci-suite-scope.sh
# Exit codes: 0 when no *IT.java lives under apps/ or libs/, 1 when one does or
# the scanned tree is missing, 2 on a usage error.

set -euo pipefail

# Resolve the repository root from this script's location so the check behaves
# the same no matter which directory Jenkins (or a human) launches it from.
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  cat <<'USAGE'
Usage: scripts/ci-suite-scope.sh

Fails when apps/ or libs/ holds a *IT.java. Those tests need a Docker daemon,
which the PR gate does not have by design: they run in the release battery of
PROJECT.md §7 and enter CI through the `ci-integration` change (design D13).

Read-only. It runs before `./mvnw -B -ntp verify` in the Backend stage.

Exit codes: 0 when no *IT.java is found, 1 when one is, 2 on a usage error.
USAGE
}

for argument in "$@"; do
  case "${argument}" in
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "ci-suite-scope: unexpected argument '${argument}'" >&2
      usage >&2
      exit 2
      ;;
  esac
done

scan_roots=()
for scan_root in apps libs; do
  [[ -d "${repo_root}/${scan_root}" ]] || continue
  scan_roots+=("${repo_root}/${scan_root}")
done

if (( ${#scan_roots[@]} == 0 )); then
  echo "ci-suite-scope: neither apps/ nor libs/ exists under ${repo_root}; nothing to scan." >&2
  exit 1
fi

# target/ is excluded: it holds generated sources and compiled test classes, not
# the source tree failsafe would pick the *IT.java from. paths are reported
# relative to the repository root so the message points at the file to act on.
integration_tests=()
while IFS= read -r file; do
  [[ -n "${file}" ]] || continue
  integration_tests+=("${file#"${repo_root}/"}")
done < <(
  find "${scan_roots[@]}" -type f -name '*IT.java' -not -path '*/target/*' | sort
)

if (( ${#integration_tests[@]} > 0 )); then
  echo "ci-suite-scope: integration tests need a Docker daemon and the PR gate has none (design D13):" >&2
  printf '  - %s\n' "${integration_tests[@]}" >&2
  echo "Move them to the release battery of PROJECT.md §7 and open the 'ci-integration' change" >&2
  echo "to bring this level into CI; do not mount the Docker socket on the PR gate." >&2
  exit 1
fi

echo "ci-suite-scope: OK (no *IT.java under apps/ or libs/; the PR suite runs without a Docker daemon)."
