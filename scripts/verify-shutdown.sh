#!/usr/bin/env bash
#
# Verifies the ordered shutdown of a Java service of the local environment: it
# opens an HTTP request, runs `docker compose stop` while the service is still
# writing the response and checks that the request finishes with the expected
# body and that the container left through its normal shutdown path.
#
# Usage: scripts/verify-shutdown.sh [service]
#
# The service defaults to api-gateway, the entry point of the frontend. It must
# be one of the Java services (it serves springdoc with APP_DOCS_ENABLED=true,
# the default). The Swagger UI bundle is the largest response the service
# produces and three pipelined copies of it do not fit in the socket buffers,
# which is what keeps the first response being written when the stop signal
# arrives; a normal request finishes in milliseconds and the kernel absorbs the
# whole response, so it would prove nothing.
#
# The client talks to the container directly, at its IP on the Compose network,
# instead of the published port: the userland proxy Docker puts in front of a
# published port buffers megabytes, so the service never blocks and the stop
# finishes before the request is drained, which makes the check depend on the
# luck of the buffer sizes. The direct path is measured and stable on Linux;
# Docker Desktop does not route to container IPs and is out of scope.
#
# When Compose talks to a remote daemon (the CI stack) those addresses exist over
# there and not here, so --client-service moves both the reference request and
# the slow client inside the project network instead of falling back to a
# published port, which would measure something else (change ci-integration, D8).
#
# Exit code of the container: 0 or 143 (128 + SIGTERM) mean a healthy ordered
# shutdown; 137 (128 + SIGKILL) means the grace period expired before the drain
# finished and is a failure. The JVM exits with 143 after handling SIGTERM, so
# requiring exactly 0 would demand an entrypoint wrapper that rewrites the exit
# code and hides whether the stop was external (design D19).
#
# The service is restarted at the end, so the environment is left as it was
# found. The Compose files come from COMPOSE_FILE, exactly as the canonical
# `docker compose up --wait` reads them (.env in the repository root, or the
# environment).
#
# Exit codes: 0 when every check passes, 1 when one fails, 2 on a usage error.

set -euo pipefail

# Resolve the repository root from this script's location: .env lives there, and
# the relative paths of COMPOSE_FILE are resolved from the directory Compose runs
# in, not from the caller's.
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

# Biggest response served without business endpoints: 1.68 MB of springdoc.
slow_path="/swagger-ui/swagger-ui-bundle.js"
# Three copies of the bundle exceed the socket buffers the kernel can hold for
# this connection, so the first response is still being written when the stop
# arrives (measured: the stop waits ~3.3 s on three consecutive runs; D19).
request_count=3
# Window during which the client does not read, in whole seconds.
hold_seconds=4
# Delay between the requests being in flight and the stop, in whole seconds.
stop_delay_seconds=1

usage() {
  cat <<'USAGE'
Usage: scripts/verify-shutdown.sh [--client-service=<name>] [service]

Opens an HTTP request to a Java service of the running local environment, runs
`docker compose stop` while the response is still being written and checks that
the request completes with the expected body and that the container exits
through its normal shutdown path (0 or 143, never 137).

service (default: api-gateway) must be a Java service serving springdoc.

--client-service=<name> runs both the reference request and the slow client
inside a Compose service of the project instead of on this host: required when
Compose talks to a remote daemon (the CI stack), where the container addresses
do not exist here. The named service needs python3 and a network in common with
service, and `ops/compose/docker-compose.ci.yml` declares one for that purpose.

The service is restarted at the end, so the environment is left as it was found.
Start the environment first with `docker compose up --wait`.

Exit codes: 0 when every check passes, 1 when one fails, 2 on a usage error.
USAGE
}

fail() {
  echo "verify-shutdown: $*" >&2
  exit 1
}

# Every Docker call goes through here: the working directory is the repository
# root because that is where Compose finds .env, no matter where the script was
# launched from.
compose() {
  (cd -- "${repo_root}" && docker compose "$@")
}

# Milliseconds, so the stop can be compared with the moment the client starts
# reading: a stop that finishes earlier had nothing in flight.
now_ms() {
  if [[ -n "${EPOCHREALTIME:-}" ]]; then
    local value="${EPOCHREALTIME//[.,]/}"
    printf '%s' "$(( value / 1000 ))"
  else
    printf '%s' "$(( $(date +%s) * 1000 ))"
  fi
}

