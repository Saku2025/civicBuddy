#!/bin/sh
# Run the backup on this Mac using .env (never committed) and the local
# rclone "unidrive" remote.  Examples:
#   ./run_local.sh check
#   DRY_RUN=1 ./run_local.sh weekly
cd "$(dirname "$0")"
set -a
. ./.env
set +a
PY="${PY:-.venv/bin/python}"
exec "$PY" backup.py "$@"
