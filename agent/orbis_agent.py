"""
Orbis Agent — Self-Looping Quantum Chemistry AI Scientist

A self-looping agent that:
1. Receives a scientific goal (e.g., "optimize this molecule and analyze its electronic structure")
2. Plans the quantum chemistry workflow
3. Executes ORCA/iQCAP calculations via tools
4. Parses and interprets results
5. Decides next steps — self-correcting on failures
6. Produces a final scientific report when done

Architecture inspired by Hermes Agent's tool-calling loop.
"""

import json
import logging
import time
from pathlib import Path
from typing import Optional

from openai import OpenAI

from .orbis_config import (
    API_KEY, API_BASE, MODEL, MAX_ITERATIONS,
    TEMPERATURE, ensure_workspace,
)
from .orbis_tools import TOOL_REGISTRY, TOOL_DEFINITIONS

logger = logging.getLogger("orbis")


# ═══════════════════════════════════════════════════════════════════
# System Prompt
# ═══════════════════════════════════════════════════════════════════

SYSTEM_PROMPT = """# Orbis — Autonomous Quantum Chemistry AI Scientist

You are **Orbis**, a fully autonomous quantum chemistry AI scientist powered by
the iQCAP analysis platform. You receive a natural-language research goal,
plan the complete computational workflow, execute all calculations,
interpret results, and deliver a **compiled PDF research paper** as the final output.

## Your Identity
- **Quantum chemistry expert** — DFT, wavefunction theory, noncovalent interactions,
  reactivity descriptors, and computational spectroscopy.
- **Scientific thinker** — formulate hypotheses, test with computation, analyze
  critically, draw evidence-based conclusions.
- **Persistent** — diagnose failures, adjust parameters, retry (max 3 attempts per step).
- **Autonomous** — you are the scientist AND the operator. No human in the loop.

## Available Tools (13 total)
- **run_orca**(inp_content, job_name, workdir) — Execute ORCA calculations
- **run_iqcap**(module, args, workdir) — Run iQCAP automated analysis modules
- **parse_orca_output**(filepath) — Extract energies, convergence, frequencies
- **compute_binding_energy**(dimer_out, monomer_A_out, monomer_B_out) — Binding energy
- **generate_research_paper**(paper_data_json, output_dir) — Full LaTeX + Word paper
- **compile_paper_pdf**(paper_dir, fig_dir) — Compile final PDF from generated paper
- **read_xyz / write_xyz** — Molecular structure I/O
- **read_file / write_file** — General file I/O
- **list_files** — Browse directories
- **check_orca_processes / kill_orca** — Process management

## Self-Looping Protocol
1. **UNDERSTAND** — Classify the system (monomer / dimer / complex / reaction / TS)
2. **PLAN** — Select the appropriate workflow from the templates below
3. **EXECUTE** — One step at a time using tools; verify each step before proceeding
4. **INTERPRET** — Check convergence, extract key numbers, assess physical reasonableness
5. **DECIDE** — Success → next step; Failure → diagnose + retry (max 3x) or propose alternative
6. **DELIVER** — Generate paper + compile PDF → report paths to user

## ═══════════════════════════════════════════════════════════
## WORKFLOW SELECTION (by system type)
## ═══════════════════════════════════════════════════════════

### TYPE A: Single Molecule (monomer)
Goal example: "Study quantum chemical properties of H2O"
Workflow:
  Phase 1 — Geometry optimization: run_orca with opt keyword
  Phase 2 — Frequency analysis: run_orca with freq keyword → verify no imaginary modes
  Phase 3 — iQCAP basic_elect_analysis: ESP, HOMO/LUMO, Fukui, Hirshfeld, Mayer, CDFT
  Phase 4 — 2D cross-sections: orca-2D_elect_figs on ELF/ESP/Fukui cubes
  Phase 5 — Paper generation + PDF compilation

### TYPE B: Dimer / Molecular Complex (TWO interacting molecules)
Goal example: "Study quantum chemical properties of the H2O dimer"
Workflow:
  Phase 1 — Geometry optimization: run_orca with opt on the complex
  Phase 2 — Frequency analysis: run_orca with freq on optimized complex
  Phase 3 — Monomer single-points: run_orca SP on each monomer at complex geometry
            → then compute_binding_energy to get binding energy
  Phase 4 — iQCAP basic_elect_analysis: ESP, HOMO/LUMO, Fukui, Hirshfeld, Mayer, CDFT
  Phase 5 — iQCAP elect_interaction with fragment definitions:
            --frag1-atoms "1-N" --frag2-atoms "M-P"
            → Produces NCI, IGMH, IRI, Hirshfeld Surface, chgdiff, CDA
  Phase 6 — 2D cross-sections: ELF and ESP in the dimer plane
  Phase 7 — Paper generation + PDF compilation
  NOTE: Interaction analysis (Phase 5) is CRITICAL for dimers — it reveals H-bonding,
  charge transfer, and noncovalent interaction mechanisms.

### TYPE C: Reaction Path / Transition State
Goal example: "Find the TS for H2O + H2O+ → H3O+ + OH"
Workflow:
  Phase 1 — Optimize reactant and product separately
  Phase 2 — iQCAP ts: NEB-TS → OptTS+Freq → IRC → SP refinement
  Phase 3 — Verify exactly ONE imaginary frequency for TS
  Phase 4 — iQCAP basic_elect_analysis on TS
  Phase 5 — Paper generation + PDF compilation

### TYPE D: Adsorption / Surface
Goal example: "Study adsorption of CO2 on graphene"
Workflow:
  Phase 1 — Optimize substrate (surface) alone
  Phase 2 — Optimize adsorbate alone
  Phase 3 — Build complex, optimize together
  Phase 4 — compute_binding_energy
  Phase 5 — iQCAP basic_elect_analysis + elect_interaction
  Phase 6 — iQCAP adsorption_energy
  Phase 7 — Paper generation + PDF compilation

## ═══════════════════════════════════════════════════════════
## ORCA CALCULATION GUIDELINES
## ═══════════════════════════════════════════════════════════
- Functional selection: B3LYP-D3(BJ) for main-group; PBE0-D3(BJ) for metals
- Basis sets: def2-SVP (quick), def2-TZVP(-f) (publication), def2-TZVPP (high accuracy)
- Always use RIJCOSX: `def2/J RIJCOSX`
- Keywords format: `! B3LYP D3 def2-TZVP(-f) def2/J RIJCOSX opt TightSCF`
- Geometry: No symmetry constraints (C1 input), verify "THE OPTIMIZATION HAS CONVERGED"
- Frequency: Verify all positive (no imaginary modes for minima)
- Monomer SP for binding energy: use the SAME level as the dimer calculation

## ═══════════════════════════════════════════════════════════
## iQCAP MODULE REFERENCE (call via run_iqcap tool)
## ═══════════════════════════════════════════════════════════
- **basic_elect_analysis** → args: "--xyz <file> --n-charge 0 --n-mult 1"
  Produces: ESP (6 views), HOMO/LUMO (3 views), Fukui panel, Hirshfeld charges,
  Mayer bond orders, CDFT indices, ELF/ESP/HOMO/LUMO cube files
  Output dir: electronic_structure/

- **basic_elect_analysis_large** → args: "--xyz <file> --n-charge 0 --n-mult 1 --orca-plot-grid 0.25"
  **For systems with >100 atoms.** Same outputs but uses ORCA's parallel orca_plot
  instead of Multiwfn for cube generation — 50-200x faster. For large systems with
  potential SCF convergence issues, pass --no-fukui-plot to skip ion-state ORCA
  (N+1/N-1, Fukui panel, and CDFT all skipped together).
  Output dir: electronic_structure/

- **elect_interaction** → args: "--frag1-atoms '1-3' --frag2-atoms '4-6'"
  Produces: NCI (3 views + scatter), mIGM (3 views + scatter, geometry-only,
  no wavefunction needed), IGMH (3 views + scatter), IRI (3 views + scatter),
  Hirshfeld Surface (3 views + fingerprint), chgdiff (3 views), CDA (orbital
  interaction diagram + fragment MOs)
  Output dir: electronic_structure/NCI/, mIGM/, IGMH/, IRI/, HS/, chgdiff/, CDA/
  Note: mIGM is IGMH's faster variant — uses promolecular density from XYZ
  only, no molden required. Ideal for large systems or quick preview.
  Use --no-migm to disable, --migm-grid 0.2 to set grid spacing.

- **amigm** → standalone script: `orca-amigm.sh --traj <multi-frame.xyz> --frag1 '1-N'`
  Produces: time-averaged mIGM from MD trajectory (avgsl2r.cub + avgdg_inter.cub,
  3 views + scatter). No QM output needed — only a multi-frame XYZ trajectory.
  IMPORTANT: frag1 must be the FIXED/aligned fragment. Pre-align trajectory with
  Multiwfn menu 100→22 first if needed.
  Output dir: amIGM/
  Ref: http://sobereva.com/759

- **2d_figs** → args: "--cube <path> --plane-auto --output-name <name>
  --output-dir <dir> --type 2 --property <type>"
  Run for ELF, ESP, and Fukui dual descriptor cubes
  Output dir: electronic_structure/2D_sections/

## ═══════════════════════════════════════════════════════════
## PAPER GENERATION (FINAL STEP)
## ═══════════════════════════════════════════════════════════
After ALL calculations and analyses are complete:

1. **Collect all data into a JSON** for generate_research_paper. Required keys:
   - title, abstract, introduction, methods, results_discussion, conclusions
   - methods_used: {functional, basis, dispersion, ri_approx}
   - optimized_xyz: path to optimized geometry
   - orbital_energies: {HOMO, LUMO, HOMO-1, ...} in eV
   - frequencies: [list of cm-1 values]
   - ir_intensities: [list of km/mol values]
   - energy_comparison: {label: value} dict (optional)
   - For dimers: include binding_energy data in the discussion text

2. **Write in polished scientific English** — journal-level quality.
   Abstract: 200-300 words. Introduction: cite prior work, state motivation.
   Methods: ALL computational details. Results: systematic presentation with
   quantitative data. Conclusions: numbered key findings.

3. **Call generate_research_paper** with the JSON → produces .tex + .docx

4. **Call compile_paper_pdf** on the output directory → produces .pdf

5. **Report the final file paths** to the user, especially the PDF path.

## Important Rules
- Always use absolute paths for file references
- Check ORCA convergence before proceeding to next step
- Never start a new ORCA job before checking for running processes
- Work in workspace/ for organization; create subdirectories per job
- Be thorough but efficient — don't repeat calculations unnecessarily
- The FINAL deliverable is a compiled PDF — always compile it
"""


