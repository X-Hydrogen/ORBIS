#!/usr/bin/env bash
# Interactive cleanup: prompt for each file > 1MB

set -e
cd "$(dirname "$0")"

files=(
  "1.1M  tests/run+advance/H2O-H2O/H2O-H2O-CDA/orbitals/frag1_MO8.png"
  "1.1M  tests/run+advance/H2O-H2O/H2O-H2O-TZVP+1/TZVP+1.gbw"
  "1.1M  tests/run+advance/H2O-H2O/H2O-H2O-TZVP-1/TZVP-1.gbw"
  "1.1M  tests/run+advance/H2O-H2O/H2O-H2O-TZVP/TZVP.gbw"
  "1.1M  tests/run+advance/H2O-H2O/opt.gbw"
  "1.8M  tests/ts/ts-PLOTS/irc_movie_front.gif"
  "2.0M  tests/run+advance/H2O-H2O/H2O-H2O-Fukui/fukui_panel.png"
  "2.1M  tests/ts/ts-PLOTS/irc_movie_side.gif"
  "2.2M  tests/ts/ts-PLOTS/irc_movie_top.gif"
  "111M  tests/run+advance/H2O-H2O/H2O-H2O-IGMH/output.txt"
  "118M  tests/run+advance/H2O-H2O/H2O-H2O-TZVP/output.txt"
  "547M  tests/run+advance/H2O-H2O/H2O-H2O-IRI/output.txt"
)

echo "=== IQCAP: 超过 1MB 的文件 (共 ${#files[@]} 个) ==="
echo "对每个文件输入 y 删除，n 保留，q 退出"
echo ""

for entry in "${files[@]}"; do
  size="${entry%%  *}"
  path="${entry#*  }"
  if [[ ! -f "$path" ]]; then
    echo "[跳过] $path (不存在)"
    continue
  fi
  while true; do
    read -rp "删除? [$size] $path [y/n/q]: " ans
    case "$ans" in
      y|Y) rm -v "$path"; echo ""; break ;;
      n|N) echo "  保留"; echo ""; break ;;
      q|Q) echo "退出"; exit 0 ;;
      *) echo "  请输入 y, n 或 q" ;;
    esac
  done
done

echo "=== 完成 ==="
