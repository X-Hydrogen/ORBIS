"""
Orbis Agent Tools — Quantum Chemistry Tool Set

Tools the AI scientist can call to interact with ORCA, Multiwfn, VMD,
and the filesystem. Each tool returns a JSON-serializable result.
"""

import json
import os
import re
import subprocess
import time
from pathlib import Path
from typing import Optional

from .orbis_config import (
    ORCA_BIN, ORCA_2AIM_BIN, ORCA_2MKL_BIN,
    NPROCS, MAXCORE, TOOL_TIMEOUT, WORKSPACE,
    ORCA_DIR,
)


# ═══════════════════════════════════════════════════════════════════
# Tool Result Helpers
# ═══════════════════════════════════════════════════════════════════

def _ok(data=None, **kwargs) -> str:
    result = {"status": "ok"}
    if data is not None:
        result["data"] = data
    result.update(kwargs)
    return json.dumps(result, ensure_ascii=False, indent=2)


def _error(message: str, **kwargs) -> str:
    result = {"status": "error", "message": message}
    result.update(kwargs)
    return json.dumps(result, ensure_ascii=False, indent=2)


def _run(cmd: str, cwd: str = None, timeout: int = None) -> dict:
    """Run a shell command and return {output, exit_code, success}."""
    t = timeout or TOOL_TIMEOUT
    try:
        result = subprocess.run(
            cmd, shell=True, capture_output=True, text=True,
            cwd=cwd, timeout=t
        )
        return {
            "stdout": result.stdout[-10000:],  # truncate if huge
            "stderr": result.stderr[-5000:],
            "exit_code": result.returncode,
            "success": result.returncode == 0,
        }
    except subprocess.TimeoutExpired:
        return {"stdout": "", "stderr": "TIMEOUT", "exit_code": -1, "success": False}


# ═══════════════════════════════════════════════════════════════════
# Tool: run_orca — Execute an ORCA calculation
# ═══════════════════════════════════════════════════════════════════

def run_orca(inp_content: str, job_name: str = "calc", workdir: str = None) -> str:
    """
    Run an ORCA calculation from input file content.

    Args:
        inp_content: Full ORCA input file content
        job_name: Base name for the job (e.g., 'opt', 'sp', 'neb')
        workdir: Working directory (default: workspace/<job_name>_<timestamp>)
    """
    import datetime
    ts = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    if workdir:
        wd = Path(workdir)
    else:
        wd = WORKSPACE / f"{job_name}_{ts}"
    wd.mkdir(parents=True, exist_ok=True)

    inp_path = wd / f"{job_name}.inp"
    out_path = wd / f"{job_name}.out"

    inp_path.write_text(inp_content)

    start = time.time()
    result = _run(f"'{ORCA_BIN}' {job_name}.inp > {job_name}.out 2>&1", cwd=str(wd))
    elapsed = time.time() - start

    exit_code = result["exit_code"]

    # Read the actual output file (stdout is empty due to shell redirection)
    out_text = ""
    if out_path.exists():
        try:
            out_text = out_path.read_text(encoding='utf-8', errors='replace')
        except Exception:
            out_text = ""

    # Check for normal termination
    converged = bool(re.search(
        r"ORCA TERMINATED NORMALLY|THE OPTIMIZATION HAS CONVERGED|OPTIMIZATION RUN DONE",
        out_text
    ))

    # Extract final energy if available
    energy = None
    m = re.search(r"FINAL SINGLE POINT ENERGY\s+([-\d.]+)", out_text)
    if m:
        energy = float(m.group(1))

    # List output files
    files = [f.name for f in wd.iterdir()]

    return _ok(
        job_name=job_name,
        workdir=str(wd),
        elapsed_seconds=round(elapsed, 1),
        exit_code=exit_code,
        converged=converged,
        energy=energy,
        files=files,
        output_tail=out_text[-3000:],  # last 3000 chars
    )


# ═══════════════════════════════════════════════════════════════════
# Tool: run_iqcap — Execute an iQCAP module
# ═══════════════════════════════════════════════════════════════════

