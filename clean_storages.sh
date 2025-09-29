#!/usr/bin/env bash
set -euo pipefail

# --- options ---------------------------------------------------------------
MODE="soft"      # soft | hard
BRING_DOWN=false # stop stack first (useful for hard)
YES=false        # skip confirmation in hard mode

for a in "$@"; do
  case "$a" in
    --soft|-s) MODE="soft" ;;
    --hard|-h) MODE="hard" ;;
    --down)    BRING_DOWN=true ;;
    --no-down) BRING_DOWN=false ;;
    --yes|-y)  YES=true ;;
    -*) echo "Usage: $0 [--soft|--hard] [--down|--no-down] [--yes]"; exit 2 ;;
  esac
done

# --- helpers ---------------------------------------------------------------
say()  { printf "\n\033[1;34m▶ %s\033[0m\n" "$*"; }
ok()   { printf "\033[1;32m✔ %s\033[0m\n" "$*"; }
warn() { printf "\033[1;33m! %s\033[0m\n" "$*"; }
fail() { printf "\033[1;31m✘ %s\033[0m\n" "$*"; exit 1; }

# Pick compose command (v2 or legacy)
if docker compose version >/dev/null 2>&1; then
  DC="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
  DC="docker-compose"
else
  fail "Docker Compose not found"
fi

PROJECT="${COMPOSE_PROJECT_NAME:-$(basename "$PWD")}"
VOLUME="${PROJECT}_storage_data"          # named volume from compose
VSTORAGE_DIR="${VSTORAGE_DIR:-./vstorage}"
VSTORAGE_FILE="$VSTORAGE_DIR/log.txt"

# --- optional: bring stack down first (recommended for --hard) ------------
if $BRING_DOWN; then
  say "Stopping stack (compose down)"
  $DC down || true
fi

# --- SOFT CLEANUP ----------------------------------------------------------
if [[ "$MODE" == "soft" ]]; then
  say "Soft cleanup: truncate logs in both storages (keep volumes)"

  # vStorage (bind mount on host)
  mkdir -p "$VSTORAGE_DIR"
  : > "$VSTORAGE_FILE" || warn "Could not truncate $VSTORAGE_FILE"
  ok "vStorage truncated: $VSTORAGE_FILE"

  # Storage (named volume). Prefer exec if container 'storage' is running.
  if docker ps --format '{{.Names}}' | grep -qx 'storage'; then
    docker exec storage sh -lc ':> /data/log.txt 2>/dev/null || true'
    ok "Storage log truncated via running container"
  else
    # Use a throwaway helper container with the volume mounted
    docker run --rm -v "$VOLUME:/data" busybox sh -lc ':> /data/log.txt 2>/dev/null || true'
    ok "Storage log truncated via volume access (busybox)"
  fi

  exit 0
fi

# --- HARD CLEANUP ----------------------------------------------------------
if [[ "$MODE" == "hard" ]]; then
  say "HARD cleanup: remove Storage named volume and clear vStorage bind mount"
  if ! $YES; then
    read -r -p "This will DELETE Docker volume '$VOLUME' and clear '$VSTORAGE_DIR'. Continue? [y/N] " ans
    [[ "${ans,,}" == "y" || "${ans,,}" == "yes" ]] || fail "Aborted"
  fi

  # Clear vStorage files (keep folder)
  if [[ -d "$VSTORAGE_DIR" ]]; then
    rm -f "$VSTORAGE_DIR"/* 2>/dev/null || true
    : > "$VSTORAGE_FILE" 2>/dev/null || true
    ok "Cleared vStorage at $VSTORAGE_DIR"
  else
    warn "vStorage dir not found ($VSTORAGE_DIR) — skipping"
  fi

  # Remove named volume (force to avoid dangling refs)
  if docker volume inspect "$VOLUME" >/dev/null 2>&1; then
    docker volume rm -f "$VOLUME" >/dev/null
    ok "Removed Docker volume: $VOLUME"
  else
    warn "Volume '$VOLUME' not found — skipping"
  fi

  say "HARD cleanup complete"
  exit 0
fi

fail "Unknown mode '$MODE'"