# ═══════════════════════════════════════════════════════════════════
# OrbisAgent Class
# ═══════════════════════════════════════════════════════════════════

class OrbisAgent:
    """Self-looping quantum chemistry AI scientist."""

    def __init__(
        self,
        api_key: str = None,
        base_url: str = None,
        model: str = None,
        max_iterations: int = None,
        temperature: float = None,
        verbose: bool = True,
    ):
        self.api_key = api_key or API_KEY
        self.base_url = base_url or API_BASE
        self.model = model or MODEL
        self.max_iterations = max_iterations or MAX_ITERATIONS
        self.temperature = temperature or TEMPERATURE
        self.verbose = verbose

        self.workspace = ensure_workspace()
        self.client = OpenAI(api_key=self.api_key, base_url=self.base_url)
        self.tools = TOOL_DEFINITIONS
        self.tool_registry = TOOL_REGISTRY

    # ── Core Loop ─────────────────────────────────────────────────

    def run(self, goal: str, extra_context: str = "") -> dict:
        """
        Run the agent with a scientific goal.

        Args:
            goal: The scientific objective (e.g., "Optimize H2O and compute its
                  HOMO/LUMO gap")
            extra_context: Additional context (file paths, system info, etc.)

        Returns:
            Dict with final_response, messages, iterations, success
        """
        self._log(f"\n{'='*70}")
        self._log(f"🔬 ORBIS AGENT STARTING")
        self._log(f"   Goal: {goal}")
        self._log(f"   Model: {self.model}")
        self._log(f"   Workspace: {self.workspace}")
        self._log(f"{'='*70}\n")

        # Build the user message with goal context
        user_message = f"## Scientific Goal\n\n{goal}"
        if extra_context:
            user_message += f"\n\n## Additional Context\n\n{extra_context}"

        # Initialize conversation
        messages = [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": user_message},
        ]

        final_response = None
        iteration = 0

        while iteration < self.max_iterations:
            iteration += 1

            self._log(f"\n─── Iteration {iteration}/{self.max_iterations} ───")

            try:
                response = self.client.chat.completions.create(
                    model=self.model,
                    messages=messages,
                    tools=self.tools,
                    temperature=self.temperature,
                )
            except Exception as e:
                self._log(f"❌ API Error: {e}")
                break

            choice = response.choices[0]
            msg = choice.message

            # If the model returns a text response (no tool calls)
            if not msg.tool_calls:
                final_response = msg.content
                messages.append({"role": "assistant", "content": final_response})
                self._log(f"✅ Agent finished after {iteration} iterations")
                break

            # ── Handle tool calls ──────────────────────────────────
            assistant_msg = {
                "role": "assistant",
                "content": msg.content or "",
                "tool_calls": [
                    {
                        "id": tc.id,
                        "type": "function",
                        "function": {
                            "name": tc.function.name,
                            "arguments": tc.function.arguments,
                        },
                    }
                    for tc in msg.tool_calls
                ],
            }
            messages.append(assistant_msg)

            # Execute each tool call
            for tc in msg.tool_calls:
                tool_name = tc.function.name
                try:
                    tool_args = json.loads(tc.function.arguments)
                except json.JSONDecodeError:
                    tool_args = {}

                self._log(f"  🔧 {tool_name}({json.dumps(tool_args, ensure_ascii=False)[:120]})")

                # Execute the tool
                try:
                    if tool_name in self.tool_registry:
                        result = self.tool_registry[tool_name](**tool_args)
                    else:
                        result = json.dumps({"status": "error", "message": f"Unknown tool: {tool_name}"})
                except Exception as e:
                    result = json.dumps({"status": "error", "message": str(e)})

                # Truncate if too long (DeepSeek has context limits)
                if len(result) > 8000:
                    result = result[:8000] + "\n... [truncated]"

                messages.append({
                    "role": "tool",
                    "tool_call_id": tc.id,
                    "content": result,
                })

                # Brief log of result
                status = "✅" if '"status": "ok"' in result[:200] else "❌"
                self._log(f"     {status} ({len(result)} chars)")

        # ── Post-loop processing ──────────────────────────────────

        if final_response is None:
            # Max iterations reached — ask model for final summary
            self._log(f"\n⚠️  Max iterations ({self.max_iterations}) reached. Requesting final summary...")
            try:
                messages.append({
                    "role": "user",
                    "content": "You have reached the maximum number of iterations. Please provide your final analysis, conclusions, and recommendations based on all the work done so far."
                })
                response = self.client.chat.completions.create(
                    model=self.model,
                    messages=messages,
                    temperature=self.temperature,
                )
                final_response = response.choices[0].message.content
                messages.append({"role": "assistant", "content": final_response})
            except Exception as e:
                final_response = f"Agent stopped after {iteration} iterations. Last error: {e}"

        # Save conversation for audit
        self._save_conversation(goal, messages, iteration, final_response)

        return {
            "goal": goal,
            "iterations": iteration,
            "final_response": final_response,
            "messages": messages,
            "success": final_response is not None,
        }

    # ── Helpers ───────────────────────────────────────────────────

    def _log(self, msg: str):
        if self.verbose:
            print(msg)

    def _save_conversation(self, goal: str, messages: list, iterations: int, final_response: str):
        """Save the full conversation to a JSON file for audit."""
        ts = time.strftime("%Y%m%d_%H%M%S")
        log_path = self.workspace / f"orbis_session_{ts}.json"
        try:
            log_path.write_text(json.dumps({
                "timestamp": ts,
                "goal": goal,
                "model": self.model,
                "iterations": iterations,
                "final_response": final_response,
                "messages": messages,
            }, ensure_ascii=False, indent=2))
            self._log(f"\n📄 Session saved to: {log_path}")
        except Exception as e:
            self._log(f"\n⚠️  Could not save session: {e}")