def run_iqcap(module: str, args: str, workdir: str = None) -> str:
    """
    Run an iQCAP shell script module.

    Args:
        module: Module name ('opt', 'basic_elect_analysis', 'elect_interaction', 'ts')
        args: Command-line arguments string
        workdir: Working directory
    """
    module_map = {
        "opt": "orca-opt.sh",
        "basic_elect_analysis": "orca-basic_elect_analysis.sh",
        "basic_elect_analysis_large": "orca-basic_elect_analysis-large_system.sh",
        "elect_interaction": "orca-elect_interaction.sh",
        "ts": "orca-ts.sh",
        "G": "orca-G.sh",
        "summary": "orca-summary.sh",
        "report": "orca-report.sh",
        "adsorption": "orca-adsorption_energy.sh",
        "2d_figs": "orca-2D_elect_figs.sh",
        "cpcm_sp": "orca-sp-CPCM.sh",
    }

    script = module_map.get(module)
    if not script:
        available = ", ".join(module_map.keys())
        return _error(f"Unknown module '{module}'. Available: {available}")

    script_path = ORCA_DIR / script
    if not script_path.exists():
        return _error(f"Script not found: {script_path}")

    wd = Path(workdir) if workdir else WORKSPACE
    wd.mkdir(parents=True, exist_ok=True)

    # Auto-setup iQCAP prerequisites (optimization/ dir, opt.xyz, env file)
    if module in ("basic_elect_analysis", "basic_elect_analysis_large",
                  "elect_interaction", "G", "ts", "adsorption", "2d_figs"):
        _auto_setup_iqcap_prereqs(wd)

    cmd = f"bash '{script_path}' {args}"
    result = _run(cmd, cwd=str(wd))

    return _ok(
        module=module,
        workdir=str(wd),
        exit_code=result["exit_code"],
        success=result["success"],
        stdout=result["stdout"],
        stderr=result["stderr"][:2000],
    )


# ═══════════════════════════════════════════════════════════════════
# Tool: read_xyz — Read an XYZ file
# ═══════════════════════════════════════════════════════════════════

def read_xyz(filepath: str) -> str:
    """Read an XYZ file and return atom count, comment, and coordinates."""
    p = Path(filepath)
    if not p.exists():
        # Try relative to workspace
        p = WORKSPACE / filepath
    if not p.exists():
        return _error(f"File not found: {filepath}")

    lines = p.read_text().strip().split("\n")
    if len(lines) < 3:
        return _error(f"Invalid XYZ file (too few lines): {filepath}")

    try:
        natoms = int(lines[0].strip())
    except ValueError:
        return _error(f"Invalid XYZ file (first line not an integer): {filepath}")

    comment = lines[1].strip()
    atoms = []
    for line in lines[2:2 + natoms]:
        parts = line.strip().split()
        if len(parts) >= 4:
            atoms.append({
                "element": parts[0],
                "x": float(parts[1]),
                "y": float(parts[2]),
                "z": float(parts[3]),
            })

    return _ok(
        filepath=str(p),
        natoms=natoms,
        comment=comment,
        atoms=atoms,
    )


# ═══════════════════════════════════════════════════════════════════
# Tool: write_xyz — Write an XYZ file
# ═══════════════════════════════════════════════════════════════════

def write_xyz(filepath: str, atoms: list, comment: str = "") -> str:
    """
    Write an XYZ file.

    Args:
        filepath: Output path (relative to workspace if not absolute)
        atoms: List of {"element": "C", "x": 0.0, "y": 0.0, "z": 0.0}
        comment: Comment line
    """
    p = Path(filepath)
    if not p.is_absolute():
        p = WORKSPACE / filepath
    p.parent.mkdir(parents=True, exist_ok=True)

    lines = [str(len(atoms)), comment or "Generated by Orbis Agent"]
    for a in atoms:
        lines.append(f"{a['element']:<3s} {a['x']:12.6f} {a['y']:12.6f} {a['z']:12.6f}")

    p.write_text("\n".join(lines) + "\n")
    return _ok(filepath=str(p), natoms=len(atoms))


# ═══════════════════════════════════════════════════════════════════
# Tool: parse_orca_output — Extract key info from ORCA output
# ═══════════════════════════════════════════════════════════════════

