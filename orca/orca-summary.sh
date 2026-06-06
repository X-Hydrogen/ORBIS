#!/usr/bin/env bash

###############################################################################
#  IQCAP - Intelligent Quantum Chemistry Analysis Platform
#  Module: iqcap-summary  (Concise numerical summary + AI writing prompt pack)
#
#  Version:    0.3.0
#  Author:     Hengyue Xu + AI assistant
#  Date:       2026-03-06
#
#  Description:
#    Read key numerical outputs from an IQCAP project (adsorption energies,
#    thermochemistry, conceptual DFT, charge distribution, Hirshfeld surface
#    contacts, etc.), save the usual compact summary to summary.txt, and also
#    write a summary-ai.txt file containing section-by-section English prompts
#    for drafting a publication-quality Results and Discussion section.
#
#  Usage:
#    # From a project directory (e.g. xhy/C60-Li2S8):
#    #   bash /home/quantum/xhy/iqcap/bin/iqcap-summary.sh
#    #
#    # The script will write:
#    #   summary.txt
#    #   summary-ai.txt
#
###############################################################################

set -euo pipefail

IQCAP_NAME="IQCAP"
IQCAP_MODULE="iqcap-summary"
IQCAP_VERSION="0.3.0"

###############################################################################
# Helpers
###############################################################################

have_file() {
  local path="$1"
  [[ -f "$path" ]]
}

section_header() {
  local title="$1"
  echo
  echo "########################################"
  echo "# $title"
  echo "########################################"
}

ai_section_header() {
  local title="$1"
  echo
  echo "========================================================================"
  echo "$title"
  echo "========================================================================"
}

print_ai_data_block() {
  local emitter="$1"
  echo "----- LOCAL DATA BEGIN -----"
  "$emitter"
  echo "----- LOCAL DATA END -----"
}

###############################################################################
# Project root detection
###############################################################################

PROJECT_ROOT="$PWD"
BASE_NAME="$(basename "$PROJECT_ROOT")"
SUMMARY_REPORT="$PROJECT_ROOT/summary.txt"
AI_REPORT="$PROJECT_ROOT/summary-ai.txt"

###############################################################################
# 0) Computational details
###############################################################################

emit_computational_details_data() {
  local opt_inp="$PROJECT_ROOT/optimization/opt.inp"
  local opt_out="$PROJECT_ROOT/optimization/opt.out"
  local ads_entire_inp="$PROJECT_ROOT/adsorption_energy/entirety/opt.inp"
  local ads_frag1_inp="$PROJECT_ROOT/adsorption_energy/frag1/opt.inp"
  local ads_frag2_inp="$PROJECT_ROOT/adsorption_energy/frag2/opt.inp"
  local freq_inp="$PROJECT_ROOT/G/freq.inp"
  local sp_inp="$PROJECT_ROOT/electronic_structure/chgdiff/chgdiff-work/full/full.inp"
  local fukui_plus_inp="$PROJECT_ROOT/electronic_structure/Fukui/TZVP+1/TZVP+1.inp"
  local fukui_minus_inp="$PROJECT_ROOT/electronic_structure/Fukui/TZVP-1/TZVP-1.inp"
  local multiwfn_out="$PROJECT_ROOT/electronic_structure/CDA/cda.out"
  local vmd_out="$PROJECT_ROOT/electronic_structure/IRI/iri_render.out"

  python3 - \
  "$opt_inp" \
  "$opt_out" \
  "$ads_entire_inp" \
  "$ads_frag1_inp" \
  "$ads_frag2_inp" \
  "$freq_inp" \
  "$sp_inp" \
  "$fukui_plus_inp" \
  "$fukui_minus_inp" \
  "$multiwfn_out" \
  "$vmd_out" <<'PYCOMP'
import re
import sys
from pathlib import Path


(
  opt_inp,
  opt_out,
  ads_entire_inp,
  ads_frag1_inp,
  ads_frag2_inp,
  freq_inp,
  sp_inp,
  fukui_plus_inp,
  fukui_minus_inp,
  multiwfn_out,
  vmd_out,
) = [Path(arg) for arg in sys.argv[1:]]


def read_text(path):
  if not path.is_file():
    return None
  return path.read_text(encoding='utf-8', errors='ignore')


def rel(path):
  try:
    return path.relative_to(Path.cwd()).as_posix()
  except Exception:
    return path.as_posix()


def parse_inp(path):
  text = read_text(path)
  if text is None:
    return None
  info = {
    'path': rel(path),
    'route': None,
    'route_extra': [],
    'maxcore': None,
    'pal': None,
    'charge_mult': None,
    'moinp': None,
    'temp': None,
  }
  for raw_line in text.splitlines():
    line = raw_line.strip()
    if not line:
      continue
    if line.startswith('!'):
      if info['route'] is None:
        info['route'] = line
      else:
        info['route_extra'].append(line)
    elif line.startswith('%maxcore'):
      info['maxcore'] = line
    elif line.startswith('%pal'):
      info['pal'] = line
    elif line.startswith('%moinp'):
      info['moinp'] = line
    elif line.lower().startswith('temp'):
      info['temp'] = line
    elif line.startswith('* xyz'):
      info['charge_mult'] = line
  return info


def parse_orca_output(path):
  text = read_text(path)
  if text is None:
    return {}
  result = {}
  version = re.search(r'Program Version\s+([^\n]+)', text)
  libxc = re.search(r'libXC version:\s*([^\n]+)', text)
  dispersion = re.search(r'Your calculation utilizes the atom-pairwise dispersion correction\s+with the ([^\n]+)', text, re.DOTALL)
  basis = re.search(r'Your calculation utilizes the basis:\s*([^\n]+)', text)
  aux_basis = re.search(r'Your calculation utilizes the auxiliary basis:\s*([^\n]+)', text)
  if version:
    result['version'] = version.group(1).strip()
  if libxc:
    result['libxc'] = libxc.group(1).strip()
  if dispersion:
    result['dispersion'] = ' '.join(dispersion.group(1).split())
  if basis:
    result['basis'] = basis.group(1).strip()
  if aux_basis:
    result['aux_basis'] = aux_basis.group(1).strip()
  return result


def parse_multiwfn(path):
  text = read_text(path)
  if text is None:
    return {}
  result = {}
  version = re.search(r'Version\s+([^\n]+)', text)
  if version:
    result['version'] = version.group(1).strip()
  loaded = re.findall(r'Loaded\s+(.+?)\s+successfully!', text)
  if loaded:
    result['loaded'] = loaded[:3]
  return result


def parse_vmd(path):
  text = read_text(path)
  if text is None:
    return {}
  result = {}
  version = re.search(r'VMD for .*?, version\s+([^\n]+)', text)
  if version:
    result['version'] = version.group(1).strip()
  return result


def format_inp_summary(label, info):
  if info is None:
    return None
  parts = []
  if info['route']:
    parts.append(info['route'])
  parts.extend(info['route_extra'])
  if info['maxcore']:
    parts.append(info['maxcore'])
  if info['pal']:
    parts.append(info['pal'])
  if info['moinp']:
    parts.append(info['moinp'])
  if info['temp']:
    parts.append(info['temp'])
  if info['charge_mult']:
    parts.append(info['charge_mult'])
  return f'    {label}: ' + ' ; '.join(parts)


opt_info = parse_inp(opt_inp)
ads_entire_info = parse_inp(ads_entire_inp)
ads_frag1_info = parse_inp(ads_frag1_inp)
ads_frag2_info = parse_inp(ads_frag2_inp)
freq_info = parse_inp(freq_inp)
sp_info = parse_inp(sp_inp)
fukui_plus_info = parse_inp(fukui_plus_inp)
fukui_minus_info = parse_inp(fukui_minus_inp)
orca_info = parse_orca_output(opt_out)
multiwfn_info = parse_multiwfn(multiwfn_out)
vmd_info = parse_vmd(vmd_out)

if not any([
  opt_info, freq_info, sp_info, fukui_plus_info, fukui_minus_info, orca_info, multiwfn_info, vmd_info
]):
  print('  (No computational-details source files found.)')
  raise SystemExit(0)

print('[Source] optimization/opt.inp')
print('[Source] optimization/opt.out')
if ads_entire_info:
  print('[Source] adsorption_energy/entirety/opt.inp')
if ads_frag1_info:
  print('[Source] adsorption_energy/frag1/opt.inp')
if ads_frag2_info:
  print('[Source] adsorption_energy/frag2/opt.inp')
if freq_info:
  print('[Source] G/freq.inp')
if sp_info:
  print('[Source] electronic_structure/chgdiff/chgdiff-work/full/full.inp')
if fukui_plus_info:
  print('[Source] electronic_structure/Fukui/TZVP+1/TZVP+1.inp')
if fukui_minus_info:
  print('[Source] electronic_structure/Fukui/TZVP-1/TZVP-1.inp')
if multiwfn_info:
  print('[Source] electronic_structure/CDA/cda.out')
if vmd_info:
  print('[Source] electronic_structure/IRI/iri_render.out')

print()
print('  Verified computational setup:')
if orca_info.get('version'):
  print(f"    Main electronic-structure package: ORCA {orca_info['version']}")
if orca_info.get('basis'):
  print(f"    Orbital basis set reported by ORCA: {orca_info['basis']}")
if orca_info.get('aux_basis'):
  print(f"    Auxiliary basis set reported by ORCA: {orca_info['aux_basis']}")
if orca_info.get('dispersion'):
  print(f"    Dispersion model reported by ORCA: atom-pairwise dispersion correction with the {orca_info['dispersion']}")
if orca_info.get('libxc'):
  print(f"    ORCA build information: libXC version {orca_info['libxc']}")

print()
print('  ORCA input details by task:')
for label, info in [
  ('Neutral-singlet geometry optimization of the complex', opt_info),
  ('Adsorption-energy optimization of the full complex', ads_entire_info),
  ('Adsorption-energy optimization of fragment 1', ads_frag1_info),
  ('Adsorption-energy optimization of fragment 2', ads_frag2_info),
  ('Frequency / thermochemistry job', freq_info),
  ('Neutral-singlet single-point job for post-wavefunction analyses', sp_info),
  ('Anionic doublet single-point job for N+1 / Fukui analysis', fukui_plus_info),
  ('Cationic doublet single-point job for N-1 / Fukui analysis', fukui_minus_info),
]:
  line = format_inp_summary(label, info)
  if line:
    print(line)

print()
print('  Analysis and visualization software evidenced by output files:')
if multiwfn_info.get('version'):
  print(f"    Wavefunction-analysis package: Multiwfn {multiwfn_info['version']}")
if multiwfn_info.get('loaded'):
  print('    Example wavefunction files loaded by Multiwfn: ' + '; '.join(multiwfn_info['loaded']))
print('    Multiwfn-driven analyses evidenced in this project: conceptual DFT, Hirshfeld charges, Mayer bond orders, CDA, Hirshfeld surface analysis, electrostatic potential analysis, and NCI/IGMH/IRI weak-interaction analyses')
if vmd_info.get('version'):
  print(f"    Visualization / rendering package: VMD {vmd_info['version']}")
PYCOMP
}


