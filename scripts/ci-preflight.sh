#!/usr/bin/env bash
#
# Host preflight for the CI stack of ops/jenkins/docker-compose.yml: checks that
# this machine can run the rootless BuildKit builder and publish the Jenkins
# controller, before `up` is attempted (design D1).
#
# It must run on the host, not in a container: the sysctls, /etc/subuid and
# /etc/subgid read from inside a container are the container's, and they are not
# what rootlesskit will consume. A green run there would mean nothing.
#
# It is read-only on purpose. Nothing is created, loaded or fixed here, so a
# failure names the requirement and the command that adjusts it instead of being
# hidden behind a check that repairs what it measures.
#
# Usage: scripts/ci-preflight.sh
#
# Environment:
#   JENKINS_PORT  Port the stack publishes. Same precedence as Compose: the shell
#                 environment, then ops/jenkins/.env, then the default of the
#                 Compose file (8095, design D11).
#
# Exit codes: 0 when every requirement holds, 1 when one fails, 2 on a usage
# error.

set -euo pipefail

# Resolve the repository root from this script's location: the Compose file and
# its project directory are relative to the root, not to the caller.
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
ci_dir="${repo_root}/ops/jenkins"
compose_file="${ci_dir}/docker-compose.yml"

# Kernel 5.11 is the first whose overlayfs can back the rootless snapshotter
# (design D1). Below it BuildKit falls back to fuse-overlayfs, which is slower
# and needs /dev/fuse, hence the switch below.
overlayfs_min_major=5
overlayfs_min_minor=11
fuse_required=0

usage() {
  cat <<'USAGE'
Usage: scripts/ci-preflight.sh

Checks, on the host, the requirements of the rootless BuildKit builder: docker
compose, kernel >= 5.11 (a warning otherwise: the builder falls back to
fuse-overlayfs), user namespaces, the AppArmor user-namespace restriction,
/etc/subuid and /etc/subgid, /dev/fuse and a free Jenkins port.

Read-only. Run it before
`docker compose -f ops/jenkins/docker-compose.yml up --wait`.

Environment: JENKINS_PORT (shell environment, then ops/jenkins/.env, then 8095).

Exit codes: 0 when every requirement holds, 1 when one fails, 2 on a usage error.
USAGE
}

fail() {
  echo "ci-preflight: $*" >&2
  exit 1
}

warn() {
  echo "ci-preflight: warning: $*" >&2
}

for argument in "$@"; do
  case "${argument}" in
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "ci-preflight: unexpected argument '${argument}'" >&2
      usage >&2
      exit 2
      ;;
  esac
done

# The daemon itself is not probed here: `up` will report an unreachable daemon.
# What this check catches is a host with the docker CLI but without the Compose
# v2 plugin, which is the mistake the invocation would surface much later.
check_docker_compose() {
  local version
  command -v docker >/dev/null 2>&1 || fail "docker CLI not found in PATH"
  version="$(docker compose version 2>&1)" \
    || fail "docker compose is not available (the Compose v2 plugin is required): ${version}"
  printf 'ci-preflight: OK %s\n' "${version//$'\n'/ }"
}

check_kernel() {
  local release major minor _
  release="$(uname -r)"
  # 7.0.0-38-generic -> major=7, minor=0; the suffix after the second dot is not
  # part of the comparison.
  IFS=. read -r major minor _ <<<"${release}"
  if [[ ! "${major}" =~ ^[0-9]+$ || ! "${minor}" =~ ^[0-9]+$ ]]; then
    warn "cannot parse the kernel release '${release}'; assuming overlayfs is available"
    return 0
  fi
  if ((major > overlayfs_min_major || (major == overlayfs_min_major && minor >= overlayfs_min_minor))); then
    printf 'ci-preflight: OK kernel %s (>= %d.%d: the rootless builder uses overlayfs)\n' \
      "${release}" "${overlayfs_min_major}" "${overlayfs_min_minor}"
    return 0
  fi
  fuse_required=1
  warn "kernel ${release} is older than ${overlayfs_min_major}.${overlayfs_min_minor}: the rootless builder will use fuse-overlayfs, so /dev/fuse becomes mandatory"
}

# rootlesskit creates a user namespace for the builder; with the knob at 0 it
# fails with "user.max_user_namespaces needs to be set to non-zero" before
# Jenkins ever sees a build.
check_user_namespaces() {
  local value
  value="$(sysctl -n user.max_user_namespaces 2>/dev/null)" \
    || fail "cannot read user.max_user_namespaces (sysctl unavailable or the key is missing): the rootless builder needs unprivileged user namespaces in this kernel"
  [[ "${value}" =~ ^[0-9]+$ ]] \
    || fail "user.max_user_namespaces returned '${value}', which is not a number"
  if ((value == 0)); then
    fail "user.max_user_namespaces is 0 and the rootless builder cannot create its namespace: run 'sudo sysctl -w user.max_user_namespaces=56066' and persist it in /etc/sysctl.d/"
  fi
  printf 'ci-preflight: OK user.max_user_namespaces = %s\n' "${value}"
}

