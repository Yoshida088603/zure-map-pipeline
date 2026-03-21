#!/usr/bin/env bash
# 統合 GeoPackage（data/04-merge-geopackage）の ogrinfo による簡易検証。
# 使い方: bash 02-convert/42-check-merge-geopackage.sh [ディレクトリ]
# 既定: data/04-merge-geopackage

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DIR="${1:-$REPO_ROOT/data/04-merge-geopackage}"

if [[ ! -d "$DIR" ]]; then
  echo "Error: ディレクトリがありません: $DIR" >&2
  exit 1
fi
if ! command -v ogrinfo &>/dev/null; then
  echo "Error: ogrinfo が PATH にありません（GDAL）。" >&2
  exit 1
fi

echo "=== 42-check-merge-geopackage: $DIR ==="
shopt -s nullglob
for gpkg in "$DIR"/*.gpkg; do
  [[ -f "$gpkg" ]] || continue
  echo ""
  echo "--- $(basename "$gpkg") ---"
  ogrinfo -so -al "$gpkg" 2>&1 | head -80
done
echo ""
echo "Done."
