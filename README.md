# ORBIS — Autonomous Quantum Chemistry AI Scientist

ORBIS is a fully autonomous quantum chemistry AI agent powered by the iQCAP analysis platform. It receives a natural-language research goal, plans the complete computational workflow, executes all calculations (ORCA, Multiwfn, VMD), interprets results, and delivers a **compiled PDF research paper** as the final output.

## Features

- **13 autonomous tools**: `run_orca`, `run_iqcap` (10 modules), `parse_orca_output`, `compute_binding_energy`, `generate_research_paper`, `compile_paper_pdf`, and more
- **4 system-type workflows**: single molecule, dimer/complex, reaction path, adsorption
- **17+ analysis modules**: ESP, HOMO/LUMO, Fukui, Hirshfeld, Mayer bond orders, CDFT, NCI, mIGM, amIGM, IGMH, IRI, Hirshfeld surface, chgdiff, CDA, ELF, 2D cross-sections
- **Full paper pipeline**: .tex + .docx + .pdf with auto-generated figures and data tables
- **Large-system support**: dedicated `basic_elect_analysis_large` module for >100-atom systems (orca_plot-based)
- **Zero-dependency weak interaction**: mIGM and amIGM need only XYZ coordinates, no QM wavefunction

## Quick Start

```bash
# Environment detection & setup
bash install.sh

# Run with a natural language goal
python3 agent/run.py "Study the quantum chemical properties of the H2O dimer at B3LYP-D3(BJ)/def2-TZVP(-f) level"
```

## Requirements

- Python 3.10+
- ORCA 6.1.0
- Multiwfn ≥ 2025-Nov-23 (for mIGM/amIGM)
- VMD 1.9.4+
- Python packages: see `requirements.txt`

Install Python deps:
```bash
pip install -r requirements.txt
```

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

## iQCAP Analysis Modules

| Module | Script | Description |
|--------|--------|-------------|
| Optimization | `orca-opt.sh` | Geometry optimization (4 modes, 5 method presets) |
| Electronic Structure | `orca-basic_elect_analysis.sh` | ESP, HOMO/LUMO, Fukui, Hirshfeld, Mayer, CDFT |
| Electronic Structure (large) | `orca-basic_elect_analysis-large_system.sh` | orca_plot-based for >100-atom systems |
| Weak Interaction | `orca-elect_interaction.sh` | NCI, mIGM, IGMH, IRI, Hirshfeld surface, chgdiff, CDA |
| **amIGM** (NEW) | `orca-amigm.sh` | Time-averaged mIGM from MD trajectories |
| Transition State | `orca-ts.sh` | TS optimization + IRC |
| Gibbs Free Energy | `orca-G.sh` | Thermochemistry |

## amIGM — Averaged mIGM (NEW)

Standalone, zero-dependency weak interaction analysis for MD trajectories. Only input is a multi-frame XYZ file — no ORCA, no molden, no wavefunction.

```bash
bash orca/orca-amigm.sh --traj md_aligned.xyz --frag1 "1-13"
```

Reference: [http://sobereva.com/759](http://sobereva.com/759)

## Author

Hengyue Xu (ORCiD: 0000-0003-4438-9647)
