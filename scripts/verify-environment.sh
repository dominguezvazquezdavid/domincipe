#!/usr/bin/env bash
#
# Verifies the provisioning of the running local environment: the five
# PostgreSQL schemas, the six Kafka topics of the event contract, the Versity
# bucket and the Mailpit SMTP listener.
#
# It is read-only on purpose. Nothing is created or fixed here, so a failure
# names the init container that did not do its job (postgres-init, kafka-init,
# versity-init) instead of being hidden by a check that repairs what it
# measures.
#
# Usage: scripts/verify-environment.sh
#
# The Compose files come from COMPOSE_FILE, exactly as the canonical
# `docker compose up --wait` reads them (.env in the repository root, or the
# environment), so the script inspects the same project that is running.
#
# Exit codes: 0 when every check passes, 1 when one fails, 2 on a usage error.

set -euo pipefail

# Resolve the repository root from this script's location: .env lives there, and
# the relative paths of COMPOSE_FILE are resolved from the directory Compose runs
# in, not from the caller's.
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

# Contract of PROJECT.md §5: one schema per service and one topic per domain
# event. Both lists are the expected state, so they are never read back from the
# environment being checked.
expected_schemas=(auth users recipes media notifications)
expected_topics=(
  user.registered
  user.updated
  recipe.created
  recipe.updated
  recipe.deleted
  media.uploaded
)

usage() {
  cat <<'USAGE'
Usage: scripts/verify-environment.sh

Checks that the running local environment provisioned its data: the five
PostgreSQL schemas, the six Kafka topics of the event contract, the Versity
bucket and the Mailpit SMTP listener.

Read-only, and it uses the Compose files declared by COMPOSE_FILE (the project's
.env or the environment), so start the environment first with
`docker compose up --wait`.

Exit codes: 0 when every check passes, 1 when one fails, 2 on a usage error.
USAGE
}

fail() {
  echo "verify-environment: $*" >&2
  exit 1
}

# True when the first argument is exactly one of the rest.
contains() {
  local needle="$1" candidate
  shift
  for candidate in "$@"; do
    [[ "${candidate}" == "${needle}" ]] && return 0
  done
  return 1
}

# Every Docker call goes through here: the working directory is the repository
# root because that is where Compose finds .env, no matter where the script was
# launched from.
compose() {
  (cd -- "${repo_root}" && docker compose "$@")
}

for argument in "$@"; do
  case "${argument}" in
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "verify-environment: unexpected argument '${argument}'" >&2
      usage >&2
      exit 2
      ;;
  esac
done

command -v docker >/dev/null 2>&1 || fail "docker CLI not found in PATH"

# Resolved before probing anything: a missing file or an empty COMPOSE_FILE would
# otherwise surface as four unrelated "no configuration file provided" errors.
compose config --quiet >/dev/null 2>&1 \
  || fail "cannot resolve the Compose configuration; check COMPOSE_FILE (.env or the environment) and that every file it lists exists"

# \dn through --no-align/--tuples-only prints one "name|owner" row per schema,
# which is the documented catalog view without parsing the padded table.
check_schemas() {
  local listing row name
  local -a names=() absent=()
  if ! listing="$(printf '%s\n' '\dn' \
    | compose exec -T postgres sh -c 'psql --username="$POSTGRES_USER" --dbname="$POSTGRES_DB" --no-psqlrc --no-align --tuples-only' 2>&1)"; then
    fail "cannot list the PostgreSQL schemas; is the environment up? (${listing})"
  fi
  while IFS='|' read -r name _; do
    [[ -n "${name}" ]] && names+=("${name}")
  done <<<"${listing}"
  for schema in "${expected_schemas[@]}"; do
    contains "${schema}" "${names[@]:-}" || absent+=("${schema}")
  done
  if (( ${#absent[@]} > 0 )); then
    fail "missing PostgreSQL schema(s): ${absent[*]} (expected: ${expected_schemas[*]}; see postgres-init)"
  fi
  echo "verify-environment: OK PostgreSQL schemas (${#expected_schemas[@]}): ${expected_schemas[*]}"
}

# The broker is asked for its topic list, not for a TCP port: kafka-init uses the
# same metadata request, so both see the same API.
check_topics() {
  local listing topic
  local -a absent=()
  if ! listing="$(compose exec -T kafka /opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 --list 2>&1)"; then
    fail "cannot list the Kafka topics; is the environment up? (${listing})"
  fi
  for topic in "${expected_topics[@]}"; do
    grep -qxF -- "${topic}" <<<"${listing}" || absent+=("${topic}")
  done
  if (( ${#absent[@]} > 0 )); then
    fail "missing Kafka topic(s): ${absent[*]} (see kafka-init)"
  fi
  echo "verify-environment: OK Kafka topics (${#expected_topics[@]}): ${expected_topics[*]}"
}

# The bucket is probed with the client and the credentials of versity-init, so a
# pass means the bucket is reachable by the application (and by the container
# that creates it), not that some directory exists on the volume.
check_bucket() {
  local bucket="${MEDIA_BUCKET:-domincipe-media}" result
  if ! result="$(compose run --rm --no-deps --entrypoint /bin/sh versity-init \
    -c 'aws --endpoint-url http://versity:7070 s3api head-bucket --bucket "$BUCKET"' 2>&1)"; then
    fail "bucket '${bucket}' is not available in Versity (see versity-init): ${result}"
  fi
  echo "verify-environment: OK Versity bucket: ${bucket}"
}

# The SMTP server speaks first, so the 220 greeting proves the listener accepts a
# connection and answers the protocol. The probe runs from the kafka container
# because it is the container on backend-net that carries bash (/dev/tcp) and
# timeout; a probe from inside mailpit would not exercise the network path.
check_smtp() {
  local banner
  if ! banner="$(compose exec -T kafka timeout 5 /bin/bash -c \
    'exec 3<>/dev/tcp/mailpit/1025; head -c 3 <&3; exec 3<&-' 2>&1)"; then
    fail "Mailpit SMTP does not accept connections on mailpit:1025 (${banner})"
  fi
  if [[ "${banner}" != "220" ]]; then
    fail "Mailpit SMTP did not send an SMTP greeting (received '${banner}')"
  fi
  echo "verify-environment: OK Mailpit SMTP listening on mailpit:1025"
}

check_schemas
check_topics
check_bucket
check_smtp

echo "verify-environment: OK (schemas, topics, bucket and SMTP verified)"

