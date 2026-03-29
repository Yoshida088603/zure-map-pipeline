#!/usr/bin/env bash
# overview.pmtiles + 系別 PMTiles の MapLibre 検図用 URL を Markdown 形式で stdout に出す。
# 使用例:
#   BASE_URL=http://192.168.1.10:8080 ./print_zure_verification_urls.sh
# 既定 BASE_URL は http://localhost:8080（serve.py の既定ポートに合わせる）

set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:8080}"
BASE_URL="${BASE_URL%/}"

path="/03-analysis/maplibre/index.html"

echo "- [単系 + overview（既定 09 系）](${BASE_URL}${path}?mode=z12)"
echo "- [単系を指定（例: 01）](${BASE_URL}${path}?mode=z12&kei=01)"
echo "- [全系 + overview](${BASE_URL}${path}?mode=all-kei)"
