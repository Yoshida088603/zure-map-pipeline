#!/usr/bin/env bash
# Shapefile → GeoPackage への変換のみ（マージ・PMTiles は行わない。後続は 40-merge / 45-geopackage2pmtiles）。
# GPKG: 件数ズレの主因は「無効ジオメトリ等でコピー失敗 → -skipfailures で黙ってスキップ」。
# 対策: ogr2ogr に -makevalid（GEOS）を付けて書き込み可能な形状に直し、GPKG へのコピーでは -skipfailures を使わない。
# 終了時に SHP 合計と GPKG の featureCount を照合し、不一致なら exit 1（原因調査のため）。
# 照合を省略する場合: VERIFY_GPKG_COUNT=0  /  MakeValid を無効にする場合: OGR2OGR_NO_MAKEVALID=1（非推奨）
# DBF 文字化けは VRT 側の OpenOptions（CP932）などで調整。
# 使い方: bash 02-convert/20-shp2geopackage.sh [sample|14jyo|zure|all]
# - sample: input の *.shp → shp2geopackage/run_sample_<TS>/ に各 .gpkg
# - 14jyo:  RAW の 14条地図 内の全 SHP → 1 GPKG（run_14jyo_<TS>/）
# - zure:   ずれまっぷ（公図と現況のずれデータ）RAW 公図 → 系ごと 1 GPKG（geopackage_per_kei/）。統合は 40-merge-geopackage.sh zure
# 市区町村のみテスト: ZURE_SHIKUCHOSON=練馬区（カンマ区切りで複数可）→ */公図/<市区町村名>/* の SHP のみ。
# 前提: PATH に ogr2ogr。GDAL のビルドは行わない。

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

# GPKG 書き込み時のジオメトリ修復（GEOS 必須。ビルドに無いと ogr2ogr が失敗する）
OGR2OGR_MV=()
if [[ "${OGR2OGR_NO_MAKEVALID:-0}" != "1" ]]; then
  OGR2OGR_MV=( -makevalid )
fi

# ogrinfo -json の featureCount 合計（第2引数でレイヤ名を指定可）
sum_ogrjson_feature_count() {
  if [[ -n "${2:-}" ]]; then
    ogrinfo -json "$1" "$2" 2>/dev/null \
      | grep -o '"featureCount":[0-9][0-9]*' \
      | sed 's/.*://' \
      | awk '{ s += $1 } END { print s + 0 }'
  else
    ogrinfo -json "$1" 2>/dev/null \
      | grep -o '"featureCount":[0-9][0-9]*' \
      | sed 's/.*://' \
      | awk '{ s += $1 } END { print s + 0 }'
  fi
}

# SHP パスの列を合算
sum_shp_paths_features() {
  local sum=0 f fc
  for f in "$@"; do
    [[ -f "$f" ]] || continue
    fc=$(sum_ogrjson_feature_count "$f")
    sum=$((sum + fc))
  done
  echo "$sum"
}

# GPKG の指定レイヤの featureCount
gpkg_layer_feature_count() {
  sum_ogrjson_feature_count "$1" "$2"
}

# 件数照合（VERIFY_GPKG_COUNT=0 でスキップ）
verify_gpkg_vs_shp() {
  local tag="$1" expected="$2" actual="$3"
  [[ "${VERIFY_GPKG_COUNT:-1}" == "0" ]] && return 0
  echo "[件数照合 ${tag}] SHP 合計=${expected}  GPKG=${actual}"
  if [[ -z "$actual" || "$expected" != "$actual" ]]; then
    echo "Error: ${tag} で GPKG のフィーチャ数が SHP と一致しません。ogr2ogr の直前ログ、または OGR2OGR_NO_MAKEVALID=1 で再現確認。" >&2
    exit 1
  fi
}

