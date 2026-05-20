#!/usr/bin/env python3
"""
Orbis Agent — Run Script

Usage:
    python run.py "Optimize H2O and compute HOMO/LUMO gap"
    python run.py --goal "Analyze TS for Diels-Alder reaction" --context "reactant.xyz and product.xyz are in ./inputs/"

For cron job usage:
    python /home/quantum/xhy/orbis/agent/run.py "Daily DFT check on catalyst stability"
"""

import sys
import os
from pathlib import Path

# Ensure orbis is importable
ORBIS_HOME = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ORBIS_HOME))

from agent.orbis_agent import OrbisAgent

if __name__ == "__main__":
    goal = None
    extra_context = ""

    # Parse simple CLI: run.py [--context "text"] "goal text"
    args = sys.argv[1:]
    i = 0
    while i < len(args):
        if args[i] in ("--context", "-c") and i + 1 < len(args):
            extra_context = args[i + 1]
            i += 2
        elif args[i] in ("--goal", "-g") and i + 1 < len(args):
            goal = args[i + 1]
            i += 2
        elif args[i] in ("--help", "-h"):
            print(__doc__)
            sys.exit(0)
        else:
            goal = args[i]
            i += 1

    if not goal:
        print("❌ No goal provided. Usage: python run.py 'Your scientific goal here'")
        sys.exit(1)

    agent = OrbisAgent()
    result = agent.run(goal, extra_context=extra_context)

    print("\n" + "=" * 70)
    print("🔬 ORBIS RESULT")
    print("=" * 70)
    print(result["final_response"])
