#!/usr/bin/env python3

from __future__ import annotations

import argparse
import csv
import re
import sys
from pathlib import Path


GIBBS_LINE_RE = re.compile(
    r"Final Gibbs free energy\s*:\s*"
    r"([-+]?\d+(?:\.\d+)?)\s+Eh\s+"
    r"\(\s*([-+]?\d+(?:\.\d+)?)\s+eV,\s*"
    r"([-+]?\d+(?:\.\d+)?)\s+kcal/mol,\s*"
    r"([-+]?\d+(?:\.\d+)?)\s+kJ/mol\s*\)"
)


def parse_gibbs_values(summary_path: Path) -> dict[str, str]:
    for line in summary_path.read_text(encoding="utf-8").splitlines():
        match = GIBBS_LINE_RE.search(line)
        if match:
            return {
                "g_eh": match.group(1),
                "g_ev": match.group(2),
                "g_kcal_mol": match.group(3),
                "g_kj_mol": match.group(4),
            }

    raise ValueError(f"No Gibbs free energy line found in {summary_path}")


def collect_rows(root_dir: Path) -> tuple[list[dict[str, str]], list[str]]:
    rows: list[dict[str, str]] = []
    errors: list[str] = []

    for summary_path in sorted(root_dir.rglob("G/G_summary.txt")):
        folder_name = summary_path.parent.parent.name
        try:
            values = parse_gibbs_values(summary_path)
        except ValueError as exc:
            errors.append(str(exc))
            continue

        try:
            relative_path = str(summary_path.relative_to(root_dir))
        except ValueError:
            relative_path = str(summary_path)

        rows.append(
            {
                "folder_name": folder_name,
                **values,
                "summary_path": relative_path,
            }
        )

    rows.sort(key=lambda row: row["folder_name"])
    return rows, errors


def write_csv(rows: list[dict[str, str]], output_path: Path) -> None:
    fieldnames = [
        "folder_name",
        "g_eh",
        "g_ev",
        "g_kcal_mol",
        "g_kj_mol",
        "summary_path",
    ]

    with output_path.open("w", encoding="utf-8", newline="") as csv_file:
        writer = csv.DictWriter(csv_file, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Recursively collect Gibbs free energies from G/G_summary.txt files."
    )
    parser.add_argument(
        "root",
        nargs="?",
        default=".",
        help="Root directory to search recursively. Defaults to the current directory.",
    )
    parser.add_argument(
        "-o",
        "--output",
        default="G.csv",
        help="Output CSV path. Defaults to G.csv in the current directory.",
    )
    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()

    root_dir = Path(args.root).expanduser().resolve()
    output_path = Path(args.output).expanduser().resolve()

    if not root_dir.exists() or not root_dir.is_dir():
        print(f"Root directory does not exist or is not a directory: {root_dir}", file=sys.stderr)
        return 1

    rows, errors = collect_rows(root_dir)
    if not rows:
        print(f"No G/G_summary.txt files were found under {root_dir}", file=sys.stderr)
        return 1

    write_csv(rows, output_path)

    print(f"Wrote {len(rows)} rows to {output_path}")
    if errors:
        print("Skipped files:", file=sys.stderr)
        for error in errors:
            print(f"  - {error}", file=sys.stderr)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())