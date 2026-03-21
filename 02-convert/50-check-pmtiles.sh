#!/usr/bin/env bash
# PMTiles 書き出しが可能か GDAL で確認する（ビルドは行わない）。
# 使い方: bash 02-convert/50-check-pmtiles.sh

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

echo "=== PMTiles 書き出し可否の確認 ==="
echo "GDAL: $(ogr2ogr --version 2>/dev/null || true)"
echo ""

if ! ogrinfo --formats 2>/dev/null | grep -q "PMTiles"; then
  echo "結果: 不可（PMTiles ドライバが登録されていません）"
  exit 1
fi
echo "1) PMTiles ドライバ: 登録あり"

TMP_DIR="${TMPDIR:-/tmp}"
MIN_GPKG="$TMP_DIR/check_pmtiles_minimal_$$.gpkg"
OUT_PMTILES="$TMP_DIR/check_pmtiles_out_$$.pmtiles"
MIN_GEOJSON="$TMP_DIR/check_pmtiles_minimal_$$.geojson"
trap 'rm -f "$MIN_GPKG" "$OUT_PMTILES" "$MIN_GEOJSON"' EXIT

GEOJSON='{"type":"FeatureCollection","features":[{"type":"Feature","geometry":{"type":"Point","coordinates":[139.7,35.6]},"properties":{}}]}'
echo "$GEOJSON" > "$MIN_GEOJSON"

if ! ogr2ogr -f GPKG "$MIN_GPKG" "$MIN_GEOJSON" -nln p 2>/dev/null; then
  echo "2) 最小 GPKG: GeoJSON から作成失敗。既存 .gpkg を探索します…"
  EXISTING=$(find "$REPO_ROOT/data" -name "*.gpkg" -type f 2>/dev/null | head -1)
  if [[ -z "$EXISTING" || ! -f "$EXISTING" ]]; then
    echo "結果: 確認できず（テスト用 GPKG がありません）"
    exit 2
  fi
  MIN_GPKG="$EXISTING"
fi

echo "2) テスト用 GPKG: 用意済み"
echo "3) PMTiles 書き出し試行: $OUT_PMTILES"
err=$(ogr2ogr -skipfailures -dsco MINZOOM=0 -dsco MAXZOOM=5 \
  -f "PMTiles" "$OUT_PMTILES" "$MIN_GPKG" 2>&1) || true

if echo "$err" | grep -q "does not support data source creation"; then
  echo ""
  echo "結果: 不可（PMTiles 書き込みがこの GDAL で無効の可能性）"
  exit 1
fi

if [[ -f "$OUT_PMTILES" ]]; then
  echo ""
  echo "結果: 可（PMTiles を書き出せます）"
  exit 0
fi

echo ""
echo "結果: 不明（ファイルは作成されませんでした）"
echo "stderr: $err"
exit 2
