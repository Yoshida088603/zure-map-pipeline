#!/usr/bin/env bash
# data/03-geopackage/shp2geopackage/geopackage_per_kei の各 GeoPackage を、
# マスク・分割なしで PMTiles（既定 zoom 0–11）へ書き出す。
#
# 実処理は 45-geopackage2pmtiles.sh（MAX_FEATURES / MAX_SIZE 既定 2^31-1、タイル内切り捨てを実質無効化）。
# 命名: NN.gpkg → <出力ディレクトリ>/NN.pmtiles（GPKG のベース名そのまま）
#
# 使い方（リポジトリルートで）:
#   bash 02-convert/47-geopackage-per-kei2pmtiles.sh
#   bash 02-convert/47-geopackage-per-kei2pmtiles.sh /path/to/geopackage_per_kei /path/to/out
#   bash 02-convert/47-geopackage-per-kei2pmtiles.sh /path/to/09.gpkg data/05-pmtiles   # 1 ファイルのみ
#
# 環境変数:
#   GPKG_PER_KEI_DIR … 第1引数より優先して入力ディレクトリ（単一 .gpkg 指定時は無視）
#   PMTILES_OUT_DIR    … 第2引数より優先して出力ディレクトリ
#   PMTILES_MINZOOM / PMTILES_MAXZOOM … 既定 0 / 11（45 にそのまま渡す。z12 に戻すときは PMTILES_MAXZOOM=12）

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
export LANG=C.UTF-8
cd "$REPO_ROOT"

DEFAULT_IN="$REPO_ROOT/data/03-geopackage/shp2geopackage/geopackage_per_kei"
DEFAULT_OUT="$REPO_ROOT/data/05-pmtiles"

OUT_DIR="${PMTILES_OUT_DIR:-${2:-$DEFAULT_OUT}}"
IN_ARG="${GPKG_PER_KEI_DIR:-${1:-$DEFAULT_IN}}"

run_one() {
  local gpkg="$1"
  export PMTILES_MINZOOM="${PMTILES_MINZOOM:-0}"
  export PMTILES_MAXZOOM="${PMTILES_MAXZOOM:-11}"
  bash "$SCRIPT_DIR/45-geopackage2pmtiles.sh" "$gpkg" "$OUT_DIR"
}

if [[ -f "$IN_ARG" && "$IN_ARG" == *.gpkg ]]; then
  GPKG="$(cd "$(dirname "$IN_ARG")" && pwd)/$(basename "$IN_ARG")"
  mkdir -p "$OUT_DIR"
  OUT_DIR="$(cd "$OUT_DIR" && pwd)"
  echo "Single file: $GPKG -> $OUT_DIR/"
  run_one "$GPKG"
  exit 0
fi

IN_DIR="$IN_ARG"
if [[ ! -d "$IN_DIR" ]]; then
  echo "Error: ディレクトリがありません: $IN_DIR" >&2
  echo "（単一ファイルのときは .gpkg のフルパスを第1引数に）" >&2
  exit 1
fi

IN_DIR="$(cd "$IN_DIR" && pwd)"
mkdir -p "$OUT_DIR"
OUT_DIR="$(cd "$OUT_DIR" && pwd)"

shopt -s nullglob
gpkgs=( "$IN_DIR"/*.gpkg )
shopt -u nullglob

if [[ ${#gpkgs[@]} -eq 0 ]]; then
  echo "Error: $IN_DIR に .gpkg がありません。" >&2
  exit 1
fi

IFS=$'\n' gpkgs_sorted=( $(printf '%s\n' "${gpkgs[@]}" | sort -V) )
unset IFS

echo "入力: $IN_DIR (${#gpkgs_sorted[@]} 件) -> 出力: $OUT_DIR (PMTiles z${PMTILES_MINZOOM:-0}-${PMTILES_MAXZOOM:-11})"
for g in "${gpkgs_sorted[@]}"; do
  echo "--- $(basename "$g") ---"
  run_one "$g"
done
echo "Done. ${#gpkgs_sorted[@]} 本を $OUT_DIR に出力しました。"