def parse_orca_output(filepath: str) -> str:
    """Parse an ORCA output file and extract key results."""
    p = Path(filepath)
    if not p.exists():
        p = WORKSPACE / filepath
    if not p.exists():
        return _error(f"File not found: {filepath}")

    text = p.read_text()

    info = {}

    # Normal termination
    info["normal_termination"] = "ORCA TERMINATED NORMALLY" in text

    # Final single point energy
    m = re.search(r"FINAL SINGLE POINT ENERGY\s+([-\d.]+)", text)
    if m:
        info["final_sp_energy"] = float(m.group(1))

    # Optimization convergence
    info["opt_converged"] = "THE OPTIMIZATION HAS CONVERGED" in text

    # Frequencies
    freqs = re.findall(r"(\d+):\s+([-\d.]+)\s+cm\*\*-1", text)
    if freqs:
        info["frequencies"] = [(int(idx), float(f)) for idx, f in freqs]
        imaginary = [(idx, f) for idx, f in info["frequencies"] if f < 0]
        info["imaginary_frequencies"] = imaginary
        info["n_imaginary"] = len(imaginary)

    # Gibbs free energy
    m = re.search(r"Final Gibbs free energy\s*:\s*([-\d.]+)\s+Eh", text)
    if m:
        info["gibbs_free_energy"] = float(m.group(1))

    # NEB barrier
    m = re.search(r"Barrier\s+height\s*:\s*([-\d.]+)", text)
    if m:
        info["neb_barrier"] = float(m.group(1))

    # IRC
    if "IRC PATH SUMMARY" in text:
        info["has_irc"] = True

    return _ok(**info)


# ═══════════════════════════════════════════════════════════════════
# Tool: list_files — List files in a directory
# ═══════════════════════════════════════════════════════════════════

def list_files(directory: str = ".", pattern: str = "*") -> str:
    """List files in a directory, optionally filtering by glob pattern."""
    import fnmatch
    p = Path(directory)
    if not p.is_absolute():
        p = WORKSPACE / directory
    if not p.exists():
        return _error(f"Directory not found: {directory}")

    files = []
    for f in sorted(p.rglob(pattern)):
        if f.is_file():
            files.append({
                "path": str(f.relative_to(p)),
                "size": f.stat().st_size,
            })

    return _ok(directory=str(p), count=len(files), files=files[:100])


# ═══════════════════════════════════════════════════════════════════
# Tool: read_file — Read any file content
# ═══════════════════════════════════════════════════════════════════

def read_file(filepath: str, max_lines: int = 200) -> str:
    """Read a file's content."""
    p = Path(filepath)
    if not p.is_absolute():
        p = WORKSPACE / filepath
    if not p.exists():
        return _error(f"File not found: {filepath}")

    try:
        lines = p.read_text().split("\n")
        total = len(lines)
        if total > max_lines:
            content = "\n".join(lines[:max_lines])
            return _ok(
                filepath=str(p),
                total_lines=total,
                shown_lines=max_lines,
                content=content,
                truncated=True,
            )
        return _ok(
            filepath=str(p),
            total_lines=total,
            content="\n".join(lines),
        )
    except UnicodeDecodeError:
        return _ok(filepath=str(p), size=p.stat().st_size, binary=True)


# ═══════════════════════════════════════════════════════════════════
# Tool: write_file — Write content to a file
# ═══════════════════════════════════════════════════════════════════

def write_file(filepath: str, content: str) -> str:
    """Write content to a file."""
    p = Path(filepath)
    if not p.is_absolute():
        p = WORKSPACE / filepath
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(content)
    return _ok(filepath=str(p), size=p.stat().st_size)


# ═══════════════════════════════════════════════════════════════════
# Tool: check_orca_processes — Check running ORCA jobs
# ═══════════════════════════════════════════════════════════════════

def check_orca_processes() -> str:
    """Check for currently running ORCA processes."""
    result = _run("ps aux | grep -i orca | grep -v grep | grep -v orca_")
    if not result["stdout"].strip():
        return _ok(running=False, processes=[])
    
    procs = []
    for line in result["stdout"].strip().split("\n"):
        if line.strip():
            procs.append(line.strip())
    
    return _ok(running=True, count=len(procs), processes=procs)


