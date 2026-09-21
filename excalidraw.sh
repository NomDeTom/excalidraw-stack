#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODE_FILE="${SCRIPT_DIR}/.stack-mode"

# Storage mode: --mode flag, else STACK_MODE, else what the last start used, else full.
MODE="${STACK_MODE:-}"
if [[ "${1:-}" == "--mode" ]]; then
  MODE="${2:-}"; shift 2
elif [[ "${1:-}" == --mode=* ]]; then
  MODE="${1#--mode=}"; shift
fi
if [[ -z "$MODE" && -f "$MODE_FILE" ]]; then MODE="$(<"$MODE_FILE")"; fi
MODE="${MODE:-full}"
case "$MODE" in
  full|sqlite|hub) ;;
  *) echo "ERROR: unknown mode '$MODE' (full | sqlite | hub)"; exit 1 ;;
esac
COMPOSE="docker compose -f ${SCRIPT_DIR}/docker-compose.yml -f ${SCRIPT_DIR}/compose.${MODE}.yml"

usage() {
  cat <<EOF
Usage: $(basename "$0") [--mode full|sqlite|hub] <command>

Modes (remembered in .stack-mode after a start; STACK_MODE env also works):
  full       NestJS storage backend + Redis (default)
  sqlite     NestJS storage backend over a SQLite file, no Redis
  hub        no storage service; drawings go to the Irate-Box hub's store.py
             (set HUB_STORE_URL, default http://localhost:8000/api/v2)

Commands:
  start      Start all containers (detached)
  stop       Stop all containers
  restart    Restart all containers
  rebuild    Rebuild images from source and restart
  status     Show container status
  logs       Follow logs from all containers (Ctrl-C to exit)
  logs <svc> Follow logs from one service: excalidraw | room | storage | redis
  mode       Print the current mode
  update     Pull latest source for all repos, rebuild, and restart
  clean      Stop containers and remove volumes (DELETES ALL SAVED DATA)
EOF
}

require_docker() {
  if ! docker info &>/dev/null 2>&1; then
    echo "ERROR: Docker is not running or not accessible."
    echo "       Start Docker Desktop and ensure WSL integration is enabled."
    exit 1
  fi
}

remember_mode() { echo "$MODE" > "$MODE_FILE"; }

cmd_start() {
  require_docker
  remember_mode
  echo "Starting Excalidraw stack (mode: $MODE)..."
  $COMPOSE up -d
  echo ""
  echo "Excalidraw is available at http://localhost:3000"
}

cmd_stop() {
  require_docker
  echo "Stopping Excalidraw stack (mode: $MODE)..."
  $COMPOSE down --remove-orphans
}

cmd_restart() {
  require_docker
  echo "Restarting Excalidraw stack..."
  $COMPOSE restart
}

cmd_rebuild() {
  require_docker
  remember_mode
  echo "Rebuilding images from source (this takes several minutes)..."
  $COMPOSE up --build -d
  echo ""
  echo "Excalidraw is available at http://localhost:3000"
}

cmd_status() {
  require_docker
  $COMPOSE ps
}

cmd_logs() {
  require_docker
  local svc="${1:-}"
  if [[ -n "$svc" ]]; then
    $COMPOSE logs -f "$svc"
  else
    $COMPOSE logs -f
  fi
}

cmd_update() {
  require_docker
  echo "Pulling latest source..."
  git -C "${SCRIPT_DIR}" submodule update --remote --merge
  echo ""
  cmd_rebuild
}

cmd_clean() {
  require_docker
  echo "WARNING: This will delete all saved collaboration data."
  read -r -p "Are you sure? [y/N] " confirm
  if [[ "${confirm,,}" != "y" ]]; then
    echo "Aborted."
    exit 0
  fi
  $COMPOSE down -v
  echo "Stack and volumes removed."
}

case "${1:-}" in
  start)   cmd_start ;;
  stop)    cmd_stop ;;
  restart) cmd_restart ;;
  rebuild) cmd_rebuild ;;
  status)  cmd_status ;;
  mode)    echo "$MODE" ;;
  logs)    cmd_logs "${2:-}" ;;
  update)  cmd_update ;;
  clean)   cmd_clean ;;
  *)       usage; exit 1 ;;
esac
