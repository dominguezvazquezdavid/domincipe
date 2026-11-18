#!/usr/bin/env bash
#
# Verifies that the local and the CI image builds follow the same contract
# (design D3, task 6.3).
#
# The monorepo builds its seven images through two paths: scripts/build-images.sh
# with the Docker CLI on a development host, and the Images stage of
# ops/jenkins/Jenkinsfile with buildctl against the rootless builder. Both have
# to build each image from the same Dockerfile, with the same build arguments and
# with the same org.opencontainers.image.revision label, or an image produced by
# one path cannot be reproduced by the other.
#
# Source parity (always): the image list, the Dockerfile of each image, the build
# arguments each Dockerfile requires, the short-SHA derivation and the revision
# label must agree across scripts/build-images.sh, ops/jenkins/Jenkinsfile,
# ops/jenkins/vars/ciBuildImage.groovy and the two Dockerfiles. This half needs
# no Docker daemon, so the Images stage runs it after building.
#
# Artefact parity: every OCI archive must carry the revision label of the commit
# and its config history must record the ARG values that produced it (GIT_SHA
# always, MODULE for the images whose Dockerfile declares it). With --local the
# label is also compared against the local Docker image <prefix>/<image>:<sha> of
# the same commit, which is the check task 6.3 asks for on the host.
#
# Digests are deliberately not compared: a digest identifies bytes, and the same
# Dockerfile built at another time produces different layers (design D3 explains
# why). The contract is the Dockerfile, the build args and the label, not the
# digest.
#
# The gate passes the seven archives of /out and fails if the set does not cover
# the image matrix. --local is the host spot check of task 6.3 and may cover one
# image: it compares the label of the local image of that commit with the label
# inside its archive.
#
# Usage: scripts/ci-verify-build-parity.sh [options] <archive.tar> ...
#   --sha <short-sha>      Commit the archives and images must carry. Defaults to
#                          `git rev-parse --short HEAD`, the derivation of both
#                          build paths.
#   --image-prefix <name>  Image prefix of the local tags (default: domincipe).
#   --local                Compare every archive with the local Docker image
#                          <prefix>/<image>:<sha>. Needs a Docker daemon; the
#                          Images stage runs without this flag.
#
# Exit codes: 0 when the two paths agree, 1 when at least one check fails, 2 on
# a usage error.

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

build_script="${repo_root}/scripts/build-images.sh"
jenkinsfile="${repo_root}/ops/jenkins/Jenkinsfile"
build_helper="${repo_root}/ops/jenkins/vars/ciBuildImage.groovy"
docker_dir="${repo_root}/ops/docker"
label_key='org.opencontainers.image.revision'

expected_sha=''
image_prefix='domincipe'
with_local=false
archives=()

usage() {
  cat <<'USAGE'
Usage: scripts/ci-verify-build-parity.sh [options] <archive.tar> ...

Checks that scripts/build-images.sh and the CI Images stage build the same
images from the same Dockerfiles, with the same build args and the same
org.opencontainers.image.revision label (design D3). Source parity always runs;
the archives are checked against the commit and, with --local, against the local
Docker images of that commit.

Options:
  --sha <short-sha>      Commit the archives and images must carry
                         (default: git rev-parse --short HEAD).
  --image-prefix <name>  Prefix of the local image tags (default: domincipe).
  --local                Compare with the local Docker image of the same commit.
                         Needs a Docker daemon.

Exit codes: 0 when the two paths agree, 1 when at least one check fails, 2 on a
usage error.
USAGE
}

failures=0

fail() {
  echo "ci-verify-build-parity: $*" >&2
  failures=$((failures + 1))
}

while (( $# > 0 )); do
  case "$1" in
    -h | --help)
      usage
      exit 0
      ;;
    --sha)
      if (( $# < 2 )) || [[ -z "${2:-}" ]]; then
        echo 'ci-verify-build-parity: --sha needs a value' >&2
        usage >&2
        exit 2
      fi
      expected_sha="$2"
      shift 2
      ;;
    --sha=*)
      expected_sha="${1#--sha=}"
      if [[ -z "${expected_sha}" ]]; then
        echo 'ci-verify-build-parity: --sha needs a value' >&2
        usage >&2
        exit 2
      fi
      shift
      ;;
    --image-prefix)
      if (( $# < 2 )) || [[ -z "${2:-}" ]]; then
        echo 'ci-verify-build-parity: --image-prefix needs a value' >&2
        usage >&2
        exit 2
      fi
      image_prefix="$2"
      shift 2
      ;;
    --image-prefix=*)
      image_prefix="${1#--image-prefix=}"
      if [[ -z "${image_prefix}" ]]; then
        echo 'ci-verify-build-parity: --image-prefix needs a value' >&2
        usage >&2
        exit 2
      fi
      shift
      ;;
    --local)
      with_local=true
      shift
      ;;
    -*)
      echo "ci-verify-build-parity: unexpected argument '$1'" >&2
      usage >&2
      exit 2
      ;;
    *)
      archives+=("$1")
      shift
      ;;
  esac