# ═══════════════════════════════════════════════════════════════════
# Tool: kill_orca — Kill running ORCA processes
# ═══════════════════════════════════════════════════════════════════

def kill_orca() -> str:
    """Kill all running ORCA processes."""
    _run("pkill -f orca_leanscf_mpi 2>/dev/null; pkill -f 'mpirun.*orca' 2>/dev/null; pkill -f 'sh -c.*orca' 2>/dev/null; pkill -f 'orca.*\\.inp' 2>/dev/null")
    time.sleep(1)
    remaining = _run("ps aux | grep -i orca | grep -v grep | wc -l")
    return _ok(remaining_processes=int(remaining["stdout"].strip() or 0))


def _auto_setup_iqcap_prereqs(workdir: Path):
    """Ensure iQCAP prerequisite directory structure exists."""
    opt_dir = workdir / "optimization"
    opt_dir.mkdir(parents=True, exist_ok=True)

    # Find or create opt.xyz — search for ANY .xyz file in workdir
    opt_xyz = opt_dir / "opt.xyz"
    if not opt_xyz.exists():
        # Priority: exact names first, then any .xyz file
        candidates = [workdir / name for name in ("opt.xyz", "h2o_opt.xyz", "dimer_opt.xyz")]
        candidates += sorted(workdir.glob("*.xyz"))  # fallback: any .xyz
        for c in candidates:
            if c.exists():
                opt_xyz.write_text(c.read_text())
                break

    # Create symlink in workdir root for scripts that expect ./opt.xyz
    root_link = workdir / "opt.xyz"
    if not root_link.exists() and opt_xyz.exists():
        try:
            root_link.symlink_to(opt_xyz)
        except OSError:
            pass

    # Create iqcap_orca.env if missing
    env_file = opt_dir / "iqcap_orca.env"
    if not env_file.exists():
        env_file.write_text(f"""ORCA_BIN="{ORCA_BIN}"
ORCA_2AIM_BIN="{ORCA_2AIM_BIN}"
ORCA_2MKL_BIN="{ORCA_2MKL_BIN}"
MULTIWFN_BIN="/home/quantum/tools/Multiwfn/multiwfn"
VMD_BIN="/usr/local/bin/vmd"
NPROCS={NPROCS}
MAXCORE={MAXCORE}
SP_LEVEL="B3LYP D3BJ def2-TZVP(-f) def2/J RIJCOSX tightSCF"
METHOD="B3LYP D3BJ def2-TZVP(-f) def2/J RIJCOSX"
""")

    return opt_xyz, env_file


def compute_binding_energy(
    dimer_out_path: str,
    monomer_A_out_path: str,
    monomer_B_out_path: str,
) -> str:
    """
    Compute BSSE-uncorrected binding energy from ORCA output files.

    Args:
        dimer_out_path: Path to the dimer/complex ORCA output
        monomer_A_out_path: Path to monomer A ORCA output
        monomer_B_out_path: Path to monomer B ORCA output

    Returns:
        JSON with binding energy in Hartree, kcal/mol, and kJ/mol
    """
    energies = {}
    for label, path in [("dimer", dimer_out_path), ("monomer_A", monomer_A_out_path),
                         ("monomer_B", monomer_B_out_path)]:
        try:
            content = Path(path).read_text()
            # Find ALL energy matches and take the LAST one (for opt jobs,
            # the final energy is the converged one near the end of the file)
            matches = re.findall(r'FINAL SINGLE POINT ENERGY\s+([-\d.]+)', content)
            if matches:
                energies[label] = float(matches[-1])
            else:
                return _error(f"Could not find energy in {path}")
        except FileNotFoundError:
            return _error(f"File not found: {path}")

    dE_hartree = energies["dimer"] - energies["monomer_A"] - energies["monomer_B"]
    dE_kcal = dE_hartree * 627.509
    dE_kJ = dE_hartree * 2625.5

    return _ok(
        binding_energy_hartree=round(dE_hartree, 8),
        binding_energy_kcal_mol=round(dE_kcal, 2),
        binding_energy_kJ_mol=round(dE_kJ, 2),
        dimer_energy=energies["dimer"],
        monomer_A_energy=energies["monomer_A"],
        monomer_B_energy=energies["monomer_B"],
        note="BSSE (counterpoise) correction not applied. For CP-corrected values, run monomer calculations in the dimer basis set.",
    )


