#!/usr/bin/env bash
# RAW（data/01-raw-data）のざっくりプレビュー・ベースライン用。
# 使い方: リポジトリルートで bash 01-raw-data-preview/10-data-preview.sh
# ログ: data/02-raw-data-preview/raw_preview_log.txt（追記）

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RAW="$REPO_ROOT/data/01-raw-data"
LOG="$REPO_ROOT/data/02-raw-data-preview/raw_preview_log.txt"

export LANG=C.UTF-8
mkdir -p "$(dirname "$LOG")"
{
  echo "=== $(date -Iseconds) 10-data-preview ==="
  echo "RAW root: $RAW"
  if [[ ! -d "$RAW" ]]; then
    echo "Error: RAW が見つかりません: $RAW"
    exit 1
  fi
  echo "--- 合計サイズ ---"
  du -sh "$RAW" 2>/dev/null || true
  echo "--- ファイル数 ---"
  find "$RAW" -type f 2>/dev/null | wc -l
  echo "--- 先頭ディレクトリ ---"
  find "$RAW" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -20
  echo "=== end ==="
} | tee -a "$LOG"