service="api-gateway"
positional=0
client_service=""
for argument in "$@"; do
  case "${argument}" in
    -h | --help)
      usage
      exit 0
      ;;
    # Name of a Compose service that carries python3 and lives on the project network. The
    # client then runs inside that network instead of on the caller's host, which is what makes
    # the check work when Compose talks to a remote daemon (the CI stack): the container
    # addresses exist there, not here (change ci-integration, design D8).
    --client-service=*)
      client_service="${argument#--client-service=}"
      [[ -n "${client_service}" ]] \
        || { echo "verify-shutdown: --client-service needs a service name" >&2; usage >&2; exit 2; }
      ;;
    -*)
      echo "verify-shutdown: unexpected option '${argument}'" >&2
      usage >&2
      exit 2
      ;;
    *)
      if (( positional > 0 )); then
        echo "verify-shutdown: unexpected argument '${argument}'" >&2
        usage >&2
        exit 2
      fi
      service="${argument}"
      positional=1
      ;;
  esac
done

command -v docker >/dev/null 2>&1 || fail "docker not found in PATH"
if [[ -z "${client_service}" ]]; then
  # Only needed by the local client: in client-service mode both tools run in the container.
  for tool in curl python3; do
    command -v "${tool}" >/dev/null 2>&1 || fail "${tool} not found in PATH"
  done
fi

workdir="$(mktemp -d)"
stopped=0

restart_service() {
  compose up -d --wait "${service}" >"${workdir}/restart.out" 2>&1
}

# Leaves the environment as it was found even when a check fails halfway: a
# verification script must not leave a service down.
cleanup() {
  local status=$?
  trap - EXIT
  if (( stopped == 1 )); then
    if restart_service; then
      echo "verify-shutdown: ${service} restarted and healthy" >&2
    else
      echo "verify-shutdown: WARNING: could not restart ${service}" >&2
      cat "${workdir}/restart.out" >&2
    fi
  fi
  rm -rf -- "${workdir}"
  exit "${status}"
}
trap cleanup EXIT

# Resolved before touching anything: a missing file or an empty COMPOSE_FILE
# would otherwise surface as unrelated "no configuration file provided" errors.
compose config --quiet >/dev/null 2>&1 \
  || fail "cannot resolve the Compose configuration; check COMPOSE_FILE (.env or the environment) and that every file it lists exists"

container_id="$(compose ps -aq "${service}" | head -n1)"
[[ -n "${container_id}" ]] \
  || fail "service ${service} has no container; start the environment with docker compose up --wait"
state="$(docker inspect -f '{{.State.Status}}' "${container_id}")"
[[ "${state}" == "running" ]] \
  || fail "service ${service} is ${state}; start the environment with docker compose up --wait"
health="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "${container_id}")"
[[ "${health}" == "healthy" ]] \
  || fail "service ${service} is ${health}; start the environment with docker compose up --wait"

# Container address on its Compose network: any of them is routable from the
# host on Linux, and bypassing the published port keeps the userland proxy out
# of the measurement. With --client-service the address is resolved inside the
# network instead, so the IP is neither needed nor reachable.
ip=""
if [[ -z "${client_service}" ]]; then
  ip="$(docker inspect -f '{{range .NetworkSettings.Networks}}{{println .IPAddress}}{{end}}' \
    "${container_id}" | head -n1)"
  [[ -n "${ip}" ]] \
    || fail "cannot resolve the container IP of ${service}"
fi

# The address the client and the reference use: the container IP on the caller's
# host, the service name inside the project network.
target="${ip}"
if [[ -n "${client_service}" ]]; then
  target="${service}"
fi

# Both probes below run on the caller's host by default and inside the project
# network when --client-service names a service, so the same script measures the
# same thing whether Compose talks to the local daemon or to a remote one.
fetch_reference() {
  if [[ -n "${client_service}" ]]; then
    compose run --rm -T --no-deps --entrypoint python3 "${client_service}" - "${target}" "${slow_path}" <<'PYTHON'
import sys
import urllib.request

url = "http://%s:8080%s" % (sys.argv[1], sys.argv[2])
with urllib.request.urlopen(url) as response:
    body = response.read()
    print(response.status, len(body))
PYTHON
  else
    curl -fsS -o /dev/null -w '%{http_code} %{size_download}' "http://${target}:8080${slow_path}"
  fi
}

