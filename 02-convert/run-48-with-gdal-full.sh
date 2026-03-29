#!/usr/bin/env bash
# MapLibre HandsOn の gdal-full でビルドした GDAL を有効にし、
# 48-overview-municipality-pmtiles.sh（overview.pmtiles 生成）を実行する。
#
# 前提: gdal-full でビルド済み（local/bin/ogr2ogr が存在すること）
#
# 使い方（リポジトリ zure-map-pipeline のルートでも 02-convert からでも可）:
#   bash 02-convert/run-48-with-gdal-full.sh
#   bash 02-convert/run-48-with-gdal-full.sh /path/to/N03.gpkg N03
#   bash 02-convert/run-48-with-gdal-full.sh /path/to/boundary.shp /path/to/geopackage_per_kei
#
# 環境変数:
#   GDAL_FULL_ENV_SH … env.sh のパス（省略時はリポジトリ隣の maplibre 配下を参照）
#   GPKG_PER_KEI_DIR … 48 と同じ（系別 GPKG ディレクトリ）
#   OVERVIEW_* / OVERVIEW_FULL_MERGE … 48 と同じ
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

DEFAULT_GDAL_ENV="$REPO_ROOT/../maplibre/MapLibre-HandsOn-Beginner/05_ポリゴン表示/gdal-full/env.sh"
GDAL_ENV="${GDAL_FULL_ENV_SH:-$DEFAULT_GDAL_ENV}"

if [[ ! -f "$GDAL_ENV" ]]; then
  echo "Error: gdal-full の env.sh が見つかりません: $GDAL_ENV" >&2
  echo "  次を指定してください: GDAL_FULL_ENV_SH=/絶対パス/.../gdal-full/env.sh" >&2
  exit 1
fi

# shellcheck source=/dev/null
source "$GDAL_ENV"

export GDAL_ENV_SH="$GDAL_ENV"
export PATH LD_LIBRARY_PATH GDAL_DATA PYTHONPATH

DEFAULT_N03="$REPO_ROOT/data/03-geopackage/gml2geopackage/N03-20250101_行政区域.gpkg"

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
fi

if [[ $# -eq 0 ]]; then
  if [[ ! -e "$DEFAULT_N03" ]]; then
    echo "Error: 既定の N03 GPKG がありません: $DEFAULT_N03" >&2
    echo "  第1引数に境界ファイル（.gpkg / .shp 等）を渡してください。" >&2
    exit 1
  fi
  echo "GDAL: $(command -v ogr2ogr) — $(ogr2ogr --version 2>/dev/null | head -1)"
  echo "境界（既定）: $DEFAULT_N03  レイヤ: N03"
  bash "$SCRIPT_DIR/48-overview-municipality-pmtiles.sh" "$DEFAULT_N03" N03
else
  echo "GDAL: $(command -v ogr2ogr) — $(ogr2ogr --version 2>/dev/null | head -1)"
  bash "$SCRIPT_DIR/48-overview-municipality-pmtiles.sh" "$@"
fi
