#!/usr/bin/env python3

from __future__ import annotations

import argparse
import csv
from dataclasses import dataclass
from pathlib import Path

import matplotlib.pyplot as plt


@dataclass
class EnergyProfile:
    index: int
    labels: list[str]
    values: list[float]
    name: str | None = None


def is_float(text: str) -> bool:
    try:
        float(text)
        return True
    except ValueError:
        return False


def is_series_name_row(row: list[str]) -> bool:
    if len(row) % 2 != 0:
        return False

    has_name = False
    for col in range(0, len(row), 2):
        label = row[col].strip()
        value = row[col + 1].strip()

        if label:
            has_name = True
        if value:
            return False

    return has_name


def read_profiles(csv_path: Path) -> list[EnergyProfile]:
    profiles: dict[int, EnergyProfile] = {}
    header_names: dict[int, str] = {}

    with csv_path.open("r", encoding="utf-8", newline="") as f:
        rows = [row for row in csv.reader(f) if row and any(cell.strip() for cell in row)]

    if not rows:
        raise ValueError(f"No valid data found in {csv_path}")

    start_row = 0
    if is_series_name_row(rows[0]):
        for col in range(0, len(rows[0]), 2):
            name = rows[0][col].strip()
            if name:
                header_names[col // 2] = name
        start_row = 1

    for row_idx, row in enumerate(rows[start_row:], start=start_row + 1):
        if len(row) % 2 != 0:
            raise ValueError(
                f"Row {row_idx} has {len(row)} columns. "
                "CSV must be label/value pairs."
            )

        for col in range(0, len(row), 2):
            label = row[col].strip()
            value_text = row[col + 1].strip()

            if not label and not value_text:
                continue
            if not value_text:
                raise ValueError(
                    f"Row {row_idx}, column {col + 2} is empty for a non-empty label."
                )
            if not is_float(value_text):
                raise ValueError(
                    f"Row {row_idx}, column {col + 2} is not a number: {value_text}"
                )

            value = float(value_text)

            idx = col // 2
            profile = profiles.get(idx)
            if profile is None:
                profile = EnergyProfile(
                    index=idx,
                    labels=[],
                    values=[],
                    name=header_names.get(idx),
                )
                profiles[idx] = profile

            profile.labels.append(label or f"Step {len(profile.values) + 1}")
            profile.values.append(value)

    if not profiles:
        raise ValueError(f"No valid data found in {csv_path}")

    return [profiles[k] for k in sorted(profiles)]


def resolve_series_names(profiles: list[EnergyProfile], raw_names: str | None) -> list[str]:
    if not raw_names:
        names: list[str] = []
        for i, profile in enumerate(profiles):
            names.append(profile.name or f"Material {i + 1}")
        return names

    names = [item.strip() for item in raw_names.split(",") if item.strip()]
    if len(names) != len(profiles):
        raise ValueError(
            f"--series-names has {len(names)} names, but CSV contains {len(profiles)} materials."
        )
    return names


def build_xticklabels(profiles: list[EnergyProfile]) -> tuple[list[int], list[str]]:
    max_len = max(len(profile.values) for profile in profiles)

    same_labels = all(
        len(profile.labels) == len(profiles[0].labels) and profile.labels == profiles[0].labels
        for profile in profiles
    )

    x_ticks = list(range(1, max_len + 1))
    if same_labels:
        return x_ticks, profiles[0].labels
    return x_ticks, [f"Step {i}" for i in x_ticks]


def plot_profiles(
    profiles: list[EnergyProfile],
    series_names: list[str],
    output_path: Path,
    dpi: int,
    transparent: bool,
    show: bool,
) -> None:
    # Keep text as text in vector outputs for better compatibility in editors.
    plt.rcParams["svg.fonttype"] = "none"
    plt.rcParams["pdf.fonttype"] = 42

    fig, ax = plt.subplots(figsize=(11, 7), constrained_layout=True)
    # Nature-like scientific palette (high contrast, print-friendly)
    colors = [
        "#E64B35",
        "#4DBBD5",
        "#00A087",
        "#3C5488",
        "#F39B7F",
        "#8491B4",
        "#91D1C2",
        "#DC0000",
        "#7E6148",
        "#B09C85",
    ]
    step_width = 0.72
    title_size = 22
    label_size = 18
    tick_size = 14
    legend_size = 14
    anno_size = 13

    for i, profile in enumerate(profiles):
        color = colors[i % len(colors)]

        for step_idx, y in enumerate(profile.values, start=1):
            x_left = step_idx - step_width / 2
            x_right = step_idx + step_width / 2

            if step_idx == 1:
                ax.hlines(
                    y,
                    x_left,
                    x_right,
                    colors=color,
                    linewidth=2.2,
                    label=series_names[i],
                )
            else:
                ax.hlines(y, x_left, x_right, colors=color, linewidth=2.2)

                prev_y = profile.values[step_idx - 2]
                prev_right = (step_idx - 1) + step_width / 2
                ax.plot(
                    [prev_right, x_left],
                    [prev_y, y],
                    linestyle="--",
                    linewidth=1.4,
                    color=color,
                )

        if len(profile.values) >= 2:
            deltas = [
                profile.values[idx] - profile.values[idx - 1]
                for idx in range(1, len(profile.values))
            ]
            max_rise = max(deltas)
            if max_rise > 0:
                max_rise_pos = deltas.index(max_rise) + 2
                prev_step = max_rise_pos - 1
                x_left = max_rise_pos - step_width / 2
                prev_right = prev_step + step_width / 2

                y_prev = profile.values[prev_step - 1]
                y_curr = profile.values[max_rise_pos - 1]
                x_mid = (prev_right + x_left) / 2
                y_mid = (y_prev + y_curr) / 2

                ax.text(
                    x_mid,
                    y_mid,
                    f"+{max_rise:.2f} eV",
                    color=color,
                    fontsize=anno_size,
                    ha="center",
                    va="center",
                    fontweight="bold",
                    bbox={
                        "facecolor": "none" if transparent else "white",
                        "edgecolor": "none",
                        "alpha": 1.0,
                        "pad": 1.5,
                    },
                )

    x_ticks, x_labels = build_xticklabels(profiles)
    ax.set_xticks(x_ticks)
    ax.set_xticklabels(x_labels, rotation=30, ha="right", fontsize=tick_size)
    ax.set_xlim(0.5, max(x_ticks) + 0.5)
    ax.tick_params(axis="y", labelsize=tick_size)

    ax.set_xlabel("Reaction step", fontsize=label_size)
    ax.set_ylabel("Free energy (eV)", fontsize=label_size)
    ax.set_title("Free-energy staircase", fontsize=title_size, fontweight="bold")
    ax.grid(axis="y", linestyle="--", color="#BFBFBF", linewidth=0.9)
    ax.legend(frameon=False, fontsize=legend_size, loc="upper right")

    output_path.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(output_path, dpi=dpi, transparent=transparent)

    if show:
        plt.show()
    else:
        plt.close(fig)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=(
            "Plot a free-energy staircase from a CSV with repeated label/value pairs: "
            "label_1,value_1,label_2,value_2,..."
        )
    )
    parser.add_argument(
        "-i",
        "--input",
        default="fig_G.csv",
        help="Input CSV path. Default: fig_G.csv",
    )
    parser.add_argument(
        "-o",
        "--output",
        default="free_energy_stairs.png",
        help="Output figure path. Default: free_energy_stairs.png",
    )
    parser.add_argument(
        "--series-names",
        default=None,
        help="Comma-separated legend names. Example: 'Li-system,Na-system'",
    )
    parser.add_argument("--dpi", type=int, default=300, help="Figure DPI. Default: 300")
    parser.add_argument(
        "--transparent",
        action="store_true",
        help="Save figure with transparent background.",
    )
    parser.add_argument(
        "--show",
        action="store_true",
        help="Display the figure window after saving.",
    )
    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()

    input_path = Path(args.input).expanduser().resolve()
    output_path = Path(args.output).expanduser().resolve()

    if not input_path.exists():
        parser.error(f"Input CSV does not exist: {input_path}")

    profiles = read_profiles(input_path)
    series_names = resolve_series_names(profiles, args.series_names)
    plot_profiles(
        profiles,
        series_names,
        output_path,
        dpi=args.dpi,
        transparent=args.transparent,
        show=args.show,
    )

    print(f"Saved free-energy staircase to: {output_path}")
    print(f"Detected materials: {len(profiles)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())