#!/usr/bin/env bash
set -euo pipefail

# Config
STATUS_CALLS="${STATUS_CALLS:-3}"           # how many /status requests to send
S1_URL="${S1_URL:-http://localhost:8199}"   # public endpoint (only service1)
S2_HOST_PORT="${S2_HOST_PORT:-8081}"        # should NOT be reachable from host
ST_HOST_PORT="${ST_HOST_PORT:-8080}"        # should NOT be reachable from host
VSTORAGE_PATH="${VSTORAGE_PATH:-./vstorage/log.txt}"
LOG_TMP_STORAGE="$(mktemp)"
LOG_TMP_VSTORAGE="$(mktemp)"
HEADERS_TMP="$(mktemp)"

# Helper: choose docker compose v2 or old docker-compose
if command -v docker >/dev/null && docker compose version >/dev/null 2>&1; then
  DC="docker compose"
elif command -v docker-compose >/dev/null; then
  DC="docker-compose"
else
  echo "FATAL: Docker Compose not found." >&2
  exit 1
fi

cleanup() {
  rm -f "$LOG_TMP_STORAGE" "$LOG_TMP_VSTORAGE" "$HEADERS_TMP"
}
trap cleanup EXIT

say()  { printf "\n\033[1;34m▶ %s\033[0m\n" "$*"; }
ok()   { printf "\033[1;32m✔ %s\033[0m\n" "$*"; }
fail() { printf "\033[1;31m✘ %s\033[0m\n" "$*" >&2; exit 1; }

require() {
  command -v "$1" >/dev/null || fail "Required command '$1' not found"
}
require curl
require docker

# 0) Fresh start: remove old containers/volumes (clean state)
say "Bringing stack down & cleaning volumes (fresh state)"
$DC down -v --remove-orphans >/dev/null 2>&1 || true

# ensure vstorage dir exists and is empty
mkdir -p "$(dirname "$VSTORAGE_PATH")"
: > "$VSTORAGE_PATH"

# 1) Build & start
say "Building images and starting containers"
$DC up -d --build

# 2) Wait for service1 to be reachable
say "Waiting for Service1 at $S1_URL/"
ATTEMPTS=60
until curl -fsS "$S1_URL/" >/dev/null 2>&1; do
  ((ATTEMPTS--)) || fail "Service1 never became ready"
  sleep 1
done
ok "Service1 is up"

# 3) Verify Service2 and Storage are NOT exposed to host
say "Verifying Service2/Storage are NOT exposed to the host"
if curl -fsS "http://localhost:$S2_HOST_PORT/" >/dev/null 2>&1; then
  fail "Service2 appears reachable from host (:$S2_HOST_PORT) — must not publish this port"
fi
ok "Service2 not exposed on host"

if curl -fsS "http://localhost:$ST_HOST_PORT/" >/dev/null 2>&1; then
  fail "Storage appears reachable from host (:$ST_HOST_PORT) — must not publish this port"
fi
ok "Storage not exposed on host"

# secondary check via docker ps: service2/storage must have NO host port mapping ("->")
say "Double-checking published ports via 'docker ps'"
PS_OUT="$(docker ps --format 'table {{.Names}}\t{{.Ports}}')"
echo "$PS_OUT"
echo "$PS_OUT" | awk '/\t.*->/ {print}' | grep -E '(^|[^a-z])service2([^a-z]|$)|(^|[^a-z])storage([^a-z]|$)' >/dev/null 2>&1 \
  && fail "service2 or storage shows a published host port in 'docker ps'"
ok "Only service1 has a published port"

# 4) Hit /status N times (each should trigger 2 log lines)
say "Triggering /status $STATUS_CALLS times"
for i in $(seq 1 "$STATUS_CALLS"); do
  RESP="$(curl -fsS "$S1_URL/status")" || fail "/status call failed"
  echo "--- /status #$i ---"
  echo "$RESP"
  # Expect 2 lines (record1 + record2)
  LINES="$(printf "%s\n" "$RESP" | wc -l | tr -dc 0-9)"
  [[ "$LINES" -eq 2 ]] || fail "Expected 2 lines from /status, got $LINES"
done
ok "/status produced 2 lines per call"

# 5) GET /log and capture headers + body
say "Fetching /log via Service1 (should proxy Storage)"
curl -fsS -D "$HEADERS_TMP" -o "$LOG_TMP_STORAGE" "$S1_URL/log"
grep -qi '^Content-Type: *text/plain' "$HEADERS_TMP" \
  || fail "Content-Type from /log is not text/plain"
ok "GET /log returns text/plain"

# 6) Compare with vStorage (bind mount) — they must be equal and 2*N lines total
say "Comparing Storage(/log) with vStorage file"
cat "$VSTORAGE_PATH" > "$LOG_TMP_VSTORAGE" || true

DIFF="$(diff -u "$LOG_TMP_VSTORAGE" "$LOG_TMP_STORAGE" || true)"
if [[ -n "$DIFF" ]]; then
  echo "$DIFF"
  fail "Mismatch: ./vstorage/log.txt != GET /log output"
fi
ok "Contents match between vStorage and Storage"

TOTAL_LINES="$(wc -l < "$LOG_TMP_STORAGE" | tr -dc 0-9)"
EXPECTED=$(( STATUS_CALLS * 2 ))
[[ "$TOTAL_LINES" -eq "$EXPECTED" ]] \
  || fail "Expected $EXPECTED lines in logs after $STATUS_CALLS /status calls, got $TOTAL_LINES"
ok "Log contains exactly $EXPECTED lines (2 per /status)"

# 7) Quick format sanity: lines start with Timestamp1:/Timestamp2:
say "Checking line prefixes and fields"
grep -q '^Timestamp1:' "$LOG_TMP_STORAGE" || fail "No Timestamp1 lines found"
grep -q '^Timestamp2:' "$LOG_TMP_STORAGE" || fail "No Timestamp2 lines found"
ok "Both Timestamp1 and Timestamp2 present"

# 8) Persistence check across a restart (containers only; volumes persist)
say "Restarting containers to verify persistence"
$DC restart >/dev/null

# wait for service1 back up
ATTEMPTS=60
until curl -fsS "$S1_URL/" >/dev/null 2>&1; do
  ((ATTEMPTS--)) || fail "Service1 didn't come up after restart"
  sleep 1
done

# capture /log after restart to a file (not a variable)
AFTER_FILE="$(mktemp)"
curl -fsS -o "$AFTER_FILE" "$S1_URL/log"

# compare files (exact byte match)
if ! cmp -s "$AFTER_FILE" "$LOG_TMP_STORAGE"; then
  echo "---- BEFORE ----"; nl -ba "$LOG_TMP_STORAGE"
  echo "---- AFTER  ----"; nl -ba "$AFTER_FILE"
  fail "Log changed across restart — persistence failed"
fi
ok "Logs persisted across restart"


# 9) Save required status info (for submission)
say "Writing docker-status.txt (container & network lists)"
{
  echo "# docker container ls"
  docker container ls
  echo
  echo "# docker network ls"
  docker network ls
} > docker-status.txt
ok "docker-status.txt written"

say "All checks passed ✅"
