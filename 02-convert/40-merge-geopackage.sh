#!/usr/bin/env bash
# 個別 GPKG（data/03-geopackage/csv2geopackage）を用途別にマージし data/04-merge-geopackage に出力する。
# 旧 HandsOn の merge_tochi / merge_gaiku / merge_toshi / merge_kozu を順に実行相当。
# 使い方: bash 02-convert/40-merge-geopackage.sh [tochi|gaiku|toshi|kozu|all]
# 前提: PATH 上に ogr2ogr。GDAL のビルドは行わない。

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
G3="$REPO_ROOT/data/03-geopackage/csv2geopackage"
G4="$REPO_ROOT/data/04-merge-geopackage"
export LANG=C.UTF-8
cd "$REPO_ROOT"

if ! command -v ogr2ogr &>/dev/null; then
  echo "Error: ogr2ogr が PATH にありません。" >&2
  exit 1
fi

merge_tochi() {
  local INPUT_DIR="$G3/土地活用推進調査"
  local OUTPUT_FILE="$G4/土地活用推進調査_merged.gpkg"
  local SRC_SRS="${SRC_SRS:-EPSG:6674}"
  local TGT_SRS="EPSG:3857"
  [[ -d "$INPUT_DIR" ]] || { echo "skip tochi: no $INPUT_DIR"; return 0; }
  shopt -s nullglob
  local gpkgs=("$INPUT_DIR"/*.gpkg)
  if [[ ${#gpkgs[@]} -eq 0 ]]; then echo "skip tochi: no gpkg"; return 0; fi
  mkdir -p "$G4"
  rm -f "$OUTPUT_FILE"
  local first=true merged=0
  for gpkg in "${gpkgs[@]}"; do
    local base
    base=$(basename "$gpkg" .gpkg)
    if [[ "$first" == true ]]; then
      ogr2ogr -f GPKG -nln tochi_merged -s_srs "$SRC_SRS" -t_srs "$TGT_SRS" "$OUTPUT_FILE" "$gpkg" || { echo "Warning: $base" >&2; continue; }
      first=false
      merged=$((merged + 1))
    else
      ogr2ogr -update -append -nln tochi_merged -s_srs "$SRC_SRS" -t_srs "$TGT_SRS" "$OUTPUT_FILE" "$gpkg" || { echo "Warning: $base" >&2; continue; }
      merged=$((merged + 1))
    fi
  done
  echo "merge_tochi: $merged files -> $OUTPUT_FILE"
}

merge_gaiku() {
  local INPUT_DIR="$G3/街区基準点等データ"
  local OUTPUT_FILE="$G4/街区基準点等_merged.gpkg"
  [[ -d "$INPUT_DIR" ]] || { echo "skip gaiku: no $INPUT_DIR"; return 0; }
  shopt -s nullglob
  local gpkgs=("$INPUT_DIR"/*.gpkg)
  if [[ ${#gpkgs[@]} -eq 0 ]]; then echo "skip gaiku: no gpkg"; return 0; fi
  mkdir -p "$G4"
  rm -f "$OUTPUT_FILE"
  local first=true merged=0
  for gpkg in "${gpkgs[@]}"; do
    local base
    base=$(basename "$gpkg" .gpkg)
    if [[ "$first" == true ]]; then
      ogr2ogr -f GPKG -nln gaiku_merged "$OUTPUT_FILE" "$gpkg" || { echo "Warning: $base" >&2; continue; }
      first=false
      merged=$((merged + 1))
    else
      ogr2ogr -update -append -nln gaiku_merged "$OUTPUT_FILE" "$gpkg" || { echo "Warning: $base" >&2; continue; }
      merged=$((merged + 1))
    fi
  done
  echo "merge_gaiku: $merged files -> $OUTPUT_FILE"
}

merge_toshi() {
  local INPUT_DIR="$G3/都市部官民基準点等データ"
  local OUTPUT_FILE="$G4/都市部官民基準点等_merged.gpkg"
  [[ -d "$INPUT_DIR" ]] || { echo "skip toshi: no $INPUT_DIR"; return 0; }
  shopt -s nullglob
  local gpkgs=("$INPUT_DIR"/*.gpkg)
  if [[ ${#gpkgs[@]} -eq 0 ]]; then echo "skip toshi: no gpkg"; return 0; fi
  mkdir -p "$G4"
  rm -f "$OUTPUT_FILE"
  local first=true merged=0
  for gpkg in "${gpkgs[@]}"; do
    local base
    base=$(basename "$gpkg" .gpkg)
    if [[ "$first" == true ]]; then
      ogr2ogr -f GPKG -nln toshi_merged "$OUTPUT_FILE" "$gpkg" || { echo "Warning: $base" >&2; continue; }
      first=false
      merged=$((merged + 1))
    else
      ogr2ogr -update -append -nln toshi_merged "$OUTPUT_FILE" "$gpkg" || { echo "Warning: $base" >&2; continue; }
      merged=$((merged + 1))
    fi
  done
  echo "merge_toshi: $merged files -> $OUTPUT_FILE"
}

merge_kozu() {
  local INPUT_DIR="$G3/公図と現況のずれデータ"
  local OUTPUT_FILE="$G4/公図と現況のずれデータ_merged.gpkg"
  local LAYER_NAME="kozu_merged"
  local NPROC="${NPROC:-2}"
  local WORK_DIR="$G4"
  [[ -d "$INPUT_DIR" ]] || { echo "skip kozu: no $INPUT_DIR"; return 0; }

  local gpkgs=()
  while IFS= read -r -d '' f; do
    gpkgs+=( "$f" )
  done < <(find "$INPUT_DIR" -maxdepth 1 -name "*_残差データ抽出.gpkg" -print0 | sort -z)
  local NUM=${#gpkgs[@]}
  if [[ $NUM -eq 0 ]]; then echo "skip kozu: no *_残差データ抽出.gpkg"; return 0; fi

  mkdir -p "$(dirname "$OUTPUT_FILE")"
  rm -f "$OUTPUT_FILE"

  local PART_WORK_DIR="$WORK_DIR"
  if [[ "${MERGE_USE_RAM:-1}" != "0" ]] && [[ -d /dev/shm ]]; then
    local shm_avail_kb
    shm_avail_kb=$(df -k /dev/shm 2>/dev/null | awk 'NR==2 {print $4}')
    if [[ -n "$shm_avail_kb" ]] && [[ "${shm_avail_kb:-0}" -ge 4194304 ]]; then
      PART_WORK_DIR=$(mktemp -d /dev/shm/merge_kozu.XXXXXX)
      echo "Using RAM work dir: $PART_WORK_DIR" >&2
    fi
  fi
  local PART_PREFIX="${PART_WORK_DIR}/.merge_part_"
  rm -f "${PART_PREFIX}"*.gpkg

  local batch_size=$(( (NUM + NPROC - 1) / NPROC ))
  merge_one_batch() {
    local part_id=$1
    local start=$(( part_id * batch_size ))
    local end=$(( start + batch_size ))
    if (( end > NUM )); then end=$NUM; fi
    local part_file="${PART_PREFIX}${part_id}.gpkg"
    local first=true
    local i
    for (( i = start; i < end; i++ )); do
      local gpkg="${gpkgs[i]}"
      if [[ "$first" == true ]]; then
        if ogr2ogr -skipfailures -f GPKG -nln "$LAYER_NAME" -nlt PROMOTE_TO_MULTI \
          "$part_file" "$gpkg" 2>&1; then
          first=false
        fi
      else
        ogr2ogr -skipfailures -update -append -nln "$LAYER_NAME" -nlt PROMOTE_TO_MULTI \
          "$part_file" "$gpkg" 2>/dev/null || true
      fi
    done
  }
  local p
  for (( p = 0; p < NPROC; p++ )); do
    merge_one_batch "$p" &
  done
  wait

  local merged_parts=0
  for (( p = 0; p < NPROC; p++ )); do
    local part_file="${PART_PREFIX}${p}.gpkg"
    [[ -f "$part_file" ]] || continue
    if [[ $merged_parts -eq 0 ]]; then
      cp "$part_file" "$OUTPUT_FILE"
      merged_parts=$((merged_parts + 1))
    else
      ogr2ogr -skipfailures -update -append -nln "$LAYER_NAME" -nlt PROMOTE_TO_MULTI \
        "$OUTPUT_FILE" "$part_file" 2>/dev/null && merged_parts=$((merged_parts + 1)) || true
    fi
  done
  rm -f "${PART_PREFIX}"*.gpkg
  if [[ "$PART_WORK_DIR" != "$WORK_DIR" ]] && [[ -d "$PART_WORK_DIR" ]]; then
    rm -rf "$PART_WORK_DIR"
  fi
  echo "merge_kozu: $NUM sources -> $OUTPUT_FILE"
}

MODE="${1:-all}"
case "$MODE" in
  tochi) merge_tochi ;;
  gaiku) merge_gaiku ;;
  toshi) merge_toshi ;;
  kozu) merge_kozu ;;
  all)
    merge_tochi
    merge_gaiku
    merge_toshi
    merge_kozu
    ;;
  *)
    echo "Usage: $0 [tochi|gaiku|toshi|kozu|all]" >&2
    exit 1
    ;;
esac
echo "Done."
