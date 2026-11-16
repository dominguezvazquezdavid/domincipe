#!/usr/bin/env bash
#
# Builds the container images of the monorepo and tags each one twice: with the
# short git SHA, which is the immutable reference deployments and rollbacks use,
# and with `latest`, the moving pointer local `docker compose` runs consume.
# Both tags are applied by a single `docker build`, so they cannot drift apart
# (design D11, PROJECT.md §9).
#
# Usage: scripts/build-images.sh [image ...]
#   image  Build only the named images. A name is one of api-gateway,
#          auth-service, user-service, recipe-service, media-service,
#          notification-service or web-frontend. Without arguments every image
#          is built.
#
# Environment:
#   IMAGE_PREFIX       Tag prefix (default: domincipe).
#   VITE_API_BASE_URL  API endpoint baked into the frontend bundle. The build
#                      fails without it (design D13), so the api-gateway port of
#                      the local environment is the default.
#
# Exit codes: 0 when every requested image is built and both tags match, 1 on a
# build or verification failure, 2 on a usage error.

set -euo pipefail

# Resolve the repository root from this script's location: the Docker build
# context and the git metadata are relative to the root, not to the caller.
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

image_prefix="${IMAGE_PREFIX:-domincipe}"
api_base_url="${VITE_API_BASE_URL:-http://localhost:8080}"

java_dockerfile="${repo_root}/ops/docker/java-service.Dockerfile"
frontend_dockerfile="${repo_root}/ops/docker/web-frontend.Dockerfile"

# The six Java applications share one parameterised Dockerfile and differ only in
# the Maven module; the frontend owns its build and runtime stages.
java_images=(
  api-gateway
  auth-service
  user-service
  recipe-service
  media-service
  notification-service
)
known_images=("${java_images[@]}" web-frontend)

usage() {
  cat <<'USAGE'
Usage: scripts/build-images.sh [image ...]

Builds the container images of the monorepo and tags each one with the short git
SHA and with `latest`.

Images: api-gateway, auth-service, user-service, recipe-service, media-service,
notification-service, web-frontend. Without arguments every image is built.

Environment: IMAGE_PREFIX (default: domincipe), VITE_API_BASE_URL
(default: http://localhost:8080).
USAGE
}

fail() {
  echo "build-images: $*" >&2
  exit 1
}

selected=()
for argument in "$@"; do
  case "${argument}" in
    -h | --help)
      usage
      exit 0
      ;;
    -*)
      echo "build-images: unknown option ${argument}" >&2
      usage >&2
      exit 2
      ;;
    *)
      selected+=("${argument}")
      ;;
  esac
done

if (( ${#selected[@]} == 0 )); then
  selected=("${known_images[@]}")
fi

# An unknown name would otherwise build nothing and report success, which is the
# worst possible outcome for a release script.
for image in "${selected[@]}"; do
  known=false
  for candidate in "${known_images[@]}"; do
    if [[ "${image}" == "${candidate}" ]]; then
      known=true
      break
    fi
  done
  if [[ "${known}" == false ]]; then
    echo "build-images: unknown image '${image}'" >&2
    echo "Known images: ${known_images[*]}" >&2
    exit 2
  fi
done

command -v docker >/dev/null 2>&1 || fail "docker CLI not found in PATH"
command -v git >/dev/null 2>&1 || fail "git CLI not found in PATH"

# The short SHA is what makes a deployment reproducible: without a commit there
# is no immutable identifier to tag with.
short_sha="$(git -C "${repo_root}" rev-parse --short HEAD 2>/dev/null)" \
  || fail "cannot read the git revision at ${repo_root}"

built=()

for image in "${selected[@]}"; do
  tag_sha="${image_prefix}/${image}:${short_sha}"
  tag_latest="${image_prefix}/${image}:latest"

  build_args=(--build-arg "GIT_SHA=${short_sha}")
  case "${image}" in
    web-frontend)
      dockerfile="${frontend_dockerfile}"
      build_args+=(--build-arg "VITE_API_BASE_URL=${api_base_url}")
      ;;
    api-gateway)
      dockerfile="${java_dockerfile}"
      build_args+=(--build-arg "MODULE=apps/api-gateway")
      ;;
    *)
      dockerfile="${java_dockerfile}"
      build_args+=(--build-arg "MODULE=apps/services/${image}")
      ;;
  esac

  echo "build-images: building ${tag_sha} (also tagged ${tag_latest})"
  docker build \
    --file "${dockerfile}" \
    --tag "${tag_sha}" \
    --tag "${tag_latest}" \
    "${build_args[@]}" \
    "${repo_root}"

  # Both tags come from a single build, so a mismatch would mean the daemon
  # applied them to different images. Verified instead of assumed.
  sha_id="$(docker image inspect --format '{{.Id}}' "${tag_sha}")"
  latest_id="$(docker image inspect --format '{{.Id}}' "${tag_latest}")"
  if [[ "${sha_id}" != "${latest_id}" ]]; then
    fail "${tag_sha} and ${tag_latest} resolve to different images (${sha_id} vs ${latest_id})"
  fi

  built+=("${tag_sha}|${tag_latest}|${sha_id}")
done

echo "build-images: OK (${#built[@]} image(s), git ${short_sha})"
for entry in "${built[@]}"; do
  IFS='|' read -r tag_sha tag_latest image_id <<<"${entry}"
  # Drop the 'sha256:' prefix so both tags read as the same 12-hex-digit ID that
  # `docker image ls` prints.
  printf '  %s\n  %s\n    image id %s\n' "${tag_sha}" "${tag_latest}" "${image_id#sha256:}"
done