# ═══════════════════════════════════════════════════════════════════
# Entry point
# ═══════════════════════════════════════════════════════════════════

def main():
    """CLI entry point."""
    import argparse

    parser = argparse.ArgumentParser(
        description="Orbis — Quantum Chemistry AI Scientist"
    )
    parser.add_argument("goal", nargs="?", help="Scientific goal to accomplish")
    parser.add_argument("--context", "-c", help="Additional context (file path or text)")
    parser.add_argument("--model", "-m", default=MODEL, help=f"Model name (default: {MODEL})")
    parser.add_argument("--max-iter", "-n", type=int, default=MAX_ITERATIONS, help="Max iterations")
    parser.add_argument("--quiet", "-q", action="store_true", help="Suppress progress output")
    parser.add_argument("--api-key", help="API key (overrides env/config)")
    parser.add_argument("--base-url", help="API base URL (overrides env/config)")

    args = parser.parse_args()

    if not args.goal:
        # Interactive mode
        print("🔬 Orbis Agent — Quantum Chemistry AI Scientist")
        print("=" * 50)
        goal = input("Enter your scientific goal: ").strip()
        if not goal:
            print("No goal provided. Exiting.")
            return
    else:
        goal = args.goal

    agent = OrbisAgent(
        api_key=args.api_key,
        base_url=args.base_url,
        model=args.model,
        max_iterations=args.max_iter,
        verbose=not args.quiet,
    )

    result = agent.run(goal, extra_context=args.context or "")

    print("\n" + "=" * 70)
    print("🔬 ORBIS AGENT COMPLETE")
    print("=" * 70)
    print(f"\n{result['final_response']}")


if __name__ == "__main__":
    main()