# Ubuntu 24.04 and later restrict unprivileged user namespaces through AppArmor;
# with the knob at 1 rootlesskit fails with "fork/exec /proc/self/exe: permission
# denied". Hosts without AppArmor do not publish the key at all, so its absence is
# not a failure.
check_apparmor_userns() {
  local value
  if ! value="$(sysctl -n kernel.apparmor_restrict_unprivileged_userns 2>/dev/null)"; then
    printf 'ci-preflight: OK kernel.apparmor_restrict_unprivileged_userns not present (no AppArmor user-namespace restriction to lift)\n'
    return 0
  fi
  if [[ "${value}" != "0" ]]; then
    fail "kernel.apparmor_restrict_unprivileged_userns is ${value} and the rootless builder needs 0: add 'kernel.apparmor_restrict_unprivileged_userns=0' to /etc/sysctl.d/ and run 'sudo sysctl -p'"
  fi
  printf 'ci-preflight: OK kernel.apparmor_restrict_unprivileged_userns = 0\n'
}

# A user-namespace mapping needs a subordinate range outside the user's own IDs.
# Entries are matched by name (the customary form) as well as by numeric uid/gid.
check_subid_file() {
  local file="$1" usermod_flag="$2" name start count
  [[ -r "${file}" ]] || fail "${file} is not readable: the rootless builder maps subordinate IDs from it"
  while IFS=: read -r name start count; do
    if [[ "${name}" == "${subid_user}" || "${name}" == "${subid_uid}" ]]; then
      printf 'ci-preflight: OK %s: %s:%s:%s\n' "${file}" "${name}" "${start}" "${count}"
      return 0
    fi
  done <"${file}"
  fail "no entry for '${subid_user}' in ${file}: add a subordinate range with 'sudo usermod ${usermod_flag} 100000-165535 ${subid_user}'"
}

check_subordinate_ids() {
  subid_user="${USER:-$(id -un)}"
  subid_uid="$(id -u)"
  check_subid_file /etc/subuid --add-subuids
  check_subid_file /etc/subgid --add-subgids
}

# /dev/fuse is only used by the fuse-overlayfs snapshotter, so it is mandatory on
# kernels older than 5.11 and informational on the rest (design D1).
check_fuse() {
  if [[ -e /dev/fuse && -r /dev/fuse && -w /dev/fuse ]]; then
    printf 'ci-preflight: OK /dev/fuse present and readable/writable\n'
    return 0
  fi
  if ((fuse_required)); then
    fail "/dev/fuse is missing or not accessible and kernel $(uname -r) is older than ${overlayfs_min_major}.${overlayfs_min_minor}: load the module with 'sudo modprobe fuse' or use a kernel with overlayfs"
  fi
  warn "/dev/fuse is missing or not accessible; unused with the overlayfs snapshotter, but the fuse-overlayfs fallback would not work"
}

# The port is resolved with Compose's own precedence, because preflight has to
# probe the port the stack will really publish.
resolve_jenkins_port() {
  local env_file="${ci_dir}/.env" line value
  if [[ -n "${JENKINS_PORT:-}" ]]; then
    printf '%s\n' "${JENKINS_PORT}"
    return 0
  fi
  if [[ -r "${env_file}" ]]; then
    while IFS= read -r line || [[ -n "${line}" ]]; do
      # Trim leading whitespace so `KEY=value` is still recognised when indented.
      line="${line#"${line%%[![:space:]]*}"}"
      [[ "${line}" == JENKINS_PORT=* ]] || continue
      value="${line#JENKINS_PORT=}"
      # Trailing whitespace, then one pair of surrounding quotes.
      value="${value%"${value##*[![:space:]]}"}"
      value="${value%\"}"
      value="${value#\"}"
      value="${value%\'}"
      value="${value#\'}"
      printf '%s\n' "${value}"
      return 0
    done <"${env_file}"
  fi
  printf '8095\n'
}

# `up` is idempotent, so a port already published by this very stack is not a
# conflict with itself; any other listener is, and is named as such.
check_jenkins_port() {
  local port="$1" owner
  [[ "${port}" =~ ^[0-9]+$ ]] \
    || fail "JENKINS_PORT '${port}' is not a port number: fix the shell environment or ops/jenkins/.env"
  if ((port < 1 || port > 65535)); then
    fail "JENKINS_PORT '${port}' is outside the valid range 1-65535"
  fi
  owner="$(docker compose -f "${compose_file}" ps --quiet jenkins 2>/dev/null || true)"
  if [[ -n "${owner}" ]]; then
    printf 'ci-preflight: OK port %s is already published by this stack (jenkins is running)\n' "${port}"
    return 0
  fi
  # bash's /dev/tcp needs no extra tool: a successful connect means a listener is
  # there, and Compose publishes on 0.0.0.0, which loopback reaches.
  if (exec 3<>"/dev/tcp/127.0.0.1/${port}") 2>/dev/null; then
    fail "port ${port} is already in use by another process: stop it or set JENKINS_PORT to a free port in ops/jenkins/.env (8095 is reserved for the CI stack, design D11)"
  fi
  printf 'ci-preflight: OK port %s is free for the Jenkins controller\n' "${port}"
}

[[ -r "${compose_file}" ]] \
  || fail "${compose_file} not found: this script runs from a clone of the repository"

jenkins_port="$(resolve_jenkins_port)"

check_docker_compose
check_kernel
check_user_namespaces
check_apparmor_userns
check_subordinate_ids
check_fuse
check_jenkins_port "${jenkins_port}"

echo "ci-preflight: OK (host ready for the CI stack)"