summarize_computational_details() {
  section_header "0. Computational details"
  emit_computational_details_data
}

###############################################################################
# 1) Adsorption / binding energies
###############################################################################

emit_adsorption_data() {
  local summary_txt="$PROJECT_ROOT/adsorption_energy/energy_summary.txt"
  local data_csv="$PROJECT_ROOT/adsorption_energy/energy_data.csv"

  if have_file "$summary_txt"; then
    echo "[Source] adsorption_energy/energy_summary.txt"
    cat "$summary_txt"
  elif have_file "$data_csv"; then
    echo "[Source] adsorption_energy/energy_data.csv"
    cat "$data_csv"
  else
    echo "  (No adsorption_energy summary found.)"
  fi
}

summarize_adsorption() {
  section_header "1. Adsorption / binding energies"
  emit_adsorption_data
}

###############################################################################
# 2) Thermochemistry and Gibbs free energy
###############################################################################

emit_thermo_data() {
  local gsum="$PROJECT_ROOT/G/G_summary.txt"

  if have_file "$gsum"; then
    echo "[Source] G/G_summary.txt"
    cat "$gsum"
  else
    echo "  (No G/G_summary.txt found.)"
  fi
}

summarize_thermo() {
  section_header "2. Thermochemistry and Gibbs free energy"
  emit_thermo_data
}

###############################################################################
# 3) Conceptual DFT + condensed Fukui functions
###############################################################################

emit_cdft_global_data() {
  local cdft="$PROJECT_ROOT/electronic_structure/CDFT/CDFT.txt"
  local fukui_plus="$PROJECT_ROOT/electronic_structure/Fukui/fukui_fplus.cub"
  local fukui_minus="$PROJECT_ROOT/electronic_structure/Fukui/fukui_fminus.cub"
  local fukui_zero="$PROJECT_ROOT/electronic_structure/Fukui/fukui_f0.cub"
  local fukui_dual="$PROJECT_ROOT/electronic_structure/Fukui/fukui_dual.cub"

  if ! have_file "$cdft"; then
    echo "  (No CDFT/CDFT.txt found.)"
    return
  fi

  echo "[Source] electronic_structure/CDFT/CDFT.txt"
  have_file "$fukui_plus" && echo "[Source] electronic_structure/Fukui/fukui_fplus.cub"
  have_file "$fukui_minus" && echo "[Source] electronic_structure/Fukui/fukui_fminus.cub"
  have_file "$fukui_zero" && echo "[Source] electronic_structure/Fukui/fukui_f0.cub"
  have_file "$fukui_dual" && echo "[Source] electronic_structure/Fukui/fukui_dual.cub"
  echo

  python3 - "$cdft" <<'PYCDFT'
import re
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding='utf-8', errors='ignore')
lines = text.splitlines()

global_patterns = [
    r'^\s*E\(N\):',
    r'^\s*E\(N\+1\):',
    r'^\s*E\(N-1\):',
    r'^\s*E_HOMO\(N\):',
    r'^\s*E_HOMO\(N\+1\):',
    r'^\s*E_HOMO\(N-1\):',
    r'^\s*First vertical IP:',
    r'^\s*First vertical EA:',
    r'^\s*Mulliken electronegativity:',
    r'^\s*Chemical potential:',
    r'^\s*Hardness',
    r'^\s*Softness:',
    r'^\s*Softness\^2:',
    r'^\s*Electrophilicity index:',
    r'^\s*Nucleophilicity index:',
]

print('Global descriptors:')
for line in lines:
    if any(re.match(pattern, line) for pattern in global_patterns):
        print(line)

atom_re = re.compile(
    r'^\s*(\d+\([A-Za-z ]+\))\s+'
    r'([-0-9.]+)\s+([-0-9.]+)\s+([-0-9.]+)\s+'
    r'([-0-9.]+)\s+([-0-9.]+)\s+([-0-9.]+)\s+([-0-9.]+)\s*$'
)
rows = []
for line in lines:
    match = atom_re.match(line)
    if not match:
        continue
    atom = re.sub(r'\s+', '', match.group(1))
    rows.append({
        'atom': atom,
        'qN': float(match.group(2)),
        'qNp1': float(match.group(3)),
        'qNm1': float(match.group(4)),
        'fminus': float(match.group(5)),
        'fplus': float(match.group(6)),
        'f0': float(match.group(7)),
        'cdd': float(match.group(8)),
    })

if not rows:
    raise SystemExit(0)

selected = ['1(Li)', '2(Li)', '9(S)', '10(S)']
selected_rows = {row['atom']: row for row in rows}

print()
print('Selected condensed Fukui-function and dual-descriptor data:')
for key in selected:
    row = selected_rows.get(key)
    if row is None:
        continue
    print(
        f"  {key}: q(N)={row['qN']: .4f}, f-={row['fminus']:.4f}, "
        f"f+={row['fplus']:.4f}, f0={row['f0']:.4f}, CDD={row['cdd']:.4f}"
    )

top_fminus = sorted(rows, key=lambda row: row['fminus'], reverse=True)[:4]
top_fplus = sorted(rows, key=lambda row: row['fplus'], reverse=True)[:5]
most_neg_cdd = sorted(rows, key=lambda row: row['cdd'])[:5]
most_pos_cdd = sorted(rows, key=lambda row: row['cdd'], reverse=True)[:5]

def fmt(entries, key):
    return '; '.join(f"{entry['atom']} {entry[key]:.4f}" for entry in entries)

