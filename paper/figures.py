"""
Figure Generator for Orbis Papers

Auto-generates publication-quality figures from ORCA output data.
Uses matplotlib with LaTeX-compatible styling.
"""

import json
import re
from pathlib import Path
from typing import Optional

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.ticker as ticker
import numpy as np

# ── Styling ───────────────────────────────────────────────────────

plt.rcParams.update({
    "font.family": "serif",
    "font.size": 11,
    "axes.labelsize": 12,
    "axes.titlesize": 13,
    "legend.fontsize": 10,
    "figure.dpi": 150,
    "savefig.dpi": 300,
    "savefig.bbox": "tight",
    "savefig.pad_inches": 0.1,
    "axes.linewidth": 1.2,
    "xtick.major.width": 1.0,
    "ytick.major.width": 1.0,
})

COLORS = {
    "O": "#FF4444",
    "H": "#CCCCCC",
    "C": "#444444",
    "N": "#3333FF",
    "S": "#FFCC00",
    "P": "#FF8800",
    "F": "#33FFCC",
    "Cl": "#33FF33",
    "Br": "#883300",
    "I": "#6600AA",
    "default": "#888888",
}


def element_color(symbol: str) -> str:
    return COLORS.get(symbol, COLORS["default"])


# ── Figure: Energy Level Diagram (HOMO/LUMO) ─────────────────────

def generate_energy_level_diagram(
    energies: dict,
    output_path: str,
    title: str = "Frontier Molecular Orbital Energies",
):
    """
    Generate HOMO/LUMO energy level diagram.

    Args:
        energies: dict with keys like 'HOMO', 'LUMO', 'HOMO-1', 'LUMO+1' etc.
                  Values in eV.
        output_path: where to save the PNG
        title: plot title
    """
    fig, ax = plt.subplots(figsize=(5, 6))

    # Sort orbitals
    orbital_names = []
    orbital_energies = []

    for label in sorted(energies.keys(),
                         key=lambda x: energies.get(x, 0)):
        orbital_names.append(label)
        orbital_energies.append(energies[label])

    y_positions = list(range(len(orbital_energies)))
    colors_list = ["#4472C4" if e < 0 else "#ED7D31"
                   for e in orbital_energies]

    bars = ax.barh(y_positions, orbital_energies, height=0.5,
                   color=colors_list, edgecolor="black", linewidth=0.5)

    ax.set_yticks(y_positions)
    ax.set_yticklabels(orbital_names)
    ax.set_xlabel("Energy (eV)")
    ax.set_title(title, fontweight="bold")

    # Add value labels
    for bar, energy in zip(bars, orbital_energies):
        x_pos = bar.get_width()
        ax.text(x_pos + 0.05 * max(abs(e) for e in orbital_energies or [1]),
                bar.get_y() + bar.get_height() / 2,
                f"{energy:.3f}", va="center", fontsize=9)

    # HOMO-LUMO gap annotation
    if "HOMO" in energies and "LUMO" in energies:
        gap = energies["LUMO"] - energies["HOMO"]
        ax.axhline(y=orbital_names.index("HOMO") + 0.25, color="green",
                   linestyle="--", linewidth=1, alpha=0.7)
        ax.axhline(y=orbital_names.index("LUMO") - 0.25, color="green",
                   linestyle="--", linewidth=1, alpha=0.7)
        mid = (orbital_names.index("HOMO") + orbital_names.index("LUMO")) / 2
        ax.annotate(f"Gap = {gap:.2f} eV",
                    xy=(0, mid), xytext=(0.5, 0.5),
                    textcoords="axes fraction",
                    fontsize=10, fontweight="bold", color="green",
                    ha="center", va="center",
                    bbox=dict(boxstyle="round,pad=0.3",
                              facecolor="lightgreen", alpha=0.3))

    ax.axvline(x=0, color="black", linewidth=0.8, linestyle="--", alpha=0.5)
    ax.grid(axis="x", alpha=0.3, linestyle="--")
    ax.invert_yaxis()

    plt.tight_layout()
    fig.savefig(output_path, dpi=300)
    plt.close(fig)

    # Return LaTeX figure code
    basename = Path(output_path).stem
    return (
        r"\begin{figure}[htbp]" + "\n"
        r"  \centering" + "\n"
        r"  \includegraphics[width=0.55\textwidth]{" + basename + "}\n"
        r"  \caption{Frontier molecular orbital energy levels. "
        r"The HOMO--LUMO gap is " + f"{gap:.2f}" + r" eV.}" + "\n"
        r"  \label{fig:energy-levels}" + "\n"
        r"\end{figure}"
    )


