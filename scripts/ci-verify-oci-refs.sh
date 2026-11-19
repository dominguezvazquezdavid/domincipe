#!/usr/bin/env bash
#
# Verifies that the two references of an OCI archive written by buildctl resolve
# to the same manifest (design D3, task 6.2).
#
# The Images stage writes both tags in a single `--output` precisely so they
# cannot drift apart (D3). A property that is only designed is not a property:
# this check turns it into a gate, so a divergence fails the build instead of
# shipping `latest` and the sha tag pointing at different images. It fails on:
# two different digests, a repeated tag, a digest whose blob is missing from the
# archive, a blob that does not hash to its digest, and (with --sha) a tag that
# is not the commit being built.
#
# It reads the archive with tar, grep and sha256sum only: the controller image
# has neither jq nor python, and adding one just for this check would change the
# pinned toolchain of design D5.
#
# Usage: scripts/ci-verify-oci-refs.sh [--sha <short-sha>] <archive.tar> ...
#   <archive.tar>      OCI archive to verify; every one is checked.
#   --sha <short-sha>  Also require the references to be exactly <short-sha> and
#                      `latest`. The Images stage passes the sha it built with.
#
# Exit codes: 0 when every archive passes, 1 when at least one fails, 2 on a
# usage error.

set -euo pipefail

manifest_media_type='application/vnd.oci.image.manifest.v1+json'
index_media_type='application/vnd.oci.image.index.v1+json'
ref_name_key='org.opencontainers.image.ref.name'

expected_sha=''
archives=()

usage() {
  cat <<'USAGE'
Usage: scripts/ci-verify-oci-refs.sh [--sha <short-sha>] <archive.tar> ...

Checks that every OCI archive carries two distinct references (`<short-sha>` and
`latest` when --sha is given) pointing at one manifest, that the manifest blob is
present in the archive and that it hashes to the digest the index names.

Read-only. The Images stage runs it after the seven builds (design D3).

Exit codes: 0 when every archive passes, 1 when at least one fails, 2 on a usage
error.
USAGE
}

failures=0

fail() {
  echo "ci-verify-oci-refs: $*" >&2
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
        echo 'ci-verify-oci-refs: --sha needs a value' >&2
        usage >&2
        exit 2
      fi
      expected_sha="$2"
      shift 2
      ;;
    --sha=*)
      expected_sha="${1#--sha=}"
      if [[ -z "${expected_sha}" ]]; then
        echo 'ci-verify-oci-refs: --sha needs a value' >&2
        usage >&2
        exit 2
      fi
      shift
      ;;
    -*)
      echo "ci-verify-oci-refs: unexpected argument '$1'" >&2
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
  echo 'ci-verify-oci-refs: no archive given' >&2
  usage >&2
  exit 2
fi

verify_archive() {
  local archive="$1"

  if [[ ! -f "${archive}" ]]; then
    fail "${archive}: not a file"
    return
  fi

  local index_json
  if ! index_json="$(tar -xOf "${archive}" index.json 2>/dev/null)"; then
    fail "${archive}: no index.json at the root (not an OCI layout)"
    return
  fi

  # The exporter writes compact JSON; whitespace is stripped so the patterns
  # below also match a re-serialised copy. Every value read here —digests, tags,
  # media types— is whitespace-free, so nothing is lost.
  local compact
  compact="$(printf '%s' "${index_json}" | tr -d '[:space:]')"

  if [[ "${compact}" != *'"schemaVersion":2'* ]]; then
    fail "${archive}: index.json does not declare schemaVersion 2"
    return
  fi
  if [[ "${compact}" != *"\"mediaType\":\"${index_media_type}\""* ]]; then
    fail "${archive}: index.json is not an OCI image index"
    return
  fi

  local -a digests=() ref_names=()
  # Digests lose the algorithm prefix: they double as blob file names.
  mapfile -t digests < <(
    grep -oE '"digest":"sha256:[0-9a-f]{64}"' <<<"${compact}" \
      | sed -E 's/.*sha256:([0-9a-f]{64}).*/\1/'
  )
  mapfile -t ref_names < <(
    grep -oE "\"${ref_name_key}\":\"[^\"]*\"" <<<"${compact}" \
      | sed -E 's/.*:"(.*)"$/\1/'
  )

  local entries
  entries="$(grep -oF "\"mediaType\":\"${manifest_media_type}\"" <<<"${compact}" | wc -l)"

  if (( entries != 2 )); then
    fail "${archive}: index.json describes ${entries} manifest(s), expected 2 (one per reference)"
    return
  fi
  if (( ${#ref_names[@]} != 2 )); then
    fail "${archive}: ${#ref_names[@]} reference name(s) in index.json, expected 2"
    return
  fi
  if (( ${#digests[@]} != 2 )); then
    fail "${archive}: ${#digests[@]} manifest digest(es) in index.json, expected 2"
    return
  fi

  local distinct
  distinct="$(printf '%s\n' "${ref_names[@]}" | sort -u | wc -l)"
  if (( distinct != 2 )); then
    fail "${archive}: both references are '${ref_names[0]}'; they must be distinct tags"
    return
  fi

  if [[ "${digests[0]}" != "${digests[1]}" ]]; then
    fail "${archive}: '${ref_names[0]}' -> sha256:${digests[0]} and '${ref_names[1]}' -> sha256:${digests[1]} resolve to different manifests"
    return
  fi

  if [[ -n "${expected_sha}" ]]; then
    local expected actual
    expected="$(printf '%s\n' "${expected_sha}" latest | sort)"
    actual="$(printf '%s\n' "${ref_names[@]}" | sort)"
    if [[ "${expected}" != "${actual}" ]]; then
      fail "${archive}: references '${ref_names[0]}' and '${ref_names[1]}' are not '${expected_sha}' and 'latest'"
      return
    fi
  fi

  # Both references name the same digest, but a digest in an index proves nothing
  # until the blob it names is in the archive and hashes to it: that is what
  # "resolves to the same manifest" means physically.
  local hex="${digests[0]}" work actual_hash
  work="$(mktemp -d)"
  if ! tar -xf "${archive}" -C "${work}" "blobs/sha256/${hex}" 2>/dev/null; then
    rm -rf "${work}"
    fail "${archive}: sha256:${hex} is referenced but its blob is not in the archive"
    return
  fi
  actual_hash="$(sha256sum "${work}/blobs/sha256/${hex}" | cut -d' ' -f1)"
  if [[ "${actual_hash}" != "${hex}" ]]; then
    rm -rf "${work}"
    fail "${archive}: blob blobs/sha256/${hex} hashes to ${actual_hash}; the digest does not match its content"
    return
  fi
  # The exporter writes the index compact but the manifest blob pretty-printed
  # (verified on the seven archives of task 6.1), so the blob is normalised the
  # same way before matching.
  if ! tr -d '[:space:]' <"${work}/blobs/sha256/${hex}" \
    | grep -qF "\"mediaType\":\"${manifest_media_type}\""; then
    rm -rf "${work}"
    fail "${archive}: blob sha256:${hex} is not an image manifest"
    return
  fi
  rm -rf "${work}"

  echo "ci-verify-oci-refs: ${archive}: ${ref_names[0]} and ${ref_names[1]} -> sha256:${hex}"
}

for archive in "${archives[@]}"; do
  verify_archive "${archive}"
done

if (( failures > 0 )); then
  echo "ci-verify-oci-refs: ${failures} archive(s) failed" >&2
  exit 1
fi

echo "ci-verify-oci-refs: OK (${#archives[@]} archive(s); each one carries two references on a single manifest)"