print(f"  Highest f- values: {fmt(top_fminus, 'fminus')}")
print(f"  Highest f+ values: {fmt(top_fplus, 'fplus')}")
print(f"  Most negative CDD values: {fmt(most_neg_cdd, 'cdd')}")
print(f"  Most positive CDD values: {fmt(most_pos_cdd, 'cdd')}")
PYCDFT

  if have_file "$fukui_plus" || have_file "$fukui_minus" || have_file "$fukui_zero" || have_file "$fukui_dual"; then
    echo
    echo "Available Fukui grid files for figure-based interpretation:"
    have_file "$fukui_plus" && echo "  f+ map: electronic_structure/Fukui/fukui_fplus.cub"
    have_file "$fukui_minus" && echo "  f- map: electronic_structure/Fukui/fukui_fminus.cub"
    have_file "$fukui_zero" && echo "  f0 map: electronic_structure/Fukui/fukui_f0.cub"
    have_file "$fukui_dual" && echo "  Dual descriptor map: electronic_structure/Fukui/fukui_dual.cub"
  fi
}

summarize_cdft_global() {
  section_header "3. Conceptual DFT and condensed Fukui reactivity"
  emit_cdft_global_data
}

###############################################################################
# 4) Hirshfeld charges: fragment charges and dipole
###############################################################################

emit_hirshfeld_data() {
  local hfile="$PROJECT_ROOT/electronic_structure/SP/hirshfeld_charges.txt"

  if ! have_file "$hfile"; then
    echo "  (No SP/hirshfeld_charges.txt found.)"
    return
  fi

  echo "[Source] electronic_structure/SP/hirshfeld_charges.txt"
  echo

  awk '
    /^[[:space:]]*Final atomic charges:/ {flag=1; next}
    flag && /^[[:space:]]*Atom/ {
      line = $0
      sub(/^.*\(/, "", line)
      sub(/\).*/, "", line)
      gsub(/[[:space:]]/, "", line)
      elem = line
      charge = $NF + 0.0
      if (elem == "Li") sum_Li += charge
      else if (elem == "S") sum_S += charge
      else if (elem == "C") sum_C += charge
      total += charge
    }
    END {
      printf "  Fragment charges (Hirshfeld, neutral complex):\n"
      printf "    Li2 fragment (2 Li atoms): %+ .6f e\n", sum_Li
      printf "    S8 fragment (8 S atoms):   %+ .6f e\n", sum_S
      printf "    C60 cage (60 C atoms):     %+ .6f e\n", sum_C
      printf "    Overall charge:            %+ .6f e\n", total
    }
  ' "$hfile"

  echo
  grep -m4 "Total dipole moment from atomic charges" "$hfile" || true
}

summarize_hirshfeld() {
  section_header "4. Hirshfeld charges and dipole (neutral complex)"
  emit_hirshfeld_data
}

###############################################################################
# 5) Charge decomposition analysis (CDA) and orbital interaction
###############################################################################

emit_cda_data() {
  local cda_chg="$PROJECT_ROOT/electronic_structure/CDA/fragment_charges.txt"
  local cda_out="$PROJECT_ROOT/electronic_structure/CDA/cda.out"
  local cda_orblist="$PROJECT_ROOT/electronic_structure/CDA/orbitals/_orblist.txt"
  local emitted=0

  if have_file "$cda_chg"; then
    echo "[Source] electronic_structure/CDA/fragment_charges.txt"
    cat "$cda_chg"
  emitted=1
  fi

  if have_file "$cda_out"; then
  [[ "$emitted" -eq 1 ]] && echo
  echo "[Source] electronic_structure/CDA/cda.out"
  echo
  python3 - "$cda_out" "$cda_orblist" <<'PYCDA'
import re
import sys
from pathlib import Path


def parse_energy_blocks(text):
  blocks = {}
  for match in re.finditer(
    r'Energy of molecular orbitals of (the complex|fragment\s+\d+),\s+in eV:\s*\n(.*?)(?=Energy of molecular|-----|\Z)',
    text,
    re.DOTALL,
  ):
    label = ' '.join(match.group(1).strip().lower().replace('the ', '').split())
    values = [float(value) for value in match.group(2).split()]
    blocks[label] = {index + 1: energy for index, energy in enumerate(values)}
  return blocks


def parse_comp_data(text):
  comp_data = {}
  pattern = re.compile(
    r'Occupation number of orbital\s+(\d+) of the complex:\s*([\d.]+)(.*?)(?=Occupation number of orbital|Input the index|\Z)',
    re.DOTALL,
  )
  contrib_pattern = re.compile(
    r'Orbital\s+(\d+)\s+of fragment\s+(\d+).*?Contribution:\s*([\d.]+)\s*%'
  )
  for match in pattern.finditer(text):
    orb_idx = int(match.group(1))
    occupation = float(match.group(2))
    block = match.group(3)
    contributions = []
    for contrib_match in contrib_pattern.finditer(block):
      frag_orb = int(contrib_match.group(1))
      frag_id = contrib_match.group(2)
      percent = float(contrib_match.group(3))
      if percent >= 1.0:
        contributions.append((frag_id, frag_orb, percent))
    if contributions:
      comp_data[orb_idx] = (occupation, contributions)
  return comp_data


def parse_pub_orblist(path, homo, lumo, comp_data):
  show_complex = []
  show_f1 = []
  show_f2 = []

  if path.is_file():
    for raw_line in path.read_text(encoding='utf-8', errors='ignore').splitlines():
      parts = raw_line.split()
      if len(parts) != 2:
        continue
      kind, idx_str = parts
      try:
        idx = int(idx_str)
      except ValueError:
        continue
      if kind == 'complex':
        show_complex.append(idx)
      elif kind == 'frag1':
        show_f1.append(idx)
      elif kind == 'frag2':
        show_f2.append(idx)
  else:
    show_complex = list(range(homo - 2, lumo + 3))
    seen_f1, seen_f2 = set(), set()
    for complex_idx in show_complex:
      if complex_idx not in comp_data:
        continue
      for frag_id, frag_orb, _percent in comp_data[complex_idx][1]:
        if frag_id == '1':
          seen_f1.add(frag_orb)
        elif frag_id == '2':
          seen_f2.add(frag_orb)
    show_f1 = sorted(seen_f1)
    show_f2 = sorted(seen_f2)

  return show_complex, show_f1, show_f2


def format_role(orb_idx, homo, lumo):
  if orb_idx == homo:
    return 'HOMO'
  if orb_idx == homo - 1:
    return 'HOMO-1'
  if orb_idx == homo - 2:
    return 'HOMO-2'
  if orb_idx == lumo:
    return 'LUMO'
  if orb_idx == lumo + 1:
    return 'LUMO+1'
  if orb_idx == lumo + 2:
    return 'LUMO+2'
  return f'MO{orb_idx}'


def format_occ_label(orb_idx, occ_limit):
  return 'occ' if occ_limit and orb_idx <= occ_limit else 'vir'


text = Path(sys.argv[1]).read_text(encoding='utf-8', errors='ignore')
orblist_path = Path(sys.argv[2])

fragment_info = re.findall(
  r'Input \.mwfn/\.fch/\.molden/\.gms file of fragment\s+(\d+).*?'
  r'Alpha electrons:\s+(\d+)\s+Beta electrons:\s+(\d+)\s+Multiplicity:\s+(\d+).*?'
  r'The number of basis functions in this fragment:\s+(\d+).*?'
  r'The number of atoms in this fragment:\s+(\d+)',
  text,
  re.DOTALL,
)

sum_match = re.search(
  r'Sum:\s+([\d.]+)\s+([-\d.]+)\s+([-\d.]+)\s+([-\d.]+)\s+([-\d.]+)',
  text,
)
pl_match = re.search(
  r'PL\(\s*1\) \+ CT\(\s*1->\s*2\) =\s*([-\d.]+)\s+PL\(\s*1\) \+ CT\(\s*2->\s*1\) =\s*([-\d.]+)',
  text,
)
pl2_match = re.search(
  r'PL\(\s*2\) \+ CT\(\s*1->\s*2\) =\s*([-\d.]+)\s+PL\(\s*2\) \+ CT\(\s*2->\s*1\) =\s*([-\d.]+)',
  text,
)
net_match = re.search(
  r'The net electrons obtained by frag\.\s*2 = CT\(\s*1->\s*2\) - CT\(\s*2->\s*1\) =\s*([-\d.]+)',
  text,
)

if not sum_match:
  print('  (CDA result block not found in cda.out)')
  raise SystemExit(0)

total_electrons = int(float(sum_match.group(1)))
homo = total_electrons // 2
lumo = homo + 1

energy_blocks = parse_energy_blocks(text)
complex_energies = energy_blocks.get('complex', {})
frag1_energies = energy_blocks.get('fragment 1', {})
frag2_energies = energy_blocks.get('fragment 2', {})
comp_data = parse_comp_data(text)
show_complex, show_f1, show_f2 = parse_pub_orblist(orblist_path, homo, lumo, comp_data)

frag1_occ = int(fragment_info[0][1]) if len(fragment_info) >= 1 else 0
frag2_occ = int(fragment_info[1][1]) if len(fragment_info) >= 2 else 0

print('  CDA/ECDA summary:')
if len(fragment_info) >= 2:
  print(
    f'    Fragment 1: atoms={fragment_info[0][5]}, alpha/beta electrons={fragment_info[0][1]}/{fragment_info[0][2]}, '
    f'basis functions={fragment_info[0][4]}'
  )
  print(
    f'    Fragment 2: atoms={fragment_info[1][5]}, alpha/beta electrons={fragment_info[1][1]}/{fragment_info[1][2]}, '
    f'basis functions={fragment_info[1][4]}'
  )
print(f'    Sum(d) [frag1 -> frag2 donation]       = {sum_match.group(2)} e')
print(f'    Sum(b) [frag2 -> frag1 back-donation]  = {sum_match.group(3)} e')
print(f'    Sum(d-b)                               = {sum_match.group(4)} e')
print(f'    Sum(r) [repulsive polarization]        = {sum_match.group(5)} e')
if pl_match:
  print(f'    PL(1) + CT(1->2)                       = {pl_match.group(1)}')
  print(f'    PL(1) + CT(2->1)                       = {pl_match.group(2)}')
if pl2_match:
  print(f'    PL(2) + CT(1->2)                       = {pl2_match.group(1)}')
  print(f'    PL(2) + CT(2->1)                       = {pl2_match.group(2)}')
if net_match:
  print(f'    Net electrons obtained by fragment 2   = {net_match.group(1)} e')

print()
print('  Orbital-interaction window used for orbinteract-pub.png:')
complex_line = []
for complex_idx in show_complex:
  energy = complex_energies.get(complex_idx)
  role = format_role(complex_idx, homo, lumo)
  occ_label = 'occ' if complex_idx <= homo else 'vir'
  if energy is None:
    complex_line.append(f'{complex_idx} ({role}, {occ_label})')
  else:
    complex_line.append(f'{complex_idx} ({role}, {occ_label}, {energy:.4f} eV)')
print('    Complex orbitals: ' + ', '.join(complex_line))

if show_f1:
  frag1_line = []
  for orb_idx in show_f1:
    energy = frag1_energies.get(orb_idx)
    occ_label = format_occ_label(orb_idx, frag1_occ)
    if energy is None:
      frag1_line.append(f'{orb_idx} ({occ_label})')
    else:
      frag1_line.append(f'{orb_idx} ({occ_label}, {energy:.4f} eV)')
  print('    Fragment 1 orbitals: ' + ', '.join(frag1_line))

if show_f2:
  frag2_line = []
  for orb_idx in show_f2:
    energy = frag2_energies.get(orb_idx)
    occ_label = format_occ_label(orb_idx, frag2_occ)
    if energy is None:
      frag2_line.append(f'{orb_idx} ({occ_label})')
    else:
      frag2_line.append(f'{orb_idx} ({occ_label}, {energy:.4f} eV)')
  print('    Fragment 2 orbitals: ' + ', '.join(frag2_line))

print()
print('  Orbital compositions for the publication interaction diagram:')
for complex_idx in show_complex:
  if complex_idx not in comp_data:
    continue
  occupation, contributions = comp_data[complex_idx]
  role = format_role(complex_idx, homo, lumo)
  complex_energy = complex_energies.get(complex_idx)
  complex_desc = f'Complex orbital {complex_idx} ({role}, occ={occupation:.8f}'
  if complex_energy is not None:
    complex_desc += f', {complex_energy:.4f} eV'
  complex_desc += ')'

  contrib_parts = []
  for frag_id, frag_orb, percent in contributions:
    frag_energies = frag1_energies if frag_id == '1' else frag2_energies
    frag_occ = frag1_occ if frag_id == '1' else frag2_occ
    frag_energy = frag_energies.get(frag_orb)
    occ_label = format_occ_label(frag_orb, frag_occ)
    part = f'frag{frag_id} orbital {frag_orb} ({occ_label}, {percent:.2f}%'
    if frag_energy is not None:
      part += f', {frag_energy:.4f} eV'
    part += ')'
    contrib_parts.append(part)

  print(f'    {complex_desc}: ' + '; '.join(contrib_parts))
PYCDA
  emitted=1
  fi

  if [[ "$emitted" -eq 0 ]]; then
    echo "  (No CDA summary files found.)"
  fi
}

