#!/usr/bin/env bash
# GeoPackage を PMTiles に変換する。出力は入力と同じディレクトリに .pmtiles。
# 使い方: bash 02-convert/45-geopackage2pmtiles.sh [入力.gpkg]
# 既定入力: data/04-merge-geopackage/土地活用推進調査_merged.gpkg
# 前提: PATH 上に ogr2ogr（GDAL）。ビルド作業は行わない。

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DEFAULT_GPKG="$REPO_ROOT/data/04-merge-geopackage/土地活用推進調査_merged.gpkg"

GPKG="${1:-$DEFAULT_GPKG}"
if [[ ! -f "$GPKG" ]]; then
  echo "Error: GeoPackage not found: $GPKG" >&2
  exit 1
fi

DIR="$(dirname "$GPKG")"
BASE="$(basename "$GPKG" .gpkg)"
OUT_PMTILES="$DIR/${BASE}.pmtiles"
OUT_PARQUET="$DIR/${BASE}.parquet"

cd "$REPO_ROOT"
T_SRS="-t_srs EPSG:3857"

echo "Converting: $GPKG -> $OUT_PMTILES"
err=$(ogr2ogr -skipfailures -nlt PROMOTE_TO_MULTI $T_SRS -dsco MINZOOM=0 -dsco MAXZOOM=15 \
  -f "PMTiles" "$OUT_PMTILES" "$GPKG" 2>&1) || true
if [[ -f "$OUT_PMTILES" ]]; then
  echo "Done. Output: $OUT_PMTILES"
  exit 0
fi
if echo "$err" | grep -q "does not support data source creation"; then
  echo "PMTiles 直接出力は非対応のため、GeoParquet を経由します。" >&2
else
  echo "$err" >&2
fi

echo "Writing GeoParquet: $OUT_PARQUET"
if ! ogr2ogr -skipfailures $T_SRS -f Parquet -lco GEOMETRY_ENCODING=WKB "$OUT_PARQUET" "$GPKG" 2>&1; then
  echo "Error: GeoParquet の作成に失敗しました。" >&2
  exit 1
fi
[[ -f "$OUT_PARQUET" ]] || { echo "Error: Parquet が生成されませんでした。" >&2; exit 1; }

echo "Writing PMTiles: $OUT_PMTILES"
pmt_err=$(ogr2ogr -skipfailures -s_srs EPSG:3857 $T_SRS -dsco MINZOOM=0 -dsco MAXZOOM=15 -f "PMTiles" \
  "$OUT_PMTILES" "$OUT_PARQUET" 2>&1) || true

if [[ -f "$OUT_PMTILES" ]]; then
  rm -f "$OUT_PARQUET"
  echo "Done. Output: $OUT_PMTILES"
  exit 0
fi

if echo "$pmt_err" | grep -q "does not support data source creation"; then
  echo "" >&2
  echo "この GDAL では PMTiles 書き込みが無効の可能性があります。" >&2
  echo "GeoParquet は出力済み: $OUT_PARQUET" >&2
else
  echo "$pmt_err" >&2
  echo "Parquet は残しています: $OUT_PARQUET" >&2
fi
exit 1