done

if (( ${#archives[@]} == 0 )); then
  echo 'ci-verify-build-parity: no archive given' >&2
  usage >&2
  exit 2
fi

# One source of truth for the commit: the same `git rev-parse --short HEAD` both
# build paths run, so a missing --sha cannot silently check a different commit.
if [[ -z "${expected_sha}" ]]; then
  expected_sha="$(git -C "${repo_root}" rev-parse --short HEAD 2>/dev/null)" || {
    echo 'ci-verify-build-parity: cannot read the git revision; pass --sha' >&2
    exit 2
  }
fi

# --- Source parity -----------------------------------------------------------

for required in "${build_script}" "${jenkinsfile}" "${build_helper}"; do
  if [[ ! -f "${required}" ]]; then
    echo "ci-verify-build-parity: ${required#${repo_root}/}: not found" >&2
    exit 1
  fi
done

declare -a ci_images=() local_images=()
declare -A ci_dockerfile=() ci_args_string=() ci_module=() ci_arg_names=()
declare -A required_args_by_dockerfile=()
declare -a local_arg_names=()

# One entry per image in the Jenkinsfile matrix, one line each. A reformat that
# breaks this shape fails the check instead of silently checking nothing.
while IFS=$'\t' read -r image dockerfile args; do
  if [[ -n "${ci_dockerfile[${image}]:-}" ]]; then
    fail "Jenkinsfile: image '${image}' appears more than once in the matrix"
    continue
  fi
  ci_images+=("${image}")
  ci_dockerfile["${image}"]="${dockerfile}"
  ci_args_string["${image}"]="${args}"

  module_string="$(grep -oE "MODULE: '[^']*'" <<<"${args}" || true)"
  if [[ -n "${module_string}" ]]; then
    ci_module["${image}"]="$(sed -E "s/MODULE: '(.*)'/\1/" <<<"${module_string}")"
  fi
  while read -r name; do
    [[ -n "${name}" ]] && ci_arg_names["${name}"]=1
  done < <(grep -oE '[A-Z][A-Z0-9_]*:' <<<"${args}" | tr -d ':')
done < <(
  sed -nE "s/.*\[image: '([^']+)',[[:space:]]*dockerfile: '([^']+)',[[:space:]]*buildArgs: \[([^]]*)\]\].*/\1\t\2\t\3/p" \
    "${jenkinsfile}"
)

if (( ${#ci_images[@]} == 0 )); then
  fail 'Jenkinsfile: no image matrix found; expected one [image: ..., dockerfile: ..., buildArgs: [...]] entry per image'
fi

# The six Java applications live in the java_images array; the SPA is appended to
# known_images. Both are read as the local path declares them, not as a copy.
while read -r image; do
  [[ -n "${image}" ]] && local_images+=("${image}")
done < <(
  awk '
    /^java_images=\($/ { inside = 1; next }
    inside && /^\)$/ { inside = 0; next }
    inside { sub(/#.*/, ""); gsub(/[[:space:]]/, ""); if ($0 != "") print }
  ' "${build_script}"
)
frontend_image="$(sed -nE 's/^known_images=\(.*[[:space:]]([a-z][a-z-]+)\).*$/\1/p' "${build_script}")"
if [[ -n "${frontend_image}" ]]; then
  local_images+=("${frontend_image}")
else
  fail 'scripts/build-images.sh: cannot read the frontend image from known_images='
fi

while read -r name; do
  [[ -n "${name}" ]] && local_arg_names+=("${name}")
done < <(grep -oE -- '--build-arg "[A-Z][A-Z0-9_]*=' "${build_script}" | sed -E 's/.*"//; s/=$//')

# The build args each Dockerfile requires travel in its own ARG lines. Deriving
# them here instead of listing them again keeps a new ARG from being checked in
# one path only. A multi-stage Dockerfile declares the same ARG twice (MODULE in
# both stages), so the list is deduplicated.
for dockerfile_path in "${docker_dir}"/*.Dockerfile; do
  [[ -f "${dockerfile_path}" ]] || continue
  dockerfile_name="$(basename -- "${dockerfile_path}")"
  while read -r arg; do
    [[ -z "${arg}" ]] && continue
    if [[ " ${required_args_by_dockerfile[${dockerfile_name}]:-} " != *" ${arg} "* ]]; then
      required_args_by_dockerfile["${dockerfile_name}"]+="${arg} "
    fi
  done < <(sed -nE 's/^ARG ([A-Z][A-Z0-9_]*).*/\1/p' "${dockerfile_path}")
done

sort_unique() {
  printf '%s\n' "$@" | sed '/^$/d' | sort -u
}

expected_images="$(sort_unique "${local_images[@]}")"
declared_images="$(sort_unique "${ci_images[@]}")"
if [[ "${expected_images}" != "${declared_images}" ]]; then
  fail "image lists differ: scripts/build-images.sh has [$(tr '\n' ' ' <<<"${expected_images}")], Jenkinsfile has [$(tr '\n' ' ' <<<"${declared_images}")]"
fi

# Same Dockerfile set and every Dockerfile reachable from both paths.
for image in "${ci_images[@]}"; do
  dockerfile="${ci_dockerfile[${image}]}"
  if [[ ! -f "${docker_dir}/${dockerfile}" ]]; then
    fail "Jenkinsfile: image '${image}' names ${dockerfile}, which does not exist under ops/docker/"
    continue
  fi
  if ! grep -qF -- "${dockerfile}" "${build_script}"; then
    fail "scripts/build-images.sh never references ${dockerfile}, but the Jenkinsfile builds '${image}' from it"
  fi

  # Every ARG the Dockerfile declares must reach the build. GIT_SHA is injected
  # by ciBuildImage.groovy for all seven images; the rest are declared by the
  # caller, so a missing one would build a different image in each path.
  for arg in ${required_args_by_dockerfile[${dockerfile}]:-}; do
    [[ "${arg}" == 'GIT_SHA' ]] && continue
    if ! grep -qE "(^|[[:space:]\[,])${arg}:" <<<"${ci_args_string[${image}]}"; then
      fail "Jenkinsfile: '${image}' is built from ${dockerfile}, which declares ${arg}, but the entry passes no ${arg}"
    fi
  done
done

for dockerfile in "${!required_args_by_dockerfile[@]}"; do
  for arg in ${required_args_by_dockerfile[${dockerfile}]}; do
    if ! grep -qxF -- "${arg}" <<<"$(sort_unique "${local_arg_names[@]}")"; then
      fail "scripts/build-images.sh does not pass ${arg}, which ${dockerfile} declares"
    fi
  done
done

# GIT_SHA included: the helper injects it for every image, so the matrix does not
# repeat it and the two names sets only match if both paths pass the same args.
if grep -qF 'GIT_SHA: sha' "${build_helper}"; then
  ci_arg_names['GIT_SHA']=1
else
  fail 'ops/jenkins/vars/ciBuildImage.groovy: the GIT_SHA build arg is not injected from the sha argument'
fi
local_args_sorted="$(sort_unique "${local_arg_names[@]}")"
ci_args_sorted="$(printf '%s\n' "${!ci_arg_names[@]}" | sed '/^$/d' | sort -u)"
if [[ "${local_args_sorted}" != "${ci_args_sorted}" ]]; then
  fail "build args differ: scripts/build-images.sh passes [$(tr '\n' ' ' <<<"${local_args_sorted}")], the CI path passes [$(tr '\n' ' ' <<<"${ci_args_sorted}")]"
fi

# MODULE values: the local script declares either a literal (api-gateway) or the
# apps/services/${image} template. A CI value has to match one of those, so a
# swapped module (auth-service built as apps/services/user-service) fails here.
declare -a module_templates=()
while read -r template; do
  [[ -n "${template}" ]] && module_templates+=("${template}")
done < <(grep -oE 'MODULE=[A-Za-z0-9./${}_-]+' "${build_script}" | sed 's/^MODULE=//' | sort -u)

for image in "${ci_images[@]}"; do
  module="${ci_module[${image}]:-}"
  if [[ -z "${module}" ]]; then
    continue
  fi
  matched=false
  for template in "${module_templates[@]}"; do
    if [[ "${module}" == "${template//'${image}'/${image}}" ]]; then
      matched=true
      break
    fi
  done
  if [[ "${matched}" == false ]]; then
    fail "Jenkinsfile: '${image}' receives MODULE=${module}, which matches neither a literal nor the \${image} template of scripts/build-images.sh"
  fi
done

# The SPA bakes the endpoint into the bundle and vite.config.ts fails without it,
# so both paths must resolve the same default.
local_vite_default="$(sed -nE 's/^api_base_url="\$\{VITE_API_BASE_URL:-([^}]*)\}"$/\1/p' "${build_script}")"
ci_vite_default="$(sed -nE "s/^[[:space:]]*VITE_API_BASE_URL = '([^']*)'.*/\1/p" "${jenkinsfile}" | head -1)"
if [[ -z "${local_vite_default}" ]]; then
  fail 'scripts/build-images.sh: cannot read the VITE_API_BASE_URL default'
elif [[ -z "${ci_vite_default}" ]]; then
  fail 'Jenkinsfile: VITE_API_BASE_URL is not defined in the environment block'
elif [[ "${local_vite_default}" != "${ci_vite_default}" ]]; then
  fail "VITE_API_BASE_URL differs: local default '${local_vite_default}', CI '${ci_vite_default}'"
fi

# The short SHA and the revision label are the two strings both paths have to
# write identically.
grep -qF -- '--short HEAD' "${build_script}" \
  || fail 'scripts/build-images.sh: no `rev-parse --short HEAD` derivation found'
grep -qF -- 'git rev-parse --short HEAD' "${jenkinsfile}" \
  || fail 'Jenkinsfile: no `git rev-parse --short HEAD` derivation found'
grep -qF 'GIT_SHA=${short_sha}' "${build_script}" \
  || fail 'scripts/build-images.sh: GIT_SHA is not set from the short SHA'

for dockerfile_path in "${docker_dir}"/*.Dockerfile; do
  [[ -f "${dockerfile_path}" ]] || continue
  grep -qF 'ARG GIT_SHA' "${dockerfile_path}" \
    || fail "$(basename -- "${dockerfile_path}"): no ARG GIT_SHA declared"
  grep -qF "LABEL ${label_key}=\"\${GIT_SHA}\"" "${dockerfile_path}" \
    || fail "$(basename -- "${dockerfile_path}"): no LABEL ${label_key}=\"\${GIT_SHA}\""
done

# --- Artefact parity ---------------------------------------------------------

verify_archive() {
  local archive="$1"
  local name image work index manifest_digest manifest config_digest config
  local label module expected_ref local_label

  name="$(basename -- "${archive}")"
  if [[ "${name}" != *.tar ]]; then
    fail "${archive}: not a .tar OCI archive"
    return
  fi
  image="${name%.tar}"

  if [[ ! -f "${archive}" ]]; then
    fail "${archive}: not a file"
    return
  fi
  if [[ -z "${ci_dockerfile[${image}]:-}" ]]; then
    fail "${archive}: '${image}' is not an image the Jenkinsfile builds"
    return
  fi

  work="$(mktemp -d)"
  if ! index="$(tar -xOf "${archive}" index.json 2>/dev/null)"; then
    rm -rf "${work}"
    fail "${archive}: no index.json at the root (not an OCI layout)"
    return
  fi
  index="$(tr -d '[:space:]' <<<"${index}")"
  manifest_digest="$(grep -oE '"digest":"sha256:[0-9a-f]{64}"' <<<"${index}" \
    | head -1 | sed -E 's/.*sha256:([0-9a-f]{64}).*/\1/')"
  if [[ -z "${manifest_digest}" ]]; then
    rm -rf "${work}"
    fail "${archive}: index.json names no manifest digest"
    return
  fi

  if ! tar -xf "${archive}" -C "${work}" "blobs/sha256/${manifest_digest}" 2>/dev/null; then
    rm -rf "${work}"
    fail "${archive}: manifest blob sha256:${manifest_digest} is not in the archive"
    return
  fi
  # The exporter writes the index compact but the manifest blob pretty-printed
  # (verified in task 6.2), so the blob is normalised before matching.
  manifest="$(tr -d '[:space:]' <"${work}/blobs/sha256/${manifest_digest}")"
  config_digest="$(grep -oE '"config":\{[^}]*\}' <<<"${manifest}" \
    | grep -oE 'sha256:[0-9a-f]{64}' | sed 's/sha256://')"
  if [[ -z "${config_digest}" ]]; then
    rm -rf "${work}"
    fail "${archive}: manifest names no config digest"
    return
  fi

  if ! tar -xOf "${archive}" "blobs/sha256/${config_digest}" >"${work}/config.json" 2>/dev/null; then
    rm -rf "${work}"
    fail "${archive}: config blob sha256:${config_digest} is not in the archive"
    return
  fi
  # The config is kept as written: the history values are strings such as
  # `ARG GIT_SHA=<sha>`, and collapsing their whitespace would turn the ARG name
  # into ARGGIT_SHA. Structural whitespace is tolerated by the patterns instead.
  config="$(<"${work}/config.json")"
  rm -rf "${work}"

  label="$(grep -oE "\"${label_key//./\\.}\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" <<<"${config}" \
    | head -1 | sed -E 's/.*:[[:space:]]*"([^"]*)"$/\1/')"
  if [[ -z "${label}" ]]; then
    fail "${archive}: the image config carries no ${label_key} label"
  elif [[ "${label}" != "${expected_sha}" ]]; then
    fail "${archive}: ${label_key} is '${label}', expected '${expected_sha}'"
  fi

  # The label proves the final value; the history shows the ARG that produced it,
  # which is the part shared with scripts/build-images.sh.
  if ! grep -qE "\"created_by\"[[:space:]]*:[[:space:]]*\"ARG GIT_SHA=${expected_sha}\"" <<<"${config}"; then
    fail "${archive}: the config history does not record ARG GIT_SHA=${expected_sha}"
  fi

  module="${ci_module[${image}]:-}"
  if [[ -n "${module}" ]]; then
    if ! grep -qE "\"created_by\"[[:space:]]*:[[:space:]]*\"ARG MODULE=${module}\"" <<<"${config}"; then
      fail "${archive}: the config history does not record ARG MODULE=${module}"
    fi
  elif grep -qE '"created_by"[[:space:]]*:[[:space:]]*"ARG MODULE=' <<<"${config}"; then
    fail "${archive}: '${image}' must not receive a MODULE build arg"
  fi

  if [[ "${with_local}" == true ]]; then
    if ! command -v docker >/dev/null 2>&1; then
      fail '--local needs a Docker daemon, but the docker CLI is not in PATH'
      return
    fi
    expected_ref="${image_prefix}/${image}:${expected_sha}"
    if ! local_label="$(docker image inspect --format \
      "{{index .Config.Labels \"${label_key}\"}}" "${expected_ref}" 2>/dev/null)"; then
      fail "${expected_ref}: no local image; run scripts/build-images.sh ${image} for commit ${expected_sha}"
      return
    fi
    if [[ "${local_label}" != "${label}" ]]; then
      fail "${archive}: ${label_key} is '${label}' in the CI archive but '${local_label}' in ${expected_ref}"
    fi
  fi

  echo "ci-verify-build-parity: ${archive}: ${label_key}=${label} (${image} from ${ci_dockerfile[${image}]})"
}

for archive in "${archives[@]}"; do
  verify_archive "${archive}"
done

# One archive per image, not a subset: a missing one would otherwise let an image
# go unchecked in the gate. The host spot check (--local) may cover one image
# instead, because the task compares the label of a local image with the archive
# of the same commit.
if (( ${#ci_images[@]} > 0 )) && [[ "${with_local}" == false ]]; then
  archive_images="$(for archive in "${archives[@]}"; do
    basename -- "${archive}" .tar
  done | sort -u)"
  if [[ "${archive_images}" != "${declared_images}" ]]; then
    fail "archives do not cover the image matrix: checked [$(tr '\n' ' ' <<<"${archive_images}")], expected [$(tr '\n' ' ' <<<"${declared_images}")]"
  fi
fi

if (( failures > 0 )); then
  echo "ci-verify-build-parity: ${failures} check(s) failed" >&2
  exit 1
fi

echo "ci-verify-build-parity: OK (${#archives[@]} archive(s) at ${expected_sha}; Dockerfiles, build args and ${label_key} agree between scripts/build-images.sh and the CI path)"