# ── Figure: IR Spectrum (from ORCA frequencies) ──────────────────

def generate_ir_spectrum(
    frequencies: list,
    intensities: list,
    output_path: str,
    title: str = "Simulated IR Spectrum",
    broadening: float = 15.0,
    x_range: tuple = None,
):
    """
    Generate simulated IR spectrum from ORCA frequencies.

    Args:
        frequencies: list of frequencies in cm^-1
        intensities: list of IR intensities in km/mol
        output_path: PNG output path
        title: plot title
        broadening: Lorentzian broadening FWHM in cm^-1
        x_range: (min, max) cm^-1 range
    """
    if not frequencies:
        return r"% No IR data available"

    fig, ax = plt.subplots(figsize=(8, 4))

    # Generate broadened spectrum
    if x_range is None:
        x_min = max(0, min(frequencies) - 200)
        x_max = max(frequencies) + 200
    else:
        x_min, x_max = x_range

    x = np.linspace(x_min, x_max, 2000)
    y = np.zeros_like(x)

    gamma = broadening / 2.0
    for freq, intens in zip(frequencies, intensities):
        y += intens * (gamma ** 2) / ((x - freq) ** 2 + gamma ** 2)

    # Normalize
    if y.max() > 0:
        y = y / y.max() * 100

    ax.plot(x, y, color="#2E5090", linewidth=1.2)
    ax.fill_between(x, 0, y, color="#2E5090", alpha=0.15)

    # Stick spectrum overlay
    for freq, intens in zip(frequencies, intensities):
        if intens > 0:
            scaled = intens / max(intensities) * 95 if max(intensities) > 0 else 0
            ax.vlines(freq, 0, scaled, colors="#CC3333",
                      linewidth=0.8, alpha=0.6)

    ax.set_xlabel(r"Wavenumber (cm$^{-1}$)")
    ax.set_ylabel("Relative Intensity (%)")
    ax.set_title(title, fontweight="bold")
    ax.set_xlim(x_min, x_max)
    ax.set_ylim(0, 105)
    ax.grid(alpha=0.3, linestyle="--")
    ax.tick_params(direction="in", top=True, right=True)

    # Invert x-axis (standard in chemistry)
    ax.invert_xaxis()

    plt.tight_layout()
    fig.savefig(output_path, dpi=300)
    plt.close(fig)

    basename = Path(output_path).stem
    return (
        r"\begin{figure}[htbp]" + "\n"
        r"  \centering" + "\n"
        r"  \includegraphics[width=0.85\textwidth]{" + basename + "}\n"
        r"  \caption{Simulated IR spectrum from harmonic vibrational "
        r"frequency analysis. Lorentzian broadening with FWHM = "
        + f"{broadening:.0f}" + r" cm$^{-1}$ was applied.}" + "\n"
        r"  \label{fig:ir-spectrum}" + "\n"
        r"\end{figure}"
    )


# ── Figure: Molecular Structure (XYZ → 2D rendering) ──────────────

