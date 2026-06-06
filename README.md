# ORBIS — Autonomous Quantum Chemistry AI Scientist

ORBIS is a fully autonomous quantum chemistry AI agent powered by the iQCAP analysis platform. It receives a natural-language research goal, plans the complete computational workflow, executes all calculations (ORCA, Multiwfn, VMD), interprets results, and delivers a **compiled PDF research paper** as the final output.

## Features

- **13 autonomous tools**: `run_orca`, `run_iqcap` (9 modules), `parse_orca_output`, `compute_binding_energy`, `generate_research_paper`, `compile_paper_pdf`, and more
- **4 system-type workflows**: single molecule, dimer/complex, reaction path, adsorption
- **15+ analysis modules**: ESP, HOMO/LUMO, Fukui, Hirshfeld, Mayer bond orders, CDFT, NCI, IGMH, IRI, Hirshfeld surface, chgdiff, CDA, ELF, 2D cross-sections
- **Full paper pipeline**: .tex + .docx + .pdf with auto-generated figures and data tables

## Quick Start

```bash
# Run with a natural language goal
python3 agent/run.py "Study the quantum chemical properties of the H2O dimer at B3LYP-D3(BJ)/def2-TZVP(-f) level"

# Or use the shell script
bash run_orbis.sh "Study the quantum chemical properties of the H2O dimer"
```

## Requirements

- Python 3.10+
- ORCA 6.1.0
- Multiwfn 3.8+
- VMD 1.9.4+
- Python packages: `openai`, `matplotlib`, `numpy`, `scipy`, `python-docx`, `fpdf2`

## Configuration

Set your API key in `agent/orbis_config.py` or via environment variable:
```bash
export ORBIS_API_KEY="sk-..."
```

## Architecture

```
Goal → Plan → Execute tool → Parse result → Decide → (retry|next|done)
                              ↑  failure?  →  diagnose, adjust, retry
```

- **Agent**: `agent/orbis_agent.py` — Self-looping AI agent with 4 workflow types
- **Tools**: `agent/orbis_tools.py` — 13 tools for ORCA/iQCAP/analysis
- **Paper Generator**: `paper/generator.py` — LaTeX + Word + PDF generation
- **Figures**: `paper/figures.py` — Auto-generated structure/IR/energy figures
- **iQCAP Scripts**: `orca/orca-*.sh` — Automated Multiwfn+VMD analysis pipelines

## Author

Hengyue Xu (ORCiD: 0000-0003-4438-9647)