summarize_cda() {
  section_header "5. Charge decomposition analysis (CDA) and orbital interaction"
  emit_cda_data
}

###############################################################################
# 6) Frontier orbitals + HOMO/LUMO assets
###############################################################################

emit_frontier_data() {
  local cdft="$PROJECT_ROOT/electronic_structure/CDFT/CDFT.txt"
  local cda_out="$PROJECT_ROOT/electronic_structure/CDA/cda.out"
  local homo_cube="$PROJECT_ROOT/electronic_structure/homo_lumo/HOMO.cub"
  local lumo_cube="$PROJECT_ROOT/electronic_structure/homo_lumo/LUMO.cub"
  local homo_tcl="$PROJECT_ROOT/electronic_structure/homo_lumo/render_homo_3view.tcl"
  local lumo_tcl="$PROJECT_ROOT/electronic_structure/homo_lumo/render_lumo_3view.tcl"

  if ! have_file "$cdft" && ! have_file "$cda_out"; then
    echo "  (No CDFT/CDFT.txt or CDA/cda.out found; skipping frontier-orbital summary.)"
    return
  fi

  have_file "$cdft" && echo "[Source] electronic_structure/CDFT/CDFT.txt"
  have_file "$cda_out" && echo "[Source] electronic_structure/CDA/cda.out"
  have_file "$homo_cube" && echo "[Source] electronic_structure/homo_lumo/HOMO.cub"
  have_file "$lumo_cube" && echo "[Source] electronic_structure/homo_lumo/LUMO.cub"
  echo

  python3 - "$cdft" "$cda_out" "$homo_tcl" "$lumo_tcl" <<'PYFRONT'
import re
import sys
from pathlib import Path

cdft_path, cda_path, homo_tcl_path, lumo_tcl_path = [Path(arg) for arg in sys.argv[1:]]

def read_text(path):
    if not path.is_file():
        return ''
    return path.read_text(encoding='utf-8', errors='ignore')

cdft_text = read_text(cdft_path)
cda_text = read_text(cda_path)
homo_tcl = read_text(homo_tcl_path)
lumo_tcl = read_text(lumo_tcl_path)

def parse_energy_blocks(text):
  blocks = {}
  for match in re.finditer(
    r'Energy of molecular orbitals of (the complex|fragment\s+\d+),\s+in eV:\s*\n(.*?)(?=Energy of molecular|-----|\Z)',
    text,
    re.DOTALL,
  ):
    label = ' '.join(match.group(1).strip().lower().replace('the ', '').split())
    try:
      values = [float(value) for value in match.group(2).split()]
    except ValueError:
      continue
    blocks[label] = {index + 1: energy for index, energy in enumerate(values)}
  return blocks

energies = {}
blocks = parse_energy_blocks(cda_text)
complex_energies = blocks.get('complex', {})

electron_match = re.search(r'Total/Alpha/Beta electrons:\s*([-.0-9]+)\s+([-.0-9]+)\s+([-.0-9]+)', cda_text)
if electron_match and complex_energies:
  alpha_electrons = int(float(electron_match.group(2)))
  homo_idx = alpha_electrons
  lumo_idx = homo_idx + 1
  index_map = {
    'HOMO-2': homo_idx - 2,
    'HOMO-1': homo_idx - 1,
    'HOMO': homo_idx,
    'LUMO': lumo_idx,
    'LUMO+1': lumo_idx + 1,
    'LUMO+2': lumo_idx + 2,
  }
  for role, idx in index_map.items():
    if idx in complex_energies:
      energies[role] = complex_energies[idx]

if not energies:
  homoline = re.search(r'^\s*E_HOMO\(N\):\s+[-.0-9]+ Hartree,\s+([-.0-9]+) eV', cdft_text, re.MULTILINE)
  if homoline:
    energies['HOMO'] = float(homoline.group(1))

if energies:
    print('Frontier orbital energies from the CDA publication window:')
    ordered_roles = ['HOMO-2', 'HOMO-1', 'HOMO', 'LUMO', 'LUMO+1', 'LUMO+2']
    for role in ordered_roles:
        if role in energies:
            print(f'  {role}: {energies[role]: .4f} eV')
    if 'HOMO' in energies and 'LUMO' in energies:
        print(f"  Orbital HOMO-LUMO gap: {energies['LUMO'] - energies['HOMO']:.4f} eV")

hardness_match = re.search(r'^\s*Hardness \(=fundamental gap\):\s+[-\d.]+ Hartree,\s+([-\d.]+) eV', cdft_text, re.MULTILINE)
if hardness_match:
    print(f"  Fundamental gap from CDFT: {float(hardness_match.group(1)):.4f} eV")

comp_lines = []
for role in ['HOMO', 'LUMO']:
    pattern = rf'Complex orbital \d+ \({role}, occ=[^\n]+\):\s+(.+)$'
    match = re.search(pattern, cda_text, re.MULTILINE)
    if match:
        comp_lines.append(f'  {role} composition: {match.group(1).strip()}')
if comp_lines:
    print()
    print('Orbital-composition evidence:')
    for line in comp_lines:
        print(line)

iso_values = []
for text in [homo_tcl, lumo_tcl]:
    for match in re.findall(r'mol representation Isosurface\s+([-\d.]+)', text):
        try:
            iso_values.append(float(match))
        except ValueError:
            pass
if iso_values:
    print()
    print('HOMO/LUMO rendering settings:')
    unique = sorted(set(abs(value) for value in iso_values if value != 0))
    if unique:
        print('  Orbital isovalues used for rendering: ' + ', '.join(f'{value:.2f}' for value in unique))
PYFRONT

  if have_file "$homo_cube" || have_file "$lumo_cube"; then
    echo
    echo "HOMO/LUMO cube files are available for direct figure-based spatial interpretation."
  fi
}

