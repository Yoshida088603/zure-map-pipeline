#!/usr/bin/env bash
# GeoPackage の 1 レイヤを、FID（列 fid）の前半・後半で 2 ファイルに分割する。
# 系9のように 1 本の PMTiles が 100MB を超えるとき、A/B に分けて 0–13 等を載せる用途向け。
#
# 使い方（リポジトリルートで）:
#   bash 02-convert/46-split-gpkg-fid-half.sh <入力.gpkg> <出力ディレクトリ> [接頭辞] [レイヤ名]
# 接頭辞省略時: 入力ファイルのベース名（09.gpkg → 09-A.gpkg / 09-B.gpkg）
# レイヤ名省略時: kozu_merged
#
# 例:
#   bash 02-convert/46-split-gpkg-fid-half.sh \
#     data/03-geopackage/shp2geopackage/geopackage_per_kei/09.gpkg \
#     data/03-geopackage/shp2geopackage/geopackage_per_kei_split \
#     09kei
#   → 09kei-A.gpkg / 09kei-B.gpkg
#
# GDAL: 45-geopackage2pmtiles.sh と同じ PATH / HandsOn env.sh の扱い。

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
export LANG=C.UTF-8
cd "$REPO_ROOT"

zure_try_source_gdal_env() {
  command -v ogr2ogr &>/dev/null && return 0
  local env_sh
  local cands=()
  [[ -n "${GDAL_ENV_SH:-}" ]] && cands+=( "$GDAL_ENV_SH" )
  cands+=(
    "$REPO_ROOT/../maplibre/MapLibre-HandsOn-Beginner/05_ポリゴン表示/gdal-full/env.sh"
    "$REPO_ROOT/../MapLibre-HandsOn-Beginner/05_ポリゴン表示/gdal-full/env.sh"
  )
  for env_sh in "${cands[@]}"; do
    [[ -z "$env_sh" || ! -f "$env_sh" ]] && continue
    # shellcheck source=/dev/null
    source "$env_sh"
    if command -v ogr2ogr &>/dev/null; then
      echo "GDAL: env を読み込みました ($env_sh)" >&2
      return 0
    fi
  done
  return 1
}

zure_try_source_gdal_env || true
if ! command -v ogr2ogr &>/dev/null; then
  echo "Error: ogr2ogr が PATH にありません。" >&2
  exit 1
fi

IN_GPKG="${1:?入力 .gpkg を指定してください}"
OUT_DIR="${2:?出力ディレクトリを指定してください}"
BASE="$(basename "$IN_GPKG" .gpkg)"
STEM="${3:-$BASE}"
LAYER="${4:-kozu_merged}"

if [[ ! -f "$IN_GPKG" ]]; then
  echo "Error: ファイルがありません: $IN_GPKG" >&2
  exit 1
fi

IN_GPKG="$(cd "$(dirname "$IN_GPKG")" && pwd)/$(basename "$IN_GPKG")"
mkdir -p "$OUT_DIR"
OUT_DIR="$(cd "$OUT_DIR" && pwd)"
OUT_A="$OUT_DIR/${STEM}-A.gpkg"
OUT_B="$OUT_DIR/${STEM}-B.gpkg"

fc_line=$(ogrinfo -so "$IN_GPKG" "$LAYER" 2>/dev/null | grep -i '^Feature Count:')
fc=$(echo "$fc_line" | awk '{print $NF}')
if [[ -z "$fc" || ! "$fc" =~ ^[0-9]+$ ]]; then
  echo "Error: Feature Count を取得できません: $IN_GPKG $LAYER" >&2
  exit 1
fi

half=$((fc / 2))
if [[ "$half" -lt 1 ]]; then
  echo "Error: フィーチャが少なすぎます (count=$fc)" >&2
  exit 1
fi

echo "入力: $IN_GPKG レイヤ=$LAYER 件数=$fc 分割点 fid<=$half / fid>$half"
rm -f "$OUT_A" "$OUT_B"

ogr2ogr -f GPKG "$OUT_A" "$IN_GPKG" "$LAYER" -where "fid <= $half" 2>&1
ogr2ogr -f GPKG "$OUT_B" "$IN_GPKG" "$LAYER" -where "fid > $half" 2>&1

fa=$(ogrinfo -so "$OUT_A" "$LAYER" 2>/dev/null | grep -i '^Feature Count:' | awk '{print $NF}')
fb=$(ogrinfo -so "$OUT_B" "$LAYER" 2>/dev/null | grep -i '^Feature Count:' | awk '{print $NF}')
echo "出力: $OUT_A (件数 $fa)"
echo "出力: $OUT_B (件数 $fb)"
if [[ "$((fa + fb))" -ne "$fc" ]]; then
  echo "Warning: 件数合計 $((fa + fb)) が元 $fc と一致しません。" >&2
fi