def generate_structure_figure(
    xyz_path: str,
    output_path: str,
    title: str = "Optimized Molecular Geometry",
    label_distances: list = None,
):
    """
    Generate 2D structure representation from XYZ file.
    Uses simple projection; for 3D, VMD rendering is preferred.

    Args:
        xyz_path: path to XYZ file
        output_path: PNG output path
        title: figure title
        label_distances: list of (atom_i, atom_j) pairs to label distances (0-indexed)
    """
    # Read XYZ
    lines = Path(xyz_path).read_text().strip().split("\n")
    natoms = int(lines[0])
    atoms = []
    for line in lines[2:2 + natoms]:
        parts = line.strip().split()
        if len(parts) >= 4:
            atoms.append({
                "elem": parts[0],
                "x": float(parts[1]),
                "y": float(parts[2]),
                "z": float(parts[3])
            })

    if not atoms:
        return r"% No structure data available"

    fig, ax = plt.subplots(figsize=(6, 5))

    coords = np.array([[a["x"], a["y"], a["z"]] for a in atoms])
    elem_list = [a["elem"] for a in atoms]

    # Project onto XY plane (or use best 2D view)
    xs = coords[:, 0]
    ys = coords[:, 1]

    # Center the structure
    xs -= xs.mean()
    ys -= ys.mean()

    # Draw atoms as circles
    for i, (x, y, elem) in enumerate(zip(xs, ys, elem_list)):
        color = element_color(elem)
        size = {"H": 80, "C": 200, "N": 200, "O": 200, "S": 250,
                "P": 250, "F": 160, "Cl": 280,
                "default": 200}.get(elem, 200)
        ax.scatter(x, y, s=size, c=color, edgecolors="black",
                   linewidth=0.8, zorder=3)
        ax.annotate(elem, (x, y),
                    textcoords="offset points",
                    xytext=(0, -size / 25 - 8),
                    ha="center", fontsize=8, fontweight="bold")

    # Draw bonds (simple distance-based)
    for i in range(natoms):
        for j in range(i + 1, natoms):
            dx = xs[i] - xs[j]
            dy = ys[i] - ys[j]
            dz = coords[i, 2] - coords[j, 2]
            dist = np.sqrt(dx ** 2 + dy ** 2 + dz ** 2)
            max_bond = {"H": 1.2, "C": 1.8, "N": 1.7, "O": 1.7,
                        "S": 2.2, "P": 2.2,
                        "F": 1.6, "Cl": 2.2}.get(elem_list[i],
                                                {"H": 1.2, "C": 1.8}.get(
                                                    elem_list[j], 1.8))
            if dist < max_bond:
                ax.plot([xs[i], xs[j]], [ys[i], ys[j]],
                        color="gray", linewidth=1.5, zorder=1, alpha=0.7)

    # Label distances if requested
    if label_distances:
        for ai, aj in label_distances:
            if ai < natoms and aj < natoms:
                dx = xs[ai] - xs[aj]
                dy = ys[ai] - ys[aj]
                dz = coords[ai, 2] - coords[aj, 2]
                dist = np.sqrt(dx ** 2 + dy ** 2 + dz ** 2)
                mid_x = (xs[ai] + xs[aj]) / 2
                mid_y = (ys[ai] + ys[aj]) / 2
                ax.annotate(f"{dist:.3f} Å",
                            (mid_x, mid_y),
                            fontsize=8, color="#CC3333",
                            ha="center", va="bottom",
                            bbox=dict(boxstyle="round,pad=0.2",
                                      facecolor="white", alpha=0.8))

    ax.set_aspect("equal")
    ax.set_title(title, fontweight="bold")
    ax.axis("off")

    # Auto-scale
    margin = 1.0
    ax.set_xlim(xs.min() - margin, xs.max() + margin)
    ax.set_ylim(ys.min() - margin, ys.max() + margin)

    plt.tight_layout()
    fig.savefig(output_path, dpi=300)
    plt.close(fig)

    basename = Path(output_path).stem
    return (
        r"\begin{figure}[htbp]" + "\n"
        r"  \centering" + "\n"
        r"  \includegraphics[width=0.6\textwidth]{" + basename + "}\n"
        r"  \caption{Optimized molecular geometry. "
        r"Key bond distances are indicated in \AA ngstr\"{o}m.}" + "\n"
        r"  \label{fig:structure}" + "\n"
        r"\end{figure}"
    )


# ── Figure: Energy Comparison Bar Chart ──────────────────────────

def generate_energy_comparison(
    data: dict,
    output_path: str,
    title: str = "Energy Comparison",
    ylabel: str = "Energy (kcal/mol)",
    reference_label: str = None,
):
    """
    Generate comparative energy bar chart.

    Args:
        data: {label: energy_value} dict
        output_path: PNG output
        title: plot title
        ylabel: y-axis label
        reference_label: label to use as zero reference
    """
    fig, ax = plt.subplots(figsize=(6, 4))

    labels = list(data.keys())
    values = list(data.values())

    # Shift to reference if provided
    if reference_label and reference_label in data:
        ref_val = data[reference_label]
        values = [v - ref_val for v in values]

    colors_list = plt.cm.Set2(np.linspace(0, 1, len(labels)))

    bars = ax.bar(range(len(labels)), values, color=colors_list,
                  edgecolor="black", linewidth=0.5)

    # Value labels on bars
    for bar, val in zip(bars, values):
        y_pos = bar.get_height()
        va = "bottom" if y_pos >= 0 else "top"
        offset = 0.02 * max(abs(v) for v in values or [1])
        ax.text(bar.get_x() + bar.get_width() / 2,
                y_pos + offset * (1 if y_pos >= 0 else -1),
                f"{val:.2f}", ha="center", va=va, fontsize=9)

    ax.set_xticks(range(len(labels)))
    ax.set_xticklabels(labels, rotation=30, ha="right")
    ax.set_ylabel(ylabel)
    ax.set_title(title, fontweight="bold")
    ax.grid(axis="y", alpha=0.3, linestyle="--")

    if reference_label:
        ax.axhline(y=0, color="black", linewidth=0.8)
        ax.annotate(f"Reference: {reference_label}",
                    xy=(0.98, 0.02), xycoords="axes fraction",
                    ha="right", fontsize=8, fontstyle="italic",
                    color="gray")

    plt.tight_layout()
    fig.savefig(output_path, dpi=300)
    plt.close(fig)

    basename = Path(output_path).stem
    return (
        r"\begin{figure}[htbp]" + "\n"
        r"  \centering" + "\n"
        r"  \includegraphics[width=0.6\textwidth]{" + basename + "}\n"
        r"  \caption{" + title + r".}" + "\n"
        r"  \label{fig:energy-comparison}" + "\n"
        r"\end{figure}"
    )