summarize_frontier() {
  section_header "6. Frontier orbitals and HOMO/LUMO assets"
  emit_frontier_data
}

###############################################################################
# 7) Hirshfeld surface contacts (HS)
###############################################################################

emit_hs_contacts_data() {
  local hs_contacts="$PROJECT_ROOT/electronic_structure/HS/contact_areas.txt"
  local hs_dide="$PROJECT_ROOT/electronic_structure/HS/di_de.txt"

  if have_file "$hs_contacts"; then
    echo "[Source] electronic_structure/HS/contact_areas.txt"
    cat "$hs_contacts"
  else
    echo "  (No HS/contact_areas.txt found.)"
    return
  fi

  if have_file "$hs_dide"; then
    echo
    echo "[Source] electronic_structure/HS/di_de.txt"
    echo
    python3 - "$hs_dide" <<'PYHS'
import math
import sys
from collections import Counter
from pathlib import Path

points = []
for line in Path(sys.argv[1]).read_text(encoding='utf-8', errors='ignore').splitlines():
    parts = line.split()
    if len(parts) != 2:
        continue
    try:
        di = float(parts[0])
        de = float(parts[1])
    except ValueError:
        continue
    points.append((di, de))

if not points:
    raise SystemExit(0)

points.sort()
di_vals = sorted(di for di, _ in points)
de_vals = sorted(de for _, de in points)

def percentile(values, frac):
    idx = max(0, min(len(values) - 1, int(frac * (len(values) - 1))))
    return values[idx]

hist = Counter((round(di / 0.05) * 0.05, round(de / 0.05) * 0.05) for di, de in points)
peak_bin, peak_count = hist.most_common(1)[0]

print('Fingerprint statistics from di/de point cloud:')
print(f'  Number of fingerprint points: {len(points)}')
print(f'  di range: {min(di_vals):.3f} to {max(di_vals):.3f} Angstrom')
print(f'  de range: {min(de_vals):.3f} to {max(de_vals):.3f} Angstrom')
print(f'  Median di/de: {percentile(di_vals, 0.5):.3f} / {percentile(de_vals, 0.5):.3f} Angstrom')
print(f'  5th-95th percentile di: {percentile(di_vals, 0.05):.3f} to {percentile(di_vals, 0.95):.3f} Angstrom')
print(f'  5th-95th percentile de: {percentile(de_vals, 0.05):.3f} to {percentile(de_vals, 0.95):.3f} Angstrom')
print(f'  Highest-density 0.05 Angstrom bin center: di ~ {peak_bin[0]:.2f}, de ~ {peak_bin[1]:.2f} (count={peak_count})')
PYHS
  fi
}

summarize_hs_contacts() {
  section_header "7. Hirshfeld surface contacts (Li-host / S-host)"
  emit_hs_contacts_data
}

###############################################################################
# 8) Mayer bond orders (selected header)
###############################################################################

emit_mayer_bondorders_data() {
  local mbo="$PROJECT_ROOT/electronic_structure/SP/mayer_bondorder.txt"

  if ! have_file "$mbo"; then
    echo "  (No SP/mayer_bondorder.txt found.)"
    return
  fi

  echo "[Source] electronic_structure/SP/mayer_bondorder.txt"
  echo
  awk '
    /Bond orders with absolute value/ {flag=1; print; next}
    flag && NR_out < 50 { print; NR_out++ }
  ' "$mbo" || true
}

summarize_mayer_bondorders() {
  section_header "8. Mayer bond order analysis (first ~40 strongest bonds)"
  emit_mayer_bondorders_data
}

###############################################################################
# 9) Electrostatic potential (ESP) & dipole from density (optional)
###############################################################################

emit_esp_data() {
  local outesp="$PROJECT_ROOT/electronic_structure/SP/outesp.txt"
  local esp_tcl="$PROJECT_ROOT/electronic_structure/esp/render_esp.tcl"
  local hfile="$PROJECT_ROOT/electronic_structure/SP/hirshfeld_charges.txt"
  local cdft="$PROJECT_ROOT/electronic_structure/CDFT/CDFT.txt"

  if ! have_file "$outesp"; then
    echo "  (No SP/outesp.txt found.)"
    return
  fi

  echo "[Source] electronic_structure/SP/outesp.txt"
  have_file "$esp_tcl" && echo "[Source] electronic_structure/esp/render_esp.tcl"
  have_file "$hfile" && echo "[Source] electronic_structure/SP/hirshfeld_charges.txt"
  have_file "$cdft" && echo "[Source] electronic_structure/CDFT/CDFT.txt"
  echo
  awk '
    /The minimum is/ && flag == 0 {
      flag=1
      limit=8
    }
    flag && count < limit {
      print
      count++
    }
  ' "$outesp" || true

  if have_file "$esp_tcl" || have_file "$hfile" || have_file "$cdft"; then
    echo
    python3 - "$esp_tcl" "$hfile" "$cdft" <<'PYESP'
import re
import sys
from pathlib import Path

esp_tcl_path, hfile_path, cdft_path = [Path(arg) for arg in sys.argv[1:]]

def read_text(path):
    if not path.is_file():
        return ''
    return path.read_text(encoding='utf-8', errors='ignore')

tcl_text = read_text(esp_tcl_path)
htext = read_text(hfile_path)
ctext = read_text(cdft_path)

if tcl_text:
    iso_match = re.search(r'mol representation Isosurface\s+([-.0-9]+)', tcl_text)
    scale_match = re.search(r'mol scaleminmax top \d+\s+([-.0-9]+)\s+([-.0-9]+)', tcl_text)
    print('ESP mapping settings:')
    if iso_match:
        print(f"  Density isosurface used for ESP mapping: {float(iso_match.group(1)):.3f} a.u.")
    if scale_match:
        print(f"  Visualization color scale: {float(scale_match.group(1)):.2f} to {float(scale_match.group(2)):.2f} a.u.")

if htext:
    frag = {}
    for label, pattern in {
        'Li2 fragment': r'Li2 fragment \(2 Li atoms\):\s*([+\- ]*[0-9.]+) e',
        'S8 fragment': r'S8 fragment \(8 S atoms\):\s*([+\- ]*[0-9.]+) e',
        'C60 cage': r'C60 cage \(60 C atoms\):\s*([+\- ]*[0-9.]+) e',
    }.items():
        match = re.search(pattern, htext)
        if match:
            frag[label] = float(match.group(1).replace(' ', ''))
    if frag:
        print()
        print('Fragment-charge context for electrostatic interpretation:')
        for label in ['Li2 fragment', 'S8 fragment', 'C60 cage']:
            if label in frag:
                print(f'  {label}: {frag[label]:+0.6f} e')

if ctext:
    atom_re = re.compile(
        r'^\s*(\d+\([A-Za-z ]+\))\s+'
        r'([-0-9.]+)\s+([-0-9.]+)\s+([-0-9.]+)\s+'
        r'([-0-9.]+)\s+([-0-9.]+)\s+([-0-9.]+)\s+([-0-9.]+)\s*$',
        re.MULTILINE,
    )
    rows = {}
    for match in atom_re.finditer(ctext):
        atom = re.sub(r'\s+', '', match.group(1))
        rows[atom] = float(match.group(2))
    selected = [key for key in ['1(Li)', '2(Li)', '9(S)', '10(S)'] if key in rows]
    if selected:
        print()
        print('Selected atomic charges from the condensed-Fukui table:')
        for key in selected:
            print(f'  {key}: q(N)={rows[key]:+0.4f} e')
PYESP
  fi
}

