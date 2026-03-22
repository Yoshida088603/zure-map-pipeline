#!/usr/bin/env bash
# GeoPackage を「東京都（JIS 都道府県コード 13）」と「それ以外」に分割する。
# 行政界に沿うため、地図上の境目が FID 分割より自然になりやすい。
#
# 使い方（リポジトリルートで）:
#   bash 02-convert/46-split-gpkg-tokyo-other.sh <入力.gpkg> <出力ディレクトリ> [接頭辞] [レイヤ名]
# 接頭辞省略時: 入力のベース名（例 09.gpkg → 09-tokyo.gpkg / 09-other.gpkg）
# レイヤ名省略時: kozu_merged
#
# 例（系9）:
#   bash 02-convert/46-split-gpkg-tokyo-other.sh \
#     data/03-geopackage/shp2geopackage/geopackage_per_kei/09.gpkg \
#     data/03-geopackage/shp2geopackage/geopackage_per_kei_split \
#     09kei
#   → 09kei-tokyo.gpkg（PREFCODE=13） / 09kei-other.gpkg（13 以外および NULL）
#
# 環境変数 SPLIT_TOKYO_PREFCODE … 東京都のコード（既定 13）
#
# GDAL: 45-geopackage2pmtiles.sh と同じ PATH / HandsOn env.sh の扱い。

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
export LANG=C.UTF-8
cd "$REPO_ROOT"

TOKYO_PREF="${SPLIT_TOKYO_PREFCODE:-13}"

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
OUT_TOKYO="$OUT_DIR/${STEM}-tokyo.gpkg"
OUT_OTHER="$OUT_DIR/${STEM}-other.gpkg"

fc=$(ogrinfo -so "$IN_GPKG" "$LAYER" 2>/dev/null | grep -i '^Feature Count:' | awk '{print $NF}')
echo "入力: $IN_GPKG レイヤ=$LAYER 全体件数=$fc"
echo "分割: PREFCODE=$TOKYO_PREF → ${STEM}-tokyo、それ以外 → ${STEM}-other"

rm -f "$OUT_TOKYO" "$OUT_OTHER"

ogr2ogr -f GPKG "$OUT_TOKYO" "$IN_GPKG" "$LAYER" -where "PREFCODE = $TOKYO_PREF" 2>&1
ogr2ogr -f GPKG "$OUT_OTHER" "$IN_GPKG" "$LAYER" -where "PREFCODE <> $TOKYO_PREF OR PREFCODE IS NULL" 2>&1

ft=$(ogrinfo -so "$OUT_TOKYO" "$LAYER" 2>/dev/null | grep -i '^Feature Count:' | awk '{print $NF}')
fo=$(ogrinfo -so "$OUT_OTHER" "$LAYER" 2>/dev/null | grep -i '^Feature Count:' | awk '{print $NF}')
echo "出力: $OUT_TOKYO (件数 $ft)"
echo "出力: $OUT_OTHER (件数 $fo)"
sum=$((ft + fo))
if [[ "$sum" -ne "$fc" ]]; then
  echo "Warning: 件数合計 $sum が元 $fc と一致しません。" >&2
fi