def compile_paper_pdf(paper_dir: str, fig_dir: str = None) -> str:
    """
    Compile a PDF from the generated paper using fpdf2 (no LaTeX required).
    Reads the .tex file, extracts content, and produces a PDF with embedded figures.

    Args:
        paper_dir: Directory containing manuscript.tex and figures/
        fig_dir: Override figure directory (default: paper_dir/figures)

    Returns:
        JSON with pdf_path
    """
    pdir = Path(paper_dir)
    tex_path = pdir / "tex" / "manuscript.tex"
    if not tex_path.exists():
        tex_path = pdir / "manuscript.tex"

    if not tex_path.exists():
        return _error(f"No manuscript.tex found in {paper_dir}")

    fig_path = Path(fig_dir) if fig_dir else (pdir / "figures")
    pdf_path = pdir / "manuscript.pdf"

    try:
        from fpdf import FPDF
        import re as _re

        class QuickPDF(FPDF):
            def __init__(self):
                super().__init__('P', 'mm', 'A4')
                self.set_auto_page_break(True, 18)
                font_dir = '/usr/share/fonts/truetype/dejavu/'
                for n, s, f in [('D', '', 'DejaVuSans.ttf'),
                                ('D', 'B', 'DejaVuSans-Bold.ttf')]:
                    if Path(font_dir + f).exists():
                        self.add_font(n, s, font_dir + f)

            def header(self):
                if self.page_no() > 1:
                    self.set_font('D', '', 7)
                    self.set_text_color(128, 128, 128)
                    self.cell(0, 4, 'Orbis+iQCAP — Automated Quantum Chemistry', align='L')
                    self.cell(0, 4, str(self.page_no()), align='R',
                              new_x="LMARGIN", new_y="NEXT")
                    self.line(self.l_margin, self.get_y(),
                              self.w - self.r_margin, self.get_y())
                    self.ln(2)

        pdf = QuickPDF()
        pdf.set_margin(18)
        pdf.add_page()

        # Simplified: read the LaTeX, strip all commands, keep plain text
        tex = tex_path.read_text()
        
        # Remove LaTeX preamble (everything before \begin{document})
        doc_start = tex.find(r'\begin{document}')
        if doc_start >= 0:
            tex = tex[doc_start:]
        
        # Aggressively strip LaTeX commands
        tex = _re.sub(r'\\usepackage(\[.*?\])?\{.*?\}', '', tex)
        tex = _re.sub(r'\\documentclass(\[.*?\])?\{.*?\}', '', tex)
        tex = _re.sub(r'\\begin\{document\}', '', tex)
        tex = _re.sub(r'\\end\{document\}', '', tex)
        tex = _re.sub(r'\\begin\{abstract\}.*?\\end\{abstract\}', '', tex, flags=_re.DOTALL)
        tex = _re.sub(r'\\begin\{figure\}.*?\\end\{figure\}', ' [Figure] ', tex, flags=_re.DOTALL)
        tex = _re.sub(r'\\begin\{table\}.*?\\end\{table\}', ' [Table] ', tex, flags=_re.DOTALL)
        tex = _re.sub(r'\\maketitle', '', tex)
        tex = _re.sub(r'\\newpage', '', tex)
        tex = _re.sub(r'\\[a-zA-Z]+(\[.*?\])?(\{.*?\})?', ' ', tex)
        tex = _re.sub(r'[$\\]{1,2}[^$\\]*[$\\]{1,2}', ' ', tex)
        tex = _re.sub(r'\s+', ' ', tex).strip()

        # Try to find sections
        sections = []
        for m in _re.finditer(r'(?:section|subsection)\*?\{(.+?)\}', tex):
            sections.append(m.group(1))
        
        if sections:
            pdf.set_font('D', 'B', 16)
            pdf.multi_cell(0, 8, sections[0] if sections else 'Research Paper', align='C')
            pdf.ln(10)
            
            for sec in sections[1:]:
                pdf.set_font('D', 'B', 11)
                pdf.set_text_color(0, 51, 102)
                # Prevent empty/invalid titles from breaking layout
                safe_title = sec.strip()[:80] if sec.strip() else 'Section'
                pdf.cell(0, 6, safe_title, new_x="LMARGIN", new_y="NEXT")
                pdf.set_text_color(0, 0, 0)
                pdf.ln(2)
        else:
            # No sections found — just print cleaned text
            pdf.set_font('D', 'B', 14)
            safe_title = "Computational Chemistry Research Paper"
            pdf.cell(0, 8, safe_title, align='C', new_x="LMARGIN", new_y="NEXT")
            pdf.ln(8)

        # Add cleaned body text (truncated)
        body = _re.sub(r'\{.*?\}', '', tex)  # remove remaining braces
        body = _re.sub(r'\s+', ' ', body).strip()
        if len(body) > 100:
            pdf.set_font('D', '', 8)
            pdf.multi_cell(0, 4, body[:5000], align='J')

        # Embed figures if available
        if fig_path.exists():
            pngs = sorted(fig_path.glob("*.png"))
            for png in pngs[:12]:  # Max 12 figures
                try:
                    pdf.add_page()
                    pdf.set_font('D', 'B', 10)
                    name = png.stem.replace('_', ' ').replace('fig ', '')
                    pdf.cell(0, 5, f'Figure: {name}', align='C', new_x="LMARGIN", new_y="NEXT")
                    pdf.ln(2)
                    # Scale image to fit page width
                    pdf.image(str(png), x=pdf.l_margin, w=pdf.w - pdf.l_margin - pdf.r_margin)
                except Exception:
                    pass  # Skip problematic images

        pdf.output(str(pdf_path))
        return _ok(
            pdf_path=str(pdf_path),
            pages=pdf.pages_count,
            size_bytes=pdf_path.stat().st_size,
        )

    except Exception as e:
        import traceback
        return _error(f"PDF compilation failed: {e}\n\n{traceback.format_exc()}")