# ずれまっぷ RAW 配下の公図 *.shp を列挙（-print0）。ZURE_SHIKUCHOSON が空なら全件、指定時は */公図/<市区町村名>/* のみ（カンマ区切りで複数可）。
zure_find_shp_print0() {
  local root="$1"
  if [[ -z "${ZURE_SHIKUCHOSON:-}" ]]; then
    find "$root" -path "*/公図/*" -name "*.shp" -print0 2>/dev/null
    return
  fi
  local _raw pat=() n
  IFS=',' read -ra _raw <<< "$ZURE_SHIKUCHOSON"
  for n in "${_raw[@]}"; do
    n="${n#"${n%%[![:space:]]*}"}"
    n="${n%"${n##*[![:space:]]}"}"
    [[ -z "$n" ]] && continue
    pat+=( "*/公図/${n}/*" )
  done
  if [[ ${#pat[@]} -eq 0 ]]; then
    find "$root" -path "*/公図/*" -name "*.shp" -print0 2>/dev/null
    return
  fi
  local find_cmd=(find "$root" "(" -path "${pat[0]}")
  local i
  for (( i=1; i<${#pat[@]}; i++ )); do
    find_cmd+=( -o -path "${pat[i]}" )
  done
  find_cmd+=( ")" -name "*.shp" -print0 )
  "${find_cmd[@]}" 2>/dev/null
}

run_sample() {
  local INPUT_DIR="$REPO_ROOT/data/03-geopackage/shp2geopackage/input"
  local RUN_TS
  RUN_TS=$(TZ=Asia/Tokyo date +%Y%m%d_%H%M%S)
  local OUTPUT_DIR="$REPO_ROOT/data/03-geopackage/shp2geopackage/run_sample_${RUN_TS}"
  mkdir -p "$OUTPUT_DIR"
  local RUN_LOG="$OUTPUT_DIR/run.log"
  touch "$RUN_LOG"
  echo "[sample] SHP→GPKG のみ → $OUTPUT_DIR（ログ: run.log）" >&2
  (
    set -e
    exec > >(tee -a "$RUN_LOG") 2>&1
    echo "=== $(TZ=Asia/Tokyo date -Iseconds) sample 開始 ==="
    shopt -s nullglob
    local shps=( "$INPUT_DIR"/*.shp )
    if [[ ${#shps[@]} -eq 0 ]]; then
      echo "No .shp in $INPUT_DIR"
      exit 0
    fi
    local n=0
    for shp in "${shps[@]}"; do
      local base
      base=$(basename "$shp" .shp)
      echo "=== $base.shp → ${base}.gpkg ==="
      ogr2ogr "${OGR2OGR_MV[@]}" -t_srs "${T_SRS:-EPSG:4326}" -f GPKG -nln "$base" \
        "$OUTPUT_DIR/${base}.gpkg" "$shp" 2>&1
      n=$((n + 1))
    done
    echo "sample 完了: ${n} 件 -> $OUTPUT_DIR"
  )
}

run_14jyo() {
  local INPUT_14JYO="$DATA_DVD/データ/14条地図（不足あり）"
  if [[ ! -d "$INPUT_14JYO" ]]; then
    echo "Error: not found: $INPUT_14JYO" >&2
    exit 1
  fi
  local RUN_TS
  RUN_TS=$(TZ=Asia/Tokyo date +%Y%m%d_%H%M%S)
  local OUTPUT_DIR="${OUTPUT_DIR:-$REPO_ROOT/data/03-geopackage/shp2geopackage/run_14jyo_${RUN_TS}}"
  mkdir -p "$OUTPUT_DIR"
  local MERGE_GPKG="$OUTPUT_DIR/14条地図_merge.gpkg"
  local LAYER_NAME="14条地図"
  local FORMATS
  FORMATS=$(ogrinfo --formats 2>/dev/null || true)
  if ! echo "$FORMATS" | grep -q GPKG; then
    echo "Error: GDAL driver 'GPKG' is not available." >&2
    exit 1
  fi
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
      # JGD2011 平面直角: EPSG:6668 は地理座標。投影の n 系は EPSG:6668+n（1系=6669 … 9系=6677 … 15系=6683）
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
    ogr2ogr "${OGR2OGR_MV[@]}" -s_srs "$S_SRS0" -t_srs "$T_SRS" -f GPKG -nln "$LAYER_NAME" "$MERGE_GPKG" "${SHPS[0]}" 2>&1
  else
    ogr2ogr "${OGR2OGR_MV[@]}" -t_srs "$T_SRS" -f GPKG -nln "$LAYER_NAME" "$MERGE_GPKG" "${SHPS[0]}" 2>&1
  fi
  local i S_SRS
  for (( i=1; i<NUM_SHPS; i++ )); do
    S_SRS=$(get_s_srs_for_shp "${SHPS[$i]}")
    if [[ -n "$S_SRS" ]]; then
      ogr2ogr "${OGR2OGR_MV[@]}" -s_srs "$S_SRS" -t_srs "$T_SRS" -update -append -nln "$LAYER_NAME" "$MERGE_GPKG" "${SHPS[$i]}" 2>&1
    else
      ogr2ogr "${OGR2OGR_MV[@]}" -t_srs "$T_SRS" -update -append -nln "$LAYER_NAME" "$MERGE_GPKG" "${SHPS[$i]}" 2>&1
    fi
  done
  local exp14 act14
  exp14=$(sum_shp_paths_features "${SHPS[@]}")
  act14=$(gpkg_layer_feature_count "$MERGE_GPKG" "$LAYER_NAME")
  verify_gpkg_vs_shp "14条地図_merge.gpkg" "$exp14" "$act14"
  echo "14jyo done (GPKG のみ) -> $MERGE_GPKG"
}

run_zure() {
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
  local RUN_TS _shp2gpkg_base="$REPO_ROOT/data/03-geopackage/shp2geopackage"
  RUN_TS=$(TZ=Asia/Tokyo date +%Y%m%d_%H%M%S)
  local _tag="run_zure"
  [[ -n "${ZURE_SHIKUCHOSON:-}" ]] && _tag="run_zure_partial"
  local OUTPUT_BASE="${OUTPUT_BASE:-$_shp2gpkg_base/${_tag}_${RUN_TS}}"
  local RUN_LOG="$OUTPUT_BASE/run.log"
  mkdir -p "$OUTPUT_BASE"
  touch "$RUN_LOG"
  echo "[zure] 成果・逐次ログ: $OUTPUT_BASE/run.log" >&2
  if [[ -n "${ZURE_SHIKUCHOSON:-}" ]]; then
    echo "[zure] ZURE_SHIKUCHOSON=${ZURE_SHIKUCHOSON}（*/公図/<市区町村>/* のみ）" >&2
  fi
  (
    set -e
    exec > >(tee -a "$RUN_LOG") 2>&1
    echo "=== $(TZ=Asia/Tokyo date '+%Y-%m-%d %H:%M:%S %z') 20-shp2geopackage.sh zure 開始 ==="
    echo "ORIGIN_ROOT=$ORIGIN_ROOT"
    echo "OUTPUT_BASE=$OUTPUT_BASE"
    echo "ZURE_SHIKUCHOSON=${ZURE_SHIKUCHOSON:-}"
    echo "（系別 GPKG の全国 1 ファイルへの統合は 40-merge-geopackage.sh zure）"
    local DIR_MERGE_BEFORE="$OUTPUT_BASE/geopackage_per_kei"
    local LAYER_NAME="kozu_merged"
    local T_SRS="${T_SRS:-EPSG:4326}"
    local FORMATS
    FORMATS=$(ogrinfo --formats 2>/dev/null || true)
    if ! echo "$FORMATS" | grep -q GPKG; then
      echo "Error: GDAL driver 'GPKG' is not available." >&2
      exit 1
    fi
    mkdir -p "$DIR_MERGE_BEFORE"
    # RAW「公図と現況のずれデータ」直下の 01〜15（2桁）= 平面直角 1系〜15系（01=1系 … 15=15系）。→ 系番号 n に JGD2011 投影 EPSG:6668+n
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
      done < <(zure_find_shp_print0 "$ORIGIN_ROOT/$k" | sort -z)
      local num=${#shps[@]}
      [[ $num -eq 0 ]] && continue
      echo "--- 系 $k (${s_srs}) SHP ${num} 件 → ${out_gpkg} ---"
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
      ogr2ogr "${OGR2OGR_MV[@]}" -t_srs "$T_SRS" -f GPKG -nln "$LAYER_NAME" "$out_gpkg" "$vrt" 2>&1
      rm -f "$vrt"
      [[ -f "$out_gpkg" ]] || continue
      echo "[kei ${k}] 完了 featureCount 目安: $(gpkg_layer_feature_count "$out_gpkg" "$LAYER_NAME")"
    done
    local exp_zu act_zu fc
    exp_zu=0
    while IFS= read -r -d '' fsum; do
      [[ -f "$fsum" ]] || continue
      fc=$(sum_ogrjson_feature_count "$fsum")
      exp_zu=$((exp_zu + fc))
    done < <(zure_find_shp_print0 "$ORIGIN_ROOT")
    act_zu=0
    for k in "${KEI_LIST[@]}"; do
      local gf="$DIR_MERGE_BEFORE/${k}.gpkg"
      [[ -f "$gf" ]] || continue
      fc=$(gpkg_layer_feature_count "$gf" "$LAYER_NAME")
      act_zu=$((act_zu + fc))
    done
    verify_gpkg_vs_shp "geopackage_per_kei（系別合計）" "$exp_zu" "$act_zu"
    echo "zure 完了（GPKG のみ）-> $DIR_MERGE_BEFORE"
    echo "=== $(TZ=Asia/Tokyo date '+%Y-%m-%d %H:%M:%S %z') 終了 ==="
  )
}

MODE="${1:-all}"
case "$MODE" in
  sample) run_sample ;;
  14jyo) run_14jyo ;;
  zure) run_zure ;;
  all)
    run_sample
    run_14jyo
    run_zure
    ;;
  *)
    echo "Usage: $0 [sample|14jyo|zure|all]" >&2
    echo "  zure 用: ZURE_SHIKUCHOSON=練馬区[,区名...] OUTPUT_BASE=（省略時は shp2geopackage/run_zure_<TS>/ または run_zure_partial_<TS>/）" >&2
    exit 1
    ;;
esac