run_slow_client() {
  if [[ -n "${client_service}" ]]; then
    # `python3 -` reads the program from standard input, and this function runs as
    # a background job: an asynchronous list starts with /dev/null there, so
    # without this redirection Python would run an empty program, exit at once and
    # send nothing -- build #5 of PR #10 measured a stop with no request in flight
    # for exactly that reason. The workspace is on the controller and the daemon is
    # remote, so the file has to travel through stdin: a bind mount would be
    # resolved in dind, where this path does not exist.
    compose run --rm -T --no-deps --entrypoint python3 "${client_service}" - \
      "${target}" 8080 "${slow_path}" "${request_count}" "${hold_seconds}" \
      <"${workdir}/slow-client.py"
  else
    python3 "${workdir}/slow-client.py" "${target}" 8080 "${slow_path}" \
      "${request_count}" "${hold_seconds}"
  fi
}

# Reference response, fetched without tricks: every response read by the slow
# client has to carry exactly this body.
reference="$(fetch_reference)" \
  || fail "cannot fetch http://${target}:8080${slow_path}; is ${service} serving springdoc (APP_DOCS_ENABLED=true)?"
reference_status="${reference%% *}"
expected_bytes="${reference##* }"
[[ "${reference_status}" == "200" ]] \
  || fail "http://${target}:8080${slow_path} answered HTTP ${reference_status}; is ${service} serving springdoc (APP_DOCS_ENABLED=true)?"
[[ "${expected_bytes}" =~ ^[0-9]+$ ]] && (( expected_bytes > 0 )) \
  || fail "the reference response from http://${target}:8080${slow_path} is empty"


# Client: pipelined requests over one connection with the receive buffer shrunk
# before connecting, so the responses do not disappear into the kernel and the
# service has to keep writing while the client waits. It only reads after the
# hold, which is what makes the stop coincide with a response in flight. When
# the drain ends, Tomcat closes the connection and the pipelined requests it had
# not dispatched are not served; that is expected. What is never accepted is an
# incomplete body: a response that starts and does not arrive whole fails.
cat >"${workdir}/slow-client.py" <<'PYTHON'
"""Sends pipelined requests, holds the connection without reading and parses
every response, so a truncated body is detected instead of being reported as a
short answer."""
import socket
import sys
import time

host = sys.argv[1]
port = int(sys.argv[2])
path = sys.argv[3]
count = int(sys.argv[4])
hold_seconds = float(sys.argv[5])

sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 2048)
try:
    sock.connect((host, port))
    request = f"GET {path} HTTP/1.1\r\nHost: localhost\r\n\r\n".encode()
    sock.sendall(request * count)
    # Stamped right after the requests leave: the host waits for this line
    # instead of assuming that launching the client was enough, because with a
    # remote daemon the client is a container Compose has to create first.
    print(f"sent {int(time.time() * 1000)}", flush=True)
    time.sleep(hold_seconds)
    sock.settimeout(60)
    # The moment reading begins, stamped on the same kernel clock the host and
    # every container share, so the two are comparable without a skew guess.
    print(f"reading {int(time.time() * 1000)}", flush=True)
    stream = sock.makefile("rb")
    for index in range(count):
        status_line = stream.readline().strip()
        if not status_line:
            break
        headers = {}
        while True:
            line = stream.readline()
            if not line:
                raise SystemExit(
                    f"connection closed inside the headers of response {index + 1}"
                )
            if line in (b"\r\n", b"\n"):
                break
            name, _, value = line.partition(b":")
            headers[name.strip().lower()] = value.strip()
        length = int(headers.get(b"content-length", b"0"))
        body = stream.read(length)
        if len(body) != length:
            raise SystemExit(
                f"response {index + 1} truncated: {len(body)} of {length} bytes"
            )
        status_code = status_line.split()[1].decode()
        print(f"response={index + 1} status_code={status_code} body_bytes={len(body)}")
finally:
    sock.close()
PYTHON

run_slow_client \
  >"${workdir}/client.out" 2>"${workdir}/client.err" &
client_pid=$!

