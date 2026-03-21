#!/usr/bin/env bash
# 互換ラッパ: 20-shp2geopackage.sh zure に 2 段階変換＋単一系のみを渡す。
# 実装は 20 側（ZURE_TWO_PASS / ZURE_ONLY_KEI）。
#
# 使い方: リポジトリルートで
#   bash 02-convert/21-zure-two-pass-test.sh [系2桁 既定03]
#
# 環境変数 OUTPUT_BASE を上書きしなければ、two_pass_test_keiNN_<TS>/ に出力。

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
KEI="${1:-03}"
if ! [[ "$KEI" =~ ^[0-9]{1,2}$ ]]; then
  echo "Usage: $0 [系番号 既定03]" >&2
  exit 1
fi
KEI=$(printf '%02d' "$((10#$KEI))")
export ZURE_TWO_PASS=1
export ZURE_ONLY_KEI="$KEI"
RUN_TS=$(TZ=Asia/Tokyo date +%Y%m%d_%H%M%S)
export OUTPUT_BASE="${OUTPUT_BASE:-$REPO_ROOT/data/03-geopackage/shp2geopackage/two_pass_test_kei${KEI}_${RUN_TS}}"
cd "$REPO_ROOT"
exec bash "$SCRIPT_DIR/20-shp2geopackage.sh" zure