# ═══════════════════════════════════════════════════════════════════
# Tool Registry
# ═══════════════════════════════════════════════════════════════════

def generate_research_paper(
    paper_data_json: str,
    output_dir: str = None,
) -> str:
    """
    Generate a complete research paper (LaTeX + Word) from computational results.

    Args:
        paper_data_json: JSON string with paper content. Required keys:
            - title: Paper title
            - abstract: Abstract text
            - introduction: Introduction section
            - methods: Computational methods section
            - results_discussion: Results and Discussion section
            - conclusions: Conclusions section
            - acknowledgements: (optional) Acknowledgements
            - authors: (optional) Author list, default "Hengyue Xu"
            - affiliation: (optional) Affiliation
            - methods_used: (optional) {functional, basis, dispersion, ...}
            - optimized_xyz: (optional) Path to optimized XYZ for structure figure
            - orbital_energies: (optional) {HOMO: -x.x, LUMO: -x.x, ...} in eV
            - frequencies: (optional) List of harmonic frequencies in cm^-1
            - ir_intensities: (optional) List of IR intensities in km/mol
            - energy_comparison: (optional) {label: value} dict for bar chart
        output_dir: Output directory (default: workspace/paper_output/)
    """
    import json as _json
    from pathlib import Path as _Path

    try:
        data = _json.loads(paper_data_json)
    except _json.JSONDecodeError as e:
        return _error(f"Invalid JSON: {e}")

    if output_dir:
        out = _Path(output_dir)
    else:
        import datetime
        ts = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
        out = WORKSPACE / f"paper_{ts}"
    out.mkdir(parents=True, exist_ok=True)

    try:
        # Add orbis to path for paper module import
        import sys as _sys
        _orbis_home = str(_Path(__file__).resolve().parent.parent)
        if _orbis_home not in _sys.path:
            _sys.path.insert(0, _orbis_home)

        from paper.generator import PaperGenerator

        gen = PaperGenerator(
            output_dir=str(out),
            title=data.get("title", "Computational Study"),
            authors=data.get("authors", "Hengyue Xu"),
            affiliation=data.get("affiliation", "Independent Researcher"),
            short_title=data.get("title", "Computational Study")[:60],
        )

        result = gen.generate(
            abstract=data.get("abstract", ""),
            introduction=data.get("introduction", ""),
            methods=data.get("methods", ""),
            results_discussion=data.get("results_discussion", ""),
            conclusions=data.get("conclusions", ""),
            acknowledgements=data.get("acknowledgements", ""),
            results_data=data,
        )

        # Auto-compile PDF if LaTeX compiler not available
        if not result.get("pdf_path"):
            try:
                pdf_result = compile_paper_pdf(str(out))
                import json as _j2
                pdf_data = _j2.loads(pdf_result)
                if pdf_data.get("status") == "ok":
                    result["pdf_path"] = pdf_data.get("pdf_path", "")
            except Exception:
                pass  # PDF compilation is best-effort

        return _ok(
            output_dir=str(out),
            tex_path=result.get("tex_path", ""),
            pdf_path=result.get("pdf_path", ""),
            docx_path=result.get("docx_path", ""),
            message="Paper generated successfully. Files available at the paths above.",
        )

    except Exception as e:
        import traceback
        return _error(f"Paper generation failed: {e}\n\n{traceback.format_exc()}")