# The stop waits for the requests to be really in flight, not for the client to
# be launched: with a remote daemon the client is a container Compose creates
# first (measured: a few seconds in the CI stack), and a delay counted from the
# launch stopped the service before the first byte was sent -- build #5 of
# PR #10 failed exactly there. The client stamps the send, so it is observed.
sent_ms=""
for _ in $(seq 1 600); do
  sent_ms="$(awk '$1 == "sent" { print $2; exit }' "${workdir}/client.out" 2>/dev/null || true)"
  if [[ -n "${sent_ms}" ]]; then
    break
  fi
  kill -0 "${client_pid}" 2>/dev/null || break
  sleep 0.1
done
[[ -n "${sent_ms}" ]] \
  || fail "the slow client never reported that it sent the requests: $(cat "${workdir}/client.err")"

# The requests have to be in flight before SIGTERM and the buffers full: without
# the delay the stop could arrive after the service finished answering.
sleep "${stop_delay_seconds}"

stop_started_ms="$(now_ms)"
compose stop "${service}" >"${workdir}/stop.out" 2>&1 || {
  stopped=1
  fail "docker compose stop failed: $(cat "${workdir}/stop.out")"
}
stopped=1
stop_finished_ms="$(now_ms)"
stop_ms=$(( stop_finished_ms - stop_started_ms ))

exit_code="$(docker inspect -f '{{.State.ExitCode}}' "${container_id}")"

client_status=0
wait "${client_pid}" || client_status=$?

if (( client_status != 0 )); then
  fail "the slow request failed with exit ${client_status}: $(cat "${workdir}/client.err")"
fi

# Here "in flight" stops being an assumption: the client stamps the moment it
# starts reading, and a stop that had already finished by then had nothing left
# to drain.
reading_ms="$(awk '$1 == "reading" { print $2; exit }' "${workdir}/client.out" 2>/dev/null || true)"
[[ -n "${reading_ms}" ]] \
  || fail "the slow client never reported that it started reading: $(cat "${workdir}/client.err")"
(( stop_finished_ms >= reading_ms )) \
  || fail "docker compose stop finished in ${stop_ms} ms, before the client started reading: no request was in flight"

responses=0
while IFS= read -r line; do
  [[ "${line}" == response=* ]] || continue
  responses=$(( responses + 1 ))
  status="${line##*status_code=}"
  status="${status%% *}"
  bytes="${line##*body_bytes=}"
  [[ "${status}" == "200" ]] \
    || fail "response ${responses} answered HTTP ${status}, not 200"
  [[ "${bytes}" == "${expected_bytes}" ]] \
    || fail "response ${responses} was truncated: ${bytes} of ${expected_bytes} bytes"
done <"${workdir}/client.out"
(( responses >= 1 )) \
  || fail "no response was completed: the request was not in flight or the service closed the connection without serving it"

case "${exit_code}" in
  0) exit_label="clean exit" ;;
  143) exit_label="SIGTERM, 128 + 15" ;;
  137)
    fail "the container was killed by SIGKILL (137): the grace period expired before the in-flight requests finished"
    ;;
  *)
    fail "unexpected container exit code ${exit_code}; expected 0 or 143"
    ;;
esac

# The drain is also visible in the log: the JVM reports when it stops accepting
# requests and when the in-flight ones are done.
log_tail="$(compose logs --no-color --tail=15 "${service}" 2>&1)"
grep -q 'Commencing graceful shutdown' <<<"${log_tail}" \
  || fail "the log of ${service} does not report the start of the graceful shutdown"
grep -q 'Graceful shutdown complete' <<<"${log_tail}" \
  || fail "the log of ${service} does not report the end of the graceful shutdown"

# Restart explicitly so a failure here is reported as such, not hidden by the
# EXIT trap; afterwards the trap has nothing left to undo.
restart_service || fail "could not restart ${service} after the check: $(cat "${workdir}/restart.out")"
stopped=0

echo "verify-shutdown: OK ${responses} complete response(s) served while stopping (HTTP 200, ${expected_bytes} bytes each)"
echo "verify-shutdown: OK container exit code ${exit_code} (${exit_label}), no SIGKILL"
echo "verify-shutdown: OK graceful shutdown completed after ${stop_ms} ms with requests in flight"
echo "verify-shutdown: OK ${service} restarted and healthy"
echo "verify-shutdown: OK (ordered shutdown verified)"

