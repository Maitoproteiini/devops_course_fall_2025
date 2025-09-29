#!/usr/bin/env bash

# This script cleans the persistent storages as part of the exercise requirements.

set -euo pipefail

# Pick Compose v2 or legacy
if docker compose version >/dev/null 2>&1; then
  DOCKER_COMPOSE="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
  DOCKER_COMPOSE="docker-compose"
else
  echo "Docker Compose not found" >&2
  exit 1
fi

# Ensure we're in the right directory
if [[ ! -f "docker-compose.yaml" ]]; then
  echo "Please run from the repo root (docker-compose.yaml not found)." >&2
  exit 2
fi

echo "Stopping containers and removing named volumes..."
$DOCKER_COMPOSE down -v --remove-orphans

echo "Clearing vStorage..."
rm -rf ./vstorage
mkdir -p ./vstorage
: > ./vstorage/log.txt

echo "Persistent storage wiped."
echo "Start fresh with:  $DOCKER_COMPOSE up -d --build"