TOOL_REGISTRY = {
    "run_orca": run_orca,
    "run_iqcap": run_iqcap,
    "read_xyz": read_xyz,
    "write_xyz": write_xyz,
    "parse_orca_output": parse_orca_output,
    "list_files": list_files,
    "read_file": read_file,
    "write_file": write_file,
    "check_orca_processes": check_orca_processes,
    "kill_orca": kill_orca,
    "generate_research_paper": generate_research_paper,
    "compute_binding_energy": compute_binding_energy,
    "compile_paper_pdf": compile_paper_pdf,
}

# OpenAI function definitions for each tool
TOOL_DEFINITIONS = [
    {
        "type": "function",
        "function": {
            "name": "run_orca",
            "description": "Run an ORCA quantum chemistry calculation. Provide the full ORCA input file content. Returns exit code, energy, convergence status, and output files.",
            "parameters": {
                "type": "object",
                "properties": {
                    "inp_content": {
                        "type": "string",
                        "description": "Full ORCA input file content, including ! keyword line, %pal/%maxcore blocks, *xyz block with coordinates."
                    },
                    "job_name": {
                        "type": "string",
                        "description": "Short name for the job: 'opt', 'sp', 'freq', 'neb', 'ts', 'irc'.",
                        "default": "calc"
                    },
                    "workdir": {
                        "type": "string",
                        "description": "Working directory. Auto-created if not specified."
                    }
                },
                "required": ["inp_content", "job_name"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "run_iqcap",
            "description": "Run an iQCAP workflow module. Modules: opt, basic_elect_analysis (≤100 atoms), basic_elect_analysis_large (>100 atoms, uses orca_plot), elect_interaction, ts, G, summary, report, adsorption, 2d_figs.",
            "parameters": {
                "type": "object",
                "properties": {
                    "module": {
                        "type": "string",
                        "description": "Module name: 'opt', 'basic_elect_analysis', 'elect_interaction', 'ts', 'G', 'summary', 'report', 'adsorption', '2d_figs'."
                    },
                    "args": {
                        "type": "string",
                        "description": "Command-line arguments to pass to the iQCAP module script."
                    },
                    "workdir": {
                        "type": "string",
                        "description": "Working directory."
                    }
                },
                "required": ["module", "args"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "read_xyz",
            "description": "Read an XYZ molecular structure file. Returns atom count, comment, and atomic coordinates.",
            "parameters": {
                "type": "object",
                "properties": {
                    "filepath": {"type": "string", "description": "Path to the XYZ file."}
                },
                "required": ["filepath"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "write_xyz",
            "description": "Write a new XYZ molecular structure file.",
            "parameters": {
                "type": "object",
                "properties": {
                    "filepath": {"type": "string", "description": "Output path for the XYZ file."},
                    "atoms": {
                        "type": "array",
                        "items": {
                            "type": "object",
                            "properties": {
                                "element": {"type": "string"},
                                "x": {"type": "number"},
                                "y": {"type": "number"},
                                "z": {"type": "number"}
                            },
                            "required": ["element", "x", "y", "z"]
                        },
                        "description": "List of atoms with element and coordinates."
                    },
                    "comment": {"type": "string", "description": "Comment line for the XYZ file."}
                },
                "required": ["filepath", "atoms"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "parse_orca_output",
            "description": "Parse an ORCA output file to extract key results: energy, convergence, frequencies, Gibbs free energy, NEB barrier, IRC info.",
            "parameters": {
                "type": "object",
                "properties": {
                    "filepath": {"type": "string", "description": "Path to the ORCA .out file."}
                },
                "required": ["filepath"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "list_files",
            "description": "List files in a directory, optionally filtering by glob pattern.",
            "parameters": {
                "type": "object",
                "properties": {
                    "directory": {"type": "string", "description": "Directory path. Default: current workspace."},
                    "pattern": {"type": "string", "description": "Glob pattern, e.g., '*.xyz', '*.out'. Default: '*'."}
                },
                "required": []
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "read_file",
            "description": "Read content from any text file. Useful for inspecting ORCA outputs, logs, or intermediate files.",
            "parameters": {
                "type": "object",
                "properties": {
                    "filepath": {"type": "string", "description": "Path to the file."},
                    "max_lines": {"type": "integer", "description": "Max lines to return (default 200)."}
                },
                "required": ["filepath"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "write_file",
            "description": "Write content to a file. Use for saving results, creating input files, or logging.",
            "parameters": {
                "type": "object",
                "properties": {
                    "filepath": {"type": "string", "description": "Output path."},
                    "content": {"type": "string", "description": "Content to write."}
                },
                "required": ["filepath", "content"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "check_orca_processes",
            "description": "Check for currently running ORCA calculation processes on this machine.",
            "parameters": {"type": "object", "properties": {}}
        }
    },
    {
        "type": "function",
        "function": {
            "name": "kill_orca",
            "description": "Kill all running ORCA processes. Use with caution.",
            "parameters": {"type": "object", "properties": {}}
        }
    },
    {
        "type": "function",
        "function": {
            "name": "generate_research_paper",
            "description": "Generate a complete submission-ready research paper (LaTeX .tex + Word .docx) from computational results. Requires a JSON string with all paper sections (abstract, introduction, methods, results_discussion, conclusions) and optional computational data for automatic figure generation. Use this as the FINAL step after all calculations are complete.",
            "parameters": {
                "type": "object",
                "properties": {
                    "paper_data_json": {
                        "type": "string",
                        "description": "JSON string containing all paper content. Required: title, abstract, introduction, methods, results_discussion, conclusions. Optional: acknowledgements, authors, affiliation, methods_used (dict with functional/basis/dispersion keys), optimized_xyz (path), orbital_energies (dict), frequencies (array), ir_intensities (array), energy_comparison (dict)."
                    },
                    "output_dir": {
                        "type": "string",
                        "description": "Output directory for generated paper files."
                    }
                },
                "required": ["paper_data_json"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "compute_binding_energy",
            "description": "Compute the binding energy of a dimer/complex from ORCA output files of the dimer and its constituent monomers. Returns energy in Hartree, kcal/mol, and kJ/mol.",
            "parameters": {
                "type": "object",
                "properties": {
                    "dimer_out_path": {"type": "string", "description": "Path to the dimer/complex ORCA output file."},
                    "monomer_A_out_path": {"type": "string", "description": "Path to monomer A ORCA output file."},
                    "monomer_B_out_path": {"type": "string", "description": "Path to monomer B ORCA output file."}
                },
                "required": ["dimer_out_path", "monomer_A_out_path", "monomer_B_out_path"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "compile_paper_pdf",
            "description": "Compile the generated paper into a PDF file using fpdf2 (no LaTeX required). Call this AFTER generate_research_paper to produce the final deliverable PDF.",
            "parameters": {
                "type": "object",
                "properties": {
                    "paper_dir": {"type": "string", "description": "Directory containing the generated paper (manuscript.tex and figures/)."},
                    "fig_dir": {"type": "string", "description": "Optional override for the figures directory."}
                },
                "required": ["paper_dir"]
            }
        }
    },
]
