#!/usr/bin/env bash
###############################################################################
# Orbis Agent — Launch Script
#
# Usage:
#   bash run_orbis.sh "Optimize H2O and compute HOMO/LUMO gap"
#   bash run_orbis.sh --goal "Analyze TS" --context "reactant.xyz in ./"
#   bash run_orbis.sh --daemon --goal "Monitor catalyst stability every 6h"
#
# For cron: add to crontab or use Hermes cronjob
###############################################################################

set -euo pipefail

ORBIS_HOME="$(cd "$(dirname "$0")" && pwd)"
cd "$ORBIS_HOME"

# Ensure workspace exists
mkdir -p workspace

# ── Parse args ────────────────────────────────────────────────────
GOAL=""
CONTEXT=""
DAEMON_MODE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --goal|-g)   GOAL="$2"; shift 2 ;;
        --context|-c) CONTEXT="$2"; shift 2 ;;
        --daemon|-d)  DAEMON_MODE=true; shift ;;
        --help|-h)
            echo "Orbis Agent — Quantum Chemistry AI Scientist"
            echo ""
            echo "Usage: bash run_orbis.sh [--goal '...'] [--context '...'] [--daemon]"
            echo ""
            echo "  --goal, -g     Scientific goal"
            echo "  --context, -c  Additional context (file paths, notes)"
            echo "  --daemon, -d   Run continuously (re-evaluate every cycle)"
            echo ""
            echo "Examples:"
            echo "  bash run_orbis.sh 'Optimize H2O with B3LYP/def2-TZVP'"
            echo "  bash run_orbis.sh --daemon --goal 'Monitor catalysis cycle'"
            exit 0
            ;;
        *) GOAL="$1"; shift ;;
    esac
done

if [[ -z "$GOAL" ]]; then
    echo "🔬 Orbis Agent — Quantum Chemistry AI Scientist"
    echo "=============================================="
    echo -n "Enter your scientific goal: "
    read -r GOAL
fi

# ── Run ────────────────────────────────────────────────────────────
if $DAEMON_MODE; then
    echo "🔄 Daemon mode: agent will run continuously..."
    while true; do
        echo ""
        echo "─── $(date) ───"
        python3 agent/run.py --goal "$GOAL" ${CONTEXT:+--context "$CONTEXT"}
        echo "Sleeping 5 minutes before next cycle..."
        sleep 300
    done
else
    python3 agent/run.py --goal "$GOAL" ${CONTEXT:+--context "$CONTEXT"}
fi
