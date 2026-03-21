#!/usr/bin/env bash
# Shapefile 系パイプライン（旧: run_pipeline.sh / run_pipeline_14jyo.sh / run_pipeline_zuza_origin.sh）。
# 使い方: bash 02-convert/20-shp2geopackage.sh [sample|14jyo|zuza|all]
# - sample: data/03-geopackage/shp2geopackage/input の *.shp → data/05-pmtiles/shp-sample-out（Parquet/FGB/PMTiles）
# - 14jyo:  RAW の 14条地図 フォルダ内の全 SHP を 1 GPKG + PMTiles（data/05-pmtiles）
# - zuza:   RAW データ_origin の公図系（系ごと）→ 中間 GPKG → マージ GPKG → PMTiles（data/03-geopackage/shp2geopackage/zuza-work）
# 前提: PATH に ogr2ogr。Parquet/PMTiles ドライバは環境依存。GDAL のビルドは行わない。

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DATA_DVD="$REPO_ROOT/data/01-raw-data/05ホームページ公開用データ及びプログラム"
export LANG=C.UTF-8
cd "$REPO_ROOT"

for cmd in ogr2ogr ogrinfo; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "Error: $cmd が PATH にありません。" >&2
    exit 1
  fi
done

run_sample() {
  local INPUT_DIR="$REPO_ROOT/data/03-geopackage/shp2geopackage/input"
  local OUTPUT_DIR="$REPO_ROOT/data/05-pmtiles/shp-sample-out"
  mkdir -p "$OUTPUT_DIR"
  local FORMATS
  FORMATS=$(ogrinfo --formats 2>/dev/null || true)
  for drv in Parquet FlatGeobuf PMTiles; do
    if ! echo "$FORMATS" | grep -q "$drv"; then
      echo "Error: GDAL driver '$drv' is not available." >&2
      exit 1
    fi
  done
  shopt -s nullglob
  local FAILED=0
  for shp in "$INPUT_DIR"/*.shp; do
    [[ -f "$shp" ]] || { echo "No .shp in $INPUT_DIR"; return 0; }
    local base
    base=$(basename "$shp" .shp)
    echo "=== $base ==="
    if ! ogr2ogr -skipfailures -f Parquet -lco GEOMETRY_ENCODING=WKB \
      "$OUTPUT_DIR/${base}.parquet" "$shp" 2>&1; then
      echo "Warning: $base SHP→Parquet" >&2
      FAILED=1
      continue
    fi
    [[ -f "$OUTPUT_DIR/${base}.parquet" ]] || continue
    ogr2ogr -f FlatGeobuf -nlt PROMOTE_TO_MULTI -lco SPATIAL_INDEX=NO \
      "$OUTPUT_DIR/${base}.fgb" "$OUTPUT_DIR/${base}.parquet" 2>&1 || true
    ogr2ogr -skipfailures -dsco MINZOOM=0 -dsco MAXZOOM=15 -f "PMTiles" \
      "$OUTPUT_DIR/${base}.pmtiles" "$OUTPUT_DIR/${base}.parquet" 2>&1 || true
  done
  local ZUZA="$REPO_ROOT/data/04-merge-geopackage/公図と現況のずれデータ_merged.gpkg"
  if [[ -f "$ZUZA" ]]; then
    echo "=== 公図と現況のずれデータ_merged → PMTiles ==="
    ogr2ogr -skipfailures -nlt PROMOTE_TO_MULTI -dsco MINZOOM=0 -dsco MAXZOOM=15 -f "PMTiles" \
      "$OUTPUT_DIR/公図と現況のずれデータ_merged.pmtiles" "$ZUZA" "kozu_merged" 2>&1 || true
  fi
  [[ $FAILED -eq 0 ]] || true
  echo "sample done -> $OUTPUT_DIR"
}

run_14jyo() {
  local INPUT_14JYO="$DATA_DVD/データ/14条地図（不足あり）"
  if [[ ! -d "$INPUT_14JYO" ]]; then
    echo "Error: not found: $INPUT_14JYO" >&2
    exit 1
  fi
  local OUTPUT_DIR="$REPO_ROOT/data/05-pmtiles"
  mkdir -p "$OUTPUT_DIR"
  local MERGE_GPKG="$OUTPUT_DIR/14条地図_merge.gpkg"
  local OUTPUT_PMTILES="$OUTPUT_DIR/14条地図.pmtiles"
  local LAYER_NAME="14条地図"
  local FORMATS
  FORMATS=$(ogrinfo --formats 2>/dev/null || true)
  for drv in GPKG PMTiles; do
    if ! echo "$FORMATS" | grep -q "$drv"; then
      echo "Error: GDAL driver '$drv' is not available." >&2
      exit 1
    fi
  done
  local SHPS=()
  while IFS= read -r -d '' f; do
    SHPS+=( "$f" )
  done < <(find "$INPUT_14JYO" -name "*.shp" -print0 | sort -z)
  local NUM_SHPS=${#SHPS[@]}
  if [[ $NUM_SHPS -eq 0 ]]; then
    echo "Error: No .shp under $INPUT_14JYO" >&2
    exit 1
  fi
  rm -f "$MERGE_GPKG"
  local T_SRS="${T_SRS:-EPSG:4326}"
  get_s_srs_for_shp() {
    local path="$1"
    if [[ "$path" =~ ([0-9]+)系 ]]; then
      local n="${BASH_REMATCH[1]}"
      if [[ "$n" -ge 1 && "$n" -le 19 ]]; then
        echo "EPSG:$((6668 + n))"
        return
      fi
    fi
    echo ""
  }
  local S_SRS0
  S_SRS0=$(get_s_srs_for_shp "${SHPS[0]}")
  if [[ -n "$S_SRS0" ]]; then
    ogr2ogr -skipfailures -s_srs "$S_SRS0" -t_srs "$T_SRS" -f GPKG -nln "$LAYER_NAME" "$MERGE_GPKG" "${SHPS[0]}" 2>&1
  else
    ogr2ogr -skipfailures -t_srs "$T_SRS" -f GPKG -nln "$LAYER_NAME" "$MERGE_GPKG" "${SHPS[0]}" 2>&1
  fi
  local i S_SRS
  for (( i=1; i<NUM_SHPS; i++ )); do
    S_SRS=$(get_s_srs_for_shp "${SHPS[$i]}")
    if [[ -n "$S_SRS" ]]; then
      ogr2ogr -skipfailures -s_srs "$S_SRS" -t_srs "$T_SRS" -update -append -nln "$LAYER_NAME" "$MERGE_GPKG" "${SHPS[$i]}" 2>&1 || true
    else
      ogr2ogr -skipfailures -t_srs "$T_SRS" -update -append -nln "$LAYER_NAME" "$MERGE_GPKG" "${SHPS[$i]}" 2>&1 || true
    fi
  done
  ogr2ogr -skipfailures -nlt PROMOTE_TO_MULTI -dsco MINZOOM=0 -dsco MAXZOOM=15 -f "PMTiles" \
    "$OUTPUT_PMTILES" "$MERGE_GPKG" "$LAYER_NAME" 2>&1 || true
  echo "14jyo done -> $OUTPUT_PMTILES"
}

run_zuza() {
  local ORIGIN_TRY=(
    "$DATA_DVD/データ_origin/公図と現況のずれデータ"
    "$DATA_DVD/データ/公図と現況のずれデータ"
  )
  local ORIGIN_ROOT=""
  for d in "${ORIGIN_TRY[@]}"; do
    if [[ -d "$d" ]]; then ORIGIN_ROOT="$d"; break; fi
  done
  if [[ -z "$ORIGIN_ROOT" ]]; then
    echo "Error: 公図と現況のずれデータ が見つかりません" >&2
    exit 1
  fi
  local OUTPUT_BASE="${OUTPUT_BASE:-$REPO_ROOT/data/03-geopackage/shp2geopackage/zuza-work}"
  local DIR_MERGE_BEFORE="$OUTPUT_BASE/geopackage_マージ前"
  local DIR_MERGE_AFTER="$OUTPUT_BASE/geopackage_マージ後"
  local DIR_PMTILES="$OUTPUT_BASE/PMTiles"
  local LAYER_NAME="kozu_merged"
  local T_SRS="${T_SRS:-EPSG:4326}"
  local FORMATS
  FORMATS=$(ogrinfo --formats 2>/dev/null || true)
  for drv in GPKG PMTiles; do
    if ! echo "$FORMATS" | grep -q "$drv"; then
      echo "Error: GDAL driver '$drv' is not available." >&2
      exit 1
    fi
  done
  mkdir -p "$DIR_MERGE_BEFORE" "$DIR_MERGE_AFTER" "$DIR_PMTILES"
  local KEI_LIST=()
  local k
  for k in 01 02 03 04 05 06 07 08 09 10 11 12 13 14 15; do
    [[ -d "$ORIGIN_ROOT/$k" ]] && KEI_LIST+=( "$k" )
  done
  for k in "${KEI_LIST[@]}"; do
    local n=$((10#$k))
    local s_srs="EPSG:$((6668 + n))"
    local out_gpkg="$DIR_MERGE_BEFORE/${k}.gpkg"
    local vrt="$DIR_MERGE_BEFORE/${k}.vrt"
    rm -f "$out_gpkg" "$vrt"
    local shps=()
    while IFS= read -r -d '' f; do
      shps+=( "$f" )
    done < <(find "$ORIGIN_ROOT/$k" -path "*/公図/*" -name "*.shp" -print0 | sort -z)
    local num=${#shps[@]}
    [[ $num -eq 0 ]] && continue
    {
      echo '<OGRVRTDataSource>'
      echo '  <OGRVRTUnionLayer name="'"$LAYER_NAME"'">'
      local idx=0 shp base
      for shp in "${shps[@]}"; do
        base=$(basename "$shp" .shp)
        idx=$((idx + 1))
        echo '    <OGRVRTLayer name="layer_'"$idx"'">'
        echo '      <SrcDataSource><![CDATA['"$shp"']]></SrcDataSource>'
        echo '      <SrcLayer>'"$base"'</SrcLayer>'
        echo '      <LayerSRS>'"$s_srs"'</LayerSRS>'
        echo '      <OpenOptions><OOI key="ENCODING">CP932</OOI></OpenOptions>'
        echo '    </OGRVRTLayer>'
      done
      echo '  </OGRVRTUnionLayer>'
      echo '</OGRVRTDataSource>'
    } > "$vrt"
    if ! ogr2ogr -skipfailures -t_srs "$T_SRS" -f GPKG -nln "$LAYER_NAME" "$out_gpkg" "$vrt" 2>&1; then
      rm -f "$out_gpkg" "$vrt"
      continue
    fi
    rm -f "$vrt"
  done
  local MERGE_GPKG="$DIR_MERGE_AFTER/公図と現況のずれデータ_merged.gpkg"
  rm -f "$MERGE_GPKG"
  local first=1
  for k in "${KEI_LIST[@]}"; do
    local src="$DIR_MERGE_BEFORE/${k}.gpkg"
    [[ ! -f "$src" ]] && continue
    if [[ $first -eq 1 ]]; then
      ogr2ogr -skipfailures -f GPKG -nln "$LAYER_NAME" "$MERGE_GPKG" "$src" "$LAYER_NAME" 2>&1 || true
      first=0
    else
      ogr2ogr -skipfailures -update -append -nln "$LAYER_NAME" "$MERGE_GPKG" "$src" "$LAYER_NAME" 2>&1 || true
    fi
  done
  [[ -f "$MERGE_GPKG" ]] || { echo "Error: merge gpkg missing" >&2; exit 1; }
  local OUTPUT_PMTILES="$DIR_PMTILES/公図と現況のずれデータ_merged.pmtiles"
  ogr2ogr -skipfailures -nlt PROMOTE_TO_MULTI -dsco MINZOOM=0 -dsco MAXZOOM=15 -f "PMTiles" \
    "$OUTPUT_PMTILES" "$MERGE_GPKG" "$LAYER_NAME" 2>&1 || true
  echo "zuza done -> $OUTPUT_PMTILES"
}

MODE="${1:-all}"
case "$MODE" in
  sample) run_sample ;;
  14jyo) run_14jyo ;;
  zuza) run_zuza ;;
  all)
    run_sample
    run_14jyo
    run_zuza
    ;;
  *)
    echo "Usage: $0 [sample|14jyo|zuza|all]" >&2
    exit 1
    ;;
esac
