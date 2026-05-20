#!/usr/bin/env bash
###############################################################################
# Orbis Web Launcher
#
# Starts the Orbis web interface for quantum chemistry paper generation.
#
# Usage:
#   bash start_web.sh              # Start on port 5000
#   bash start_web.sh --port 8080  # Custom port
#   bash start_web.sh --production # Production mode (gunicorn if available)
###############################################################################

set -euo pipefail

ORBIS_HOME="$(cd "$(dirname "$0")" && pwd)"
VENV_PYTHON="/home/quantum/tools/hermes-agent/venv/bin/python3"
PORT=5000
HOST="0.0.0.0"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --port|-p) PORT="$2"; shift 2 ;;
        --host|-h)  HOST="$2"; shift 2 ;;
        --production) PRODUCTION=true; shift ;;
        *) echo "Unknown: $1"; exit 1 ;;
    esac
done

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  🔬  Orbis — Quantum Chemistry AI Scientist                 ║"
echo "║  🌐  Web Interface                                          ║"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║  Address:  http://${HOST}:${PORT}                              ║"
echo "║  ORCA:     /home/quantum/tools/orca_6_1_0_avx2/orca        ║"
echo "║  Workspace: ${ORBIS_HOME}/workspace/                         ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# Ensure workspace exists
mkdir -p "${ORBIS_HOME}/workspace"

cd "${ORBIS_HOME}"

exec "${VENV_PYTHON}" web/app.py --host "${HOST}" --port "${PORT}"