summarize_esp() {
  section_header "9. Electrostatic potential (ESP) summary (neutral complex)"
  emit_esp_data
}

###############################################################################
# 10) NCI / IGMH / IRI weak-interaction metadata
###############################################################################

emit_weak_interactions_data() {
  local nci="$PROJECT_ROOT/electronic_structure/NCI/out_nci.txt"
  local igmh_out="$PROJECT_ROOT/electronic_structure/IGMH/igmh.out"
  local igmh_render="$PROJECT_ROOT/electronic_structure/IGMH/igmh_render.out"
  local iri_out="$PROJECT_ROOT/electronic_structure/IRI/iri.out"
  local iri_render="$PROJECT_ROOT/electronic_structure/IRI/iri_render.out"

  have_file "$nci" && echo "[Source] electronic_structure/NCI/out_nci.txt"
  have_file "$igmh_out" && echo "[Source] electronic_structure/IGMH/igmh.out"
  have_file "$igmh_render" && echo "[Source] electronic_structure/IGMH/igmh_render.out"
  have_file "$iri_out" && echo "[Source] electronic_structure/IRI/iri.out"
  have_file "$iri_render" && echo "[Source] electronic_structure/IRI/iri_render.out"

  if ! have_file "$nci" && ! have_file "$igmh_out" && ! have_file "$iri_out"; then
  echo "  (No NCI/IGMH/IRI outputs found.)"
  return
  fi

  echo
  python3 - "$nci" "$igmh_out" "$igmh_render" "$iri_out" "$iri_render" <<'PYWEAK'
import re
import sys
from pathlib import Path

nci_path, igmh_path, igmh_render_path, iri_path, iri_render_path = [Path(arg) for arg in sys.argv[1:]]

def read_text(path):
  if not path.is_file():
    return ''
  return path.read_text(encoding='utf-8', errors='ignore')

nci = read_text(nci_path)
igmh = read_text(igmh_path)
igmh_render = read_text(igmh_render_path)
iri = read_text(iri_path)
iri_render = read_text(iri_render_path)

if nci:
  grid_match = re.search(r'Number of points in X,Y,Z is\s+(\d+)\s+(\d+)\s+(\d+)\s+Total:\s+(\d+)', nci)
  spacing_match = re.search(r'Grid spacing in X,Y,Z is\s+([-.0-9Ee+]+)\s+([-.0-9Ee+]+)\s+([-.0-9Ee+]+) Bohr', nci)
  x_match = re.search(r'Change range of X-axis of scatter graph, current:\s*([-.0-9Ee+]+) to\s*([-.0-9Ee+]+)', nci)
  y_match = re.search(r'Change range of Y-axis of scatter graph, current:\s*([-.0-9Ee+]+) to\s*([-.0-9Ee+]+)', nci)
  print('NCI / RDG analysis:')
  if grid_match:
    print(f'  Grid: {grid_match.group(1)} x {grid_match.group(2)} x {grid_match.group(3)} points ({grid_match.group(4)} total)')
  if spacing_match:
    print(f'  Grid spacing: {float(spacing_match.group(1)):.6f} Bohr')
  if x_match:
    print(f'  Scatter-plot X range for sign(lambda2)rho: {x_match.group(1)} to {x_match.group(2)} a.u.')
  if y_match:
    print(f'  Scatter-plot Y range for RDG: {y_match.group(1)} to {y_match.group(2)}')
  if 'Outputting output.txt' in nci:
    print('  RDG scatter points and grid/cube data were explicitly exported.')

if igmh:
  grid_match = re.search(r'Number of points in X,Y,Z is\s+(\d+)\s+(\d+)\s+(\d+)\s+Total:\s+(\d+)', igmh)
  total_match = re.search(r'Integral of delta-g over whole space:\s*([-.0-9Ee+]+) a\.u\.', igmh)
  inter_match = re.search(r'Integral of delta-g_inter over whole space:\s*([-.0-9Ee+]+) a\.u\.', igmh)
  intra_match = re.search(r'Integral of delta-g_intra over whole space:\s*([-.0-9Ee+]+) a\.u\.', igmh)
  render_inter = re.search(r'Added volume data, name=dg_inter\.cub.*?Min: ([^.\n ]+)  Max: ([^.\n ]+)', igmh_render, re.DOTALL)
  render_sl2r = re.search(r'Added volume data, name=sl2r\.cub.*?Min: ([^.\n ]+)  Max: ([^.\n ]+)', igmh_render, re.DOTALL)
  print()
  print('IGMH analysis:')
  if 'Input atom indices for fragment  1' in igmh and 'Input atom indices for fragment  2' in igmh:
    print('  Two fragments were defined for interfragment analysis.')
  if grid_match:
    print(f'  Grid: {grid_match.group(1)} x {grid_match.group(2)} x {grid_match.group(3)} points ({grid_match.group(4)} total)')
  if total_match:
    print(f'  Integral of delta-g over whole space: {float(total_match.group(1)):.6f} a.u.')
  if inter_match:
    print(f'  Integral of delta-g_inter over whole space: {float(inter_match.group(1)):.6f} a.u.')
  if intra_match:
    print(f'  Integral of delta-g_intra over whole space: {float(intra_match.group(1)):.6f} a.u.')
  if render_inter:
    print(f'  VMD render log for dg_inter.cub: min {render_inter.group(1)}, max {render_inter.group(2)}')
  if render_sl2r:
    print(f'  VMD render log for sign(lambda2)rho cube: min {render_sl2r.group(1)}, max {render_sl2r.group(2)}')

if iri:
  grid_match = re.search(r'Number of points in X,Y,Z is\s+(\d+)\s+(\d+)\s+(\d+)\s+Total:\s+(\d+)', iri)
  x_match = re.search(r'Change range of X-axis of scatter graph, current:\s*([-.0-9Ee+]+) to\s*([-.0-9Ee+]+)', iri)
  y_match = re.search(r'Change range of Y-axis of scatter graph, current:\s*([-.0-9Ee+]+) to\s*([-.0-9Ee+]+)', iri)
  render_func2 = re.search(r'Added volume data, name=func2\.cub.*?Min: ([^.\n ]+)  Max: ([^.\n ]+)', iri_render, re.DOTALL)
  render_func1 = re.search(r'Added volume data, name=func1\.cub.*?Min: ([^.\n ]+)  Max: ([^.\n ]+)', iri_render, re.DOTALL)
  print()
  print('IRI analysis:')
  if grid_match:
    print(f'  Grid: {grid_match.group(1)} x {grid_match.group(2)} x {grid_match.group(3)} points ({grid_match.group(4)} total)')
  if x_match:
    print(f'  Scatter-plot X range for sign(lambda2)rho: {x_match.group(1)} to {x_match.group(2)} a.u.')
  if y_match:
    print(f'  Scatter-plot Y range for IRI: {y_match.group(1)} to {y_match.group(2)}')
  if render_func2:
    print(f'  VMD render log for the IRI cube (func2.cub): min {render_func2.group(1)}, max {render_func2.group(2)}')
  if render_func1:
    print(f'  VMD render log for the sign(lambda2)rho cube (func1.cub): min {render_func1.group(1)}, max {render_func1.group(2)}')
  if 'Outputting output.txt' in iri:
    print('  Scatter points and grid/cube data were explicitly exported.')
PYWEAK
}