# ── Figure: Convergence Plot ─────────────────────────────────────

def generate_convergence_plot(
    energies: list,
    output_path: str,
    title: str = "SCF Convergence",
):
    """
    Generate SCF convergence plot.

    Args:
        energies: list of total energies at each SCF cycle
        output_path: PNG output
        title: plot title
    """
    if not energies or len(energies) < 2:
        return r"% No convergence data"

    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(10, 4))

    cycles = list(range(1, len(energies) + 1))

    # Energy vs cycle
    ax1.plot(cycles, energies, "o-", color="#2E5090", markersize=4,
             linewidth=1.2)
    ax1.set_xlabel("SCF Cycle")
    ax1.set_ylabel("Total Energy (Hartree)")
    ax1.set_title("Energy Convergence", fontweight="bold")
    ax1.grid(alpha=0.3, linestyle="--")

    # Energy difference
    diffs = [abs(energies[i] - energies[i - 1]) for i in range(1, len(energies))]
    ax2.semilogy(cycles[1:], diffs, "o-", color="#CC3333", markersize=4,
                 linewidth=1.2)
    ax2.set_xlabel("SCF Cycle")
    ax2.set_ylabel(r"$|\Delta E|$ (Hartree)")
    ax2.set_title("Energy Change", fontweight="bold")
    ax2.grid(alpha=0.3, linestyle="--")
    ax2.axhline(y=1e-6, color="gray", linestyle="--", alpha=0.5,
                label=r"$10^{-6}$ threshold")
    ax2.legend(fontsize=8)

    plt.tight_layout()
    fig.savefig(output_path, dpi=300)
    plt.close(fig)

    basename = Path(output_path).stem
    return (
        r"\begin{figure}[htbp]" + "\n"
        r"  \centering" + "\n"
        r"  \begin{subfigure}{0.48\textwidth}" + "\n"
        r"    \centering" + "\n"
        r"    \includegraphics[width=\textwidth]{" + basename + "}\n"
        r"  \end{subfigure}" + "\n"
        r"  \caption{SCF convergence behavior.}" + "\n"
        r"  \label{fig:convergence}" + "\n"
        r"\end{figure}"
    )


# ── Batch Figure Generation ──────────────────────────────────────

def generate_all_figures(results: dict, fig_dir: str) -> list:
    """
    Generate all figures from Orbis results dict.
    Returns list of LaTeX figure code blocks.
    """
    fig_dir = Path(fig_dir)
    fig_dir.mkdir(parents=True, exist_ok=True)
    latex_figs = []

    # 1. Structure figure
    if "optimized_xyz" in results:
        code = generate_structure_figure(
            results["optimized_xyz"],
            str(fig_dir / "fig_structure.png"),
            title="Optimized Molecular Structure"
        )
        if code:
            latex_figs.append(code)

    # 2. Energy level diagram
    if "orbital_energies" in results:
        code = generate_energy_level_diagram(
            results["orbital_energies"],
            str(fig_dir / "fig_energy_levels.png"),
            title="Frontier Molecular Orbital Energies"
        )
        if code:
            latex_figs.append(code)

    # 3. IR spectrum
    if "frequencies" in results and "ir_intensities" in results:
        code = generate_ir_spectrum(
            results["frequencies"],
            results["ir_intensities"],
            str(fig_dir / "fig_ir_spectrum.png"),
            title="Simulated IR Spectrum"
        )
        if code:
            latex_figs.append(code)

    # 4. Energy comparison
    if "energy_comparison" in results:
        code = generate_energy_comparison(
            results["energy_comparison"],
            str(fig_dir / "fig_energy_comparison.png"),
            title="Relative Energies",
            reference_label=results.get("energy_reference")
        )
        if code:
            latex_figs.append(code)

    # 5. Convergence plot
    if "scf_energies" in results:
        code = generate_convergence_plot(
            results["scf_energies"],
            str(fig_dir / "fig_convergence.png"),
            title="SCF Convergence"
        )
        if code:
            latex_figs.append(code)

    return latex_figs