summarize_weak_interactions() {
  section_header "10. Weak interaction analyses (NCI / IGMH / IRI)"
  emit_weak_interactions_data
}

###############################################################################
# Summary output
###############################################################################

emit_summary_report() {
  [[ -d "$PROJECT_ROOT/electronic_structure" ]] || \
    echo "[$IQCAP_MODULE] WARNING: electronic_structure/ not found under $PROJECT_ROOT; continuing anyway."

  echo "========================================"
  echo " $IQCAP_NAME v$IQCAP_VERSION -- $IQCAP_MODULE"
  echo " Project: $BASE_NAME"
  echo " Root:    $PROJECT_ROOT"
  echo "========================================"

  summarize_computational_details
  summarize_adsorption
  summarize_thermo
  summarize_cdft_global
  summarize_hirshfeld
  summarize_cda
  summarize_frontier
  summarize_hs_contacts
  summarize_mayer_bondorders
  summarize_esp
  summarize_weak_interactions

  echo
  echo "[$IQCAP_MODULE] Summary completed."
}

###############################################################################
# AI prompt package output
###############################################################################

emit_ai_report() {
  echo "========================================"
  echo " $IQCAP_NAME v$IQCAP_VERSION -- $IQCAP_MODULE AI prompt package"
  echo " Project: $BASE_NAME"
  echo " Root:    $PROJECT_ROOT"
  echo "========================================"
  echo
  echo "HOW TO USE"
  echo "1. Paste this entire file into ChatGPT or another LLM."
  echo "2. For a one-shot draft, use the MASTER INTEGRATED PROMPT together with all LOCAL DATA blocks already embedded below."
  echo "3. For tighter control, ask the model to answer each SECTION PROMPT separately, then run the FINAL SYNTHESIS PROMPT."
  echo "4. When a discussion would normally rely on a plotted orbital, surface, map, or interaction diagram, write in journal style and cite placeholder figure labels such as Figure X or Figure X(a-c); I will replace them later."
  echo "5. Use SECTION 0 separately when you want the model to draft a publication-quality Computational Details section."
  echo
  echo "MASTER INTEGRATED PROMPT"
  cat <<EOF
You are a native-English senior professor of theoretical chemistry, computational chemistry, and physical chemistry at MIT, writing for a high-impact peer-reviewed journal.

Task:
- Write a publication-quality Results and Discussion section for the system "$BASE_NAME".
- Use only the numerical and qualitative evidence contained in the LOCAL DATA blocks below.
- Organize the discussion into coherent scientific subsections, for example: Adsorption Energetics; Thermodynamic Effects; Charge Transfer and Electronic Structure; Bonding Characteristics; Electrostatic and Surface Features; Noncovalent Interaction Analysis.

Writing requirements:
- Write in polished, concise, publication-ready American English.
- Sound like an expert human author, not an AI assistant.
- Interpret trends physically and chemically rather than merely restating raw numbers.
- When values are present, report them exactly as given.
- When the evidence is qualitative or incomplete, state the trend carefully without inventing missing numbers.
- Explicitly connect energetics, charge transfer, frontier orbitals, electrostatics, bond-order data, and weak-interaction analyses when the data support such links.
- Write in a paper-like "figure-guided" style whenever appropriate: if a result would normally be discussed together with a visual map, surface, orbital plot, contact plot, or interaction isosurface, explicitly refer to it as Figure X, Figure X(a), Figure X(b), etc.
- Use Figure X placeholders naturally and sparingly, only where a journal article would normally cite a figure.
- If no actual visual evidence is provided in the local data, keep the figure reference generic and avoid inventing fine spatial details.
- Keep the tone rigorous, selective, and non-hyperbolic.

Do not:
- fabricate values, mechanisms, orbital localizations, or structure-property claims not supported by the local data;
- mention that the text was generated by AI;
- include methods unless they are strictly necessary for interpreting the results.
EOF

  ai_section_header "SECTION 0. Computational Details"
  print_ai_data_block emit_computational_details_data
  echo
  echo "SECTION PROMPT"
  cat <<EOF
Write the section "Computational Details" for "$BASE_NAME".

Requirements:
- Use only the LOCAL DATA block above.
- Report software packages and versions exactly as provided when they are present.
- Describe the verified ORCA setup for geometry optimization, thermochemistry/frequency analysis, neutral single-point calculations for wavefunction analysis, and charged-state single-point calculations for N+1/N-1 or Fukui analyses.
- Include the functional, dispersion treatment, basis set, auxiliary basis, RIJCOSX usage, tightSCF/opt/freq keywords, memory and parallel settings, and charge/multiplicity information only when explicitly present.
- If post-processing software such as Multiwfn or visualization software such as VMD is present, describe their role conservatively and accurately.
- If no solvation model or additional numerical settings are shown, do not invent them; state the setup only at the level supported by the extracted data.
- Write in polished, publication-ready American English suitable for a high-impact chemistry journal.
EOF

  ai_section_header "SECTION 1. Adsorption / binding energies"
  print_ai_data_block emit_adsorption_data
  echo
  echo "SECTION PROMPT"
  cat <<EOF
Write the subsection "Adsorption Energetics" for "$BASE_NAME".

Requirements:
- Use only the LOCAL DATA block above.
- Report adsorption or binding energies exactly as listed.
- Explain what the sign and magnitude imply for host-guest stabilization, adsorption strength, and practical affinity.
- If multiple configurations or states are present, compare them logically and identify the most favorable case without exaggeration.
- Connect the energetic trend to later electronic-structure discussion, but do not pre-emptively claim mechanisms that are not yet supported.
- If the adsorption geometry would normally be shown in a paper, you may refer to it generically as Figure X.
- Keep the prose suitable for an ACS-style Results and Discussion section.
EOF

  ai_section_header "SECTION 2. Thermochemistry and Gibbs free energy"
  print_ai_data_block emit_thermo_data
  echo
  echo "SECTION PROMPT"
  cat <<EOF
Write the subsection "Thermodynamic Effects" for "$BASE_NAME".

Requirements:
- Use only the LOCAL DATA block above.
- Interpret Gibbs free energy, enthalpic, or entropic information strictly from the reported values.
- State whether the process remains favorable after thermal corrections, and explain what this implies for realistic operating conditions.
- If the free-energy trend differs from the electronic adsorption energy, discuss the difference carefully and mechanistically only at a defensible level.
- Avoid overgeneralization beyond the reported thermochemical quantities.
EOF

  ai_section_header "SECTION 3. Conceptual DFT and Fukui reactivity"
  print_ai_data_block emit_cdft_global_data
  echo
  echo "SECTION PROMPT"
  cat <<EOF
Write the subsection "Conceptual DFT and Fukui Reactivity" for "$BASE_NAME".

Requirements:
- Use only the LOCAL DATA block above.
- Combine the global conceptual-DFT descriptors with the condensed Fukui functions and condensed dual descriptor into one coherent subsection.
- Interpret the HOMO energy, vertical IP, vertical EA, electronegativity, chemical potential, hardness, softness, electrophilicity index, and nucleophilicity index only if they are present.
- Use f-, f+, f0, and the condensed dual descriptor to identify likely local susceptibility to electrophilic, nucleophilic, and radical attack.
- Be explicit that f+ corresponds to sites susceptible to nucleophilic attack, whereas f- corresponds to sites susceptible to electrophilic attack.
- Distinguish clearly between firm atom-resolved observations and broader qualitative inference.
- If Fukui maps would normally accompany the discussion, cite them as Figure X or Figure X(a-d).
- Keep the discussion compact, technical, and publication-ready.
EOF

  ai_section_header "SECTION 4. Hirshfeld charges and dipole"
  print_ai_data_block emit_hirshfeld_data
  echo
  echo "SECTION PROMPT"
  cat <<EOF
Write the subsection "Hirshfeld Charge Redistribution and Dipole Response" for "$BASE_NAME".

Requirements:
- Use only the LOCAL DATA block above.
- Discuss the direction and magnitude of charge redistribution among the Li2 fragment, the S8 fragment, and the C60 host.
- State explicitly which fragment behaves as the dominant electron donor and which behaves as the dominant electron acceptor, but only if the data support that conclusion.
- Comment on the total dipole moment information if it is present, and explain what it implies about polarization upon complex formation.
- Link the charge analysis to adsorption and electrostatic stabilization without overclaiming covalent character.
EOF

  ai_section_header "SECTION 5. Charge decomposition analysis (CDA)"
  print_ai_data_block emit_cda_data
  echo
  echo "SECTION PROMPT"
  cat <<EOF
Write the subsection "Fragment Charge Transfer and Orbital Interaction from CDA" for "$BASE_NAME".

Requirements:
- Use only the LOCAL DATA block above.
- Interpret both the CDA/ECDA totals and the orbital-resolved interaction data associated with orbinteract-pub.png.
- Discuss the direction of net charge transfer, the balance between donation and back-donation, and the meaning of any asymmetry cautiously and rigorously.
- Describe which fragment orbitals dominate the complex frontier orbitals in the publication interaction window (HOMO-2 through LUMO+2), and whether fragment 1 contributes directly to frontier mixing.
- If the CDA trend is consistent with Hirshfeld charges, state that convergence explicitly.
- If an orbital interaction diagram would normally be cited, refer to it as Figure X or Figure X(a,b).
- Keep the wording rigorous and avoid turning CDA into a bonding metric it does not directly provide.
EOF

  ai_section_header "SECTION 6. Frontier orbitals and HOMO/LUMO response"
  print_ai_data_block emit_frontier_data
  echo
  echo "SECTION PROMPT"
  cat <<EOF
Write the subsection "Frontier Orbitals and HOMO/LUMO Response" for "$BASE_NAME".

Requirements:
- Use only the LOCAL DATA block above.
- Discuss the frontier-orbital energies together with the HOMO/LUMO cube-file evidence.
- Distinguish clearly between the orbital HOMO-LUMO gap and the larger fundamental gap from conceptual DFT; do not conflate them.
- Interpret the frontier-orbital information in terms of donor/acceptor separation, charge-transfer propensity, and electronic responsiveness only where justified by the data.
- Do not claim orbital spatial localization unless it is directly supported by the LOCAL DATA block.
- If visual HOMO/LUMO plots would normally accompany the discussion, cite them as Figure X or Figure X(a-c).
- Make the prose flow naturally from Section 3 while avoiding repetition.
EOF

  ai_section_header "SECTION 7. Hirshfeld surface contacts"
  print_ai_data_block emit_hs_contacts_data
  echo
  echo "SECTION PROMPT"
  cat <<EOF
Write the subsection "Hirshfeld Surface Contact Analysis" for "$BASE_NAME".

Requirements:
- Use only the LOCAL DATA block above.
- Discuss which intermolecular contacts dominate the host-guest interface and what that implies about the spatial organization of interaction.
- Use both the contact-area percentages and any fingerprint statistics present in the LOCAL DATA block.
- Explain whether the contact pattern supports localized anchoring, distributed surface accommodation, or mixed interaction motifs.
- If the contact analysis would normally be shown by Hirshfeld surface panels or fingerprint plots, cite them as Figure X or Figure X(a,b).
- Keep the interpretation descriptive but chemically meaningful, suitable for direct inclusion in a journal manuscript.
EOF

  ai_section_header "SECTION 8. Mayer bond order analysis"
  print_ai_data_block emit_mayer_bondorders_data
  echo
  echo "SECTION PROMPT"
  cat <<EOF
Write the subsection "Bonding Character from Mayer Bond Orders" for "$BASE_NAME".

Requirements:
- Use only the LOCAL DATA block above.
- Identify whether the reported bond orders indicate intact intrafragment bonds, interfragment bond formation, weak coordinative interactions, or predominantly noncovalent contact.
- Pay particular attention to any Li-S, S-S, or host-guest bond-order signatures if present.
- Be careful not to equate a small nonzero bond order with a strong covalent bond.
- Use the discussion to refine, not replace, the conclusions from energetic and charge analyses.
EOF

  ai_section_header "SECTION 9. Electrostatic potential (ESP) summary"
  print_ai_data_block emit_esp_data
  echo
  echo "SECTION PROMPT"
  cat <<EOF
Write the subsection "Electrostatic Potential and Polarization Features" for "$BASE_NAME".

Requirements:
- Use only the LOCAL DATA block above.
- Distinguish clearly between grid extrema and chemically interpretable surface-mapped ESP information.
- Use the ESP data together with the reported fragment or atomic charges to discuss which regions are relatively positive and relatively negative.
- Treat the extremely large positive grid maximum near nuclei cautiously rather than as a chemically meaningful surface feature.
- Explain what the ESP pattern implies for electrophilic or nucleophilic regions, polarization, and electrostatic complementarity at the interface.
- Link the electrostatic picture to charge redistribution and adsorption stabilization where justified.
- If an ESP map would normally accompany the interpretation, refer to it as Figure X or Figure X(a,b).
- Do not invent surface maps or spatial details that are not explicitly reported.
EOF

  ai_section_header "SECTION 10. NCI / IGMH / IRI qualitative analyses"
  print_ai_data_block emit_weak_interactions_data
  echo
  echo "SECTION PROMPT"
  cat <<EOF
Write the subsection "Weak-Interaction Analysis" for "$BASE_NAME".

Requirements:
- Use only the LOCAL DATA block above.
- Use the explicit NCI, IGMH, and IRI numerical metadata if present; do not reduce this subsection to mere file presence when more information is available.
- Position NCI as RDG-based corroboration, IGMH as separation of interfragment and intrafragment interaction contributions, and IRI as a complementary all-interaction real-space descriptor.
- If delta-g_inter and delta-g_intra are both present, discuss their relative magnitude cautiously and avoid overstating interfragment covalency.
- Do not invent color-map features, isosurfaces, or specific attractive or repulsive domains unless numerical or textual evidence is actually present.
- If these weak-interaction analyses would normally be displayed visually, cite them as Figure X or Figure X(a-c) while keeping the description conservative.
- Use this subsection mainly to position the weak-interaction analyses as corroborative evidence alongside energetics, charge transfer, and surface-contact data.
EOF

  ai_section_header "FINAL SYNTHESIS PROMPT"
  cat <<EOF
Using all LOCAL DATA blocks above and, if available, the ten subsection drafts generated from the section prompts, write a single coherent Results and Discussion section for "$BASE_NAME".

Requirements:
- Produce polished, publication-ready American English.
- Use informative subsection headings.
- Maintain a clear logical sequence from adsorption thermodynamics to electronic structure, bonding analysis, electrostatics, and weak interactions.
- Remove redundancy across subsections and keep the final text tight.
- Preserve every reported numerical value exactly.
- Use Figure X placeholders naturally where visual evidence would normally be cited in a paper, especially for orbitals, ESP, Hirshfeld surface contacts, and weak-interaction maps.
- Where evidence is missing, remain explicit and conservative rather than speculative.
- Keep Section 3 focused on descriptor-based global/local reactivity, and keep Section 6 focused on frontier-orbital energies together with HOMO/LUMO evidence.
- In the electrostatics discussion, do not confuse near-nuclear grid extrema with chemically meaningful surface electrostatic potential features.
EOF
}

###############################################################################
# Main
###############################################################################

emit_summary_report | tee "$SUMMARY_REPORT"
emit_ai_report > "$AI_REPORT"

echo
echo "[$IQCAP_MODULE] Saved reports:"
echo "  $SUMMARY_REPORT"
echo "  $AI_REPORT"

