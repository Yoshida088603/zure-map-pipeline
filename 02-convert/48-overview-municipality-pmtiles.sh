#!/usr/bin/env bash
# 市区町村境界に has_data（系別ずれ GPKG と空間交差するか）を付与し、
# data/05-pmtiles/zuremap/overview.pmtiles を生成する（45 を呼び出す）。
#
# detail PMTiles（47 出力の NN.pmtiles）は入力に使わない。geopackage_per_kei の GPKG のみ。
#
# レイヤ名の確認（境界・系が想定と違うとき）:
#   ogrinfo -so <境界.gpkg> <レイヤ名>
#   ogrinfo -so <系NN.gpkg> kozu_merged
#
# 使い方（リポジトリルートで）:
#   bash 02-convert/48-overview-municipality-pmtiles.sh /path/to/municipality.shp
#   bash 02-convert/48-overview-municipality-pmtiles.sh /path/to/boundary.gpkg MuniLayerName
#   bash 02-convert/48-overview-municipality-pmtiles.sh /path/to/boundary.shp /path/to/geopackage_per_kei
#
# 【検図・パイプライン確認用】市区町データが無くても overview を出す（外接矩形 1 ポリゴン・has_data=1）:
#   bash 02-convert/48-overview-municipality-pmtiles.sh --coverage-bbox
#   bash 02-convert/48-overview-municipality-pmtiles.sh --coverage-bbox /path/to/geopackage_per_kei
#   ※ 各系 GPKG の ogrinfo Extent だけを集約（全国マージはしない）。本番の市区町塗り分けは N03 等＋通常モード。
#
# 環境変数:
#   GPKG_PER_KEI_DIR … 第2引数が geopackage_per_kei ディレクトリでないときの入力（既定: data/03-geopackage/shp2geopackage/geopackage_per_kei）
#   OVERVIEW_BOUNDARY_LAYER … 境界が GPKG で複数レイヤのときレイヤ名（第2引数が .gpkg レイヤ名として解釈される場合あり）
#   OVERVIEW_MUNI_GEOM / OVERVIEW_PARCEL_GEOM … SpatiaLite ST_Intersects 用ジオメトリ列名（空なら ogrinfo で推定）
#   OVERVIEW_PARCEL_SRID … 系 kozu_merged の EPSG コード（例: 6668）。空なら先頭系 GPKG を ogrinfo で推定。
#     境界は 4326 に正規化済みのため、系だけ JGD2011 等のときは ST_Transform(...,4326) で交差する（推定ミス時は手動指定）
#   OVERVIEW_MUNI_KEY_COLUMN … 境界レイヤ上のフィーチャ識別子（既定: fid）。別版 N03 では N03_001 等に変更可（複合キーは連結列を用意してから指定）
#   OVERVIEW_PMTILES_MINZOOM / OVERVIEW_PMTILES_MAXZOOM … 既定 0 / 8（45 に渡す）
#   OVERVIEW_KEEP_INTERMEDIATE … 1 で中間 GPKG を削除しない
#   OVERVIEW_FULL_MERGE … 1 のとき従来の「全系 kozu_merged を 1 GPKG にマージ＋ EXISTS 一括」経路（比較・切り戻し用。I/O 重い）
#   GDAL_ENV_SH … 45 と同様
#
# SpatiaLite: -dialect SQLITE の ST_Intersects には libspatialite 付き GDAL が必要。
#   MapLibre HandsOn の gdal-full（libspatialite-dev → build_gdal_full.sh）と
#   scripts/check_gdal_capabilities.sh を参照。
#
# 実装メモ: SpatiaLite は ATTACH した別 GPKG 上のジオメトリを GPB 生 BLOB のまま扱い
#   ST_Intersects が常に偽になり得る（同一ファイル内のテーブル同士なら問題になりにくい）。
#   そのため per-kei は「境界 GPKG のコピー＋当系を kozu_one として append」してから SQL する。
#
# 仕様・ゲート位置: docs/overview-municipality-pmtiles.md

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
export LANG=C.UTF-8
cd "$REPO_ROOT"

DEFAULT_KEI_DIR="$REPO_ROOT/data/03-geopackage/shp2geopackage/geopackage_per_kei"
DEFAULT_OUT_DIR="$REPO_ROOT/data/05-pmtiles/zuremap"
MERGE_GPKG="$REPO_ROOT/data/04-merge-geopackage/overview_build_parcels_merged.gpkg"
COMBINED_GPKG="$REPO_ROOT/data/04-merge-geopackage/overview_build_combined.gpkg"
FINAL_GPKG="$REPO_ROOT/data/04-merge-geopackage/overview_municipality.gpkg"

COVERAGE_MODE=0
BOUNDARY_IN=""
KEI_DIR="$DEFAULT_KEI_DIR"

if [[ "${1:-}" == "--coverage-bbox" ]]; then
  COVERAGE_MODE=1
  if [[ -n "${2:-}" && -d "$2" ]]; then
    KEI_DIR="$2"
  fi
else
  BOUNDARY_IN="${1:-}"
  if [[ -z "$BOUNDARY_IN" ]]; then
    echo "Usage: bash 02-convert/48-overview-municipality-pmtiles.sh <境界ファイル> [geopackage_per_kei | GPKGレイヤ名]" >&2
    echo "   or: bash 02-convert/48-overview-municipality-pmtiles.sh --coverage-bbox [geopackage_per_kei]" >&2
    echo "  --coverage-bbox … 境界データ不要。系別 GPKG の範囲を集約した外接矩形 1 件で overview を生成（検図用・マージなし）。" >&2
    exit 1
  fi
  if [[ ! -e "$BOUNDARY_IN" ]]; then
    echo "Error: 境界パスがありません: $BOUNDARY_IN" >&2
    exit 1
  fi
  if [[ -n "${2:-}" ]]; then
    if [[ -d "$2" ]]; then
      KEI_DIR="$2"
    elif [[ -f "$BOUNDARY_IN" && "$BOUNDARY_IN" == *.gpkg && -z "${OVERVIEW_BOUNDARY_LAYER:-}" ]]; then
      export OVERVIEW_BOUNDARY_LAYER="$2"
    fi
  fi
fi

KEI_DIR="${GPKG_PER_KEI_DIR:-$KEI_DIR}"
KEI_DIR="$(cd "$KEI_DIR" && pwd)"

zure_try_source_gdal_env() {
  command -v ogr2ogr &>/dev/null && return 0
  local env_sh
  local cands=()
  [[ -n "${GDAL_ENV_SH:-}" ]] && cands+=( "$GDAL_ENV_SH" )
  cands+=( "$REPO_ROOT/../maplibre/MapLibre-HandsOn-Beginner/05_ポリゴン表示/gdal-full/env.sh" )
  for env_sh in "${cands[@]}"; do
    [[ -z "$env_sh" || ! -f "$env_sh" ]] && continue
    # shellcheck source=/dev/null
    source "$env_sh"
    if command -v ogr2ogr &>/dev/null; then
      echo "GDAL: env を読み込みました ($env_sh)" >&2
      return 0
    fi
  done
  return 1
}

zure_try_source_gdal_env || true

for cmd in ogr2ogr ogrinfo; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "Error: $cmd が PATH にありません。" >&2
    exit 1
  fi
done

read_geom_col() {
  local ds="$1" lyr="$2"
  ogrinfo -so "$ds" "$lyr" 2>/dev/null | sed -n 's/^Geometry Column Name: //p' | head -1 | tr -d '\r'
}

# SQLite 識別子を二重引用符で囲む
zure_sql_quote_ident() {
  printf '"%s"' "${1//\"/\"\"}"
}

# ogrinfo の SRS 表示から最初の EPSG コードを取り出す（失敗時は空）
zure_read_epsg_from_ogrinfo() {
  local out m
  out=$(ogrinfo -so "$1" "$2" 2>/dev/null | tr -d '\r') || true
  m=$(echo "$out" | grep -oE 'ID\["EPSG",[0-9]+\]' | head -1 | grep -oE '[0-9]+' || true)
  [[ -n "$m" ]] && echo "$m" && return 0
  m=$(echo "$out" | grep -oE 'AUTHORITY\["EPSG","[0-9]+"\]' | head -1 | grep -oE '[0-9]+' || true)
  [[ -n "$m" ]] && echo "$m" && return 0
  echo ""
}

# stderr に ST_Intersects 未定義があれば gdal-full 再ビルドを案内
zure_hint_if_missing_spatialite() {
  local errfile="$1"
  [[ -f "$errfile" ]] || return 0
  grep -qi 'no such function: ST_Intersects' "$errfile" 2>/dev/null || return 0
  echo "  （SpatiaLite 未リンクの GDAL です。次を実施してください）" >&2
  echo "    sudo apt install libspatialite-dev" >&2
  echo "    <gdal-full>/rm -rf gdal-build && ./build_gdal_full.sh" >&2
  echo "    source <gdal-full>/env.sh && ./scripts/check_gdal_capabilities.sh" >&2
  echo "  手順・パス: リポジトリの maplibre/MapLibre-HandsOn-Beginner/05_ポリゴン表示/gdal-full/README.md" >&2
}

mkdir -p "$REPO_ROOT/data/04-merge-geopackage"
mkdir -p "$DEFAULT_OUT_DIR"

WORK_TAG="$$"
BOUNDARY_WORK="$REPO_ROOT/data/04-merge-geopackage/overview_boundary_work_${WORK_TAG}.gpkg"
HITS_RAW="$REPO_ROOT/data/04-merge-geopackage/overview_per_kei_hits_raw_${WORK_TAG}.txt"
HITS_SORTED="$REPO_ROOT/data/04-merge-geopackage/overview_per_kei_hits_sorted_${WORK_TAG}.txt"
HIT_KEYS_GPKG="$REPO_ROOT/data/04-merge-geopackage/overview_hit_keys_${WORK_TAG}.gpkg"
HITS_CSV="$REPO_ROOT/data/04-merge-geopackage/overview_hit_keys_${WORK_TAG}.csv"
COMBO_GPKG="$REPO_ROOT/data/04-merge-geopackage/overview_combo_kei_${WORK_TAG}.gpkg"
JOIN_WORK_GPKG="$REPO_ROOT/data/04-merge-geopackage/overview_join_work_${WORK_TAG}.gpkg"

rm -f "$MERGE_GPKG" "$COMBINED_GPKG" "$FINAL_GPKG" \
  "$BOUNDARY_WORK" "$HITS_RAW" "$HITS_SORTED" "$HIT_KEYS_GPKG" "$HITS_CSV" \
  "$COMBO_GPKG" "$JOIN_WORK_GPKG"

cleanup_48_exit() {
  [[ "${OVERVIEW_KEEP_INTERMEDIATE:-0}" == "1" ]] && return 0
  rm -f "$MERGE_GPKG" "$COMBINED_GPKG" \
    "$BOUNDARY_WORK" "$HITS_RAW" "$HITS_SORTED" "$HIT_KEYS_GPKG" "$HITS_CSV" \
    "$COMBO_GPKG" "$JOIN_WORK_GPKG"
}
trap 'cleanup_48_exit' EXIT

shopt -s nullglob
gpkgs=( "$KEI_DIR"/*.gpkg )
shopt -u nullglob
if [[ ${#gpkgs[@]} -eq 0 ]]; then
  echo "Error: $KEI_DIR に .gpkg がありません（20 zure の geopackage_per_kei を指定してください）" >&2
  exit 1
fi

IFS=$'\n' gpkgs_sorted=( $(printf '%s\n' "${gpkgs[@]}" | sort -V) )
unset IFS

if [[ "$COVERAGE_MODE" == 1 ]]; then
  echo "=== 48: --coverage-bbox（各系 kozu_merged の ogrinfo Extent を集約・全国マージなし）==="
  EXT_TMP="${TMPDIR:-/tmp}/48_kei_extents_$$.txt"
  rm -f "$EXT_TMP"
  for g in "${gpkgs_sorted[@]}"; do
    line=$(ogrinfo -so "$g" kozu_merged 2>/dev/null | grep '^Extent:' | head -1 || true)
    [[ -z "$line" ]] && continue
    if [[ "$line" =~ Extent:\ \(([-0-9.eE+]+),\ ([-0-9.eE+]+)\)\ -\ \(([-0-9.eE+]+),\ ([-0-9.eE+]+)\) ]]; then
      echo "${BASH_REMATCH[1]} ${BASH_REMATCH[2]} ${BASH_REMATCH[3]} ${BASH_REMATCH[4]}" >> "$EXT_TMP"
    fi
  done
  if [[ ! -s "$EXT_TMP" ]]; then
    echo "Error: いずれの GPKG からも Extent を取得できませんでした（レイヤ kozu_merged）" >&2
    rm -f "$EXT_TMP"
    exit 1
  fi
  read -r GXMIN GYMIN GXMAX GYMAX < <(awk 'BEGIN{mnX=1e308;mnY=1e308;mxX=-1e308;mxY=-1e308} NF==4 { if($1+0<mnX)mnX=$1+0; if($2+0<mnY)mnY=$2+0; if($3+0>mxX)mxX=$3+0; if($4+0>mxY)mxY=$4+0 } END{ printf "%.10f %.10f %.10f %.10f\n", mnX, mnY, mxX, mxY }' "$EXT_TMP")
  rm -f "$EXT_TMP"
  GEOJSON_TMP="${TMPDIR:-/tmp}/48_overview_bbox_$$.geojson"
  printf '%s\n' "{\"type\":\"FeatureCollection\",\"features\":[{\"type\":\"Feature\",\"properties\":{\"has_data\":1},\"geometry\":{\"type\":\"Polygon\",\"coordinates\":[[[${GXMIN},${GYMIN}],[${GXMAX},${GYMIN}],[${GXMAX},${GYMAX}],[${GXMIN},${GYMAX}],[${GXMIN},${GYMIN}]]]}}]}" > "$GEOJSON_TMP"
  ogr2ogr -skipfailures -f GPKG "$FINAL_GPKG" "$GEOJSON_TMP" -nln overview_municipality
  rm -f "$GEOJSON_TMP"
  echo "外接矩形 (WGS84): $GXMIN $GYMIN .. $GXMAX $GYMAX"
elif [[ "${OVERVIEW_FULL_MERGE:-0}" == "1" ]]; then
  echo "=== 48: OVERVIEW_FULL_MERGE=1 — 系別 GPKG を 1 本にマージ（レイヤ kozu_merged）==="
  first=1
  for g in "${gpkgs_sorted[@]}"; do
    if [[ "$first" == 1 ]]; then
      ogr2ogr -skipfailures -f GPKG "$MERGE_GPKG" "$g" kozu_merged -nln kozu_merged -nlt PROMOTE_TO_MULTI
      first=0
    else
      ogr2ogr -skipfailures -update -append -nlt PROMOTE_TO_MULTI "$MERGE_GPKG" "$g" kozu_merged -nln kozu_merged
    fi
  done
  echo "マージ済み: $MERGE_GPKG (${#gpkgs_sorted[@]} ファイル)"
else
  echo "=== 48: per-kei 交差（全系マージなし。各系ごとに N03×kozu_merged で ST_Intersects、キーの和集合）==="
  echo "=== 48: 境界を作業用 GPKG に取り込み（EPSG:4326・レイヤ muni_boundary）==="
  if [[ -n "${OVERVIEW_BOUNDARY_LAYER:-}" ]]; then
    ogr2ogr -skipfailures -f GPKG "$BOUNDARY_WORK" "$BOUNDARY_IN" "$OVERVIEW_BOUNDARY_LAYER" -nln muni_boundary -t_srs EPSG:4326
  else
    ogr2ogr -skipfailures -f GPKG "$BOUNDARY_WORK" "$BOUNDARY_IN" -nln muni_boundary -t_srs EPSG:4326
  fi

  KEY_COL="${OVERVIEW_MUNI_KEY_COLUMN:-fid}"
  if ! [[ "$KEY_COL" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
    echo "Error: OVERVIEW_MUNI_KEY_COLUMN が不正です（英数字と _ の識別子のみ）: $KEY_COL" >&2
    exit 1
  fi

  MG="${OVERVIEW_MUNI_GEOM:-$(read_geom_col "$BOUNDARY_WORK" muni_boundary)}"
  PG="${OVERVIEW_PARCEL_GEOM:-$(read_geom_col "${gpkgs_sorted[0]}" kozu_merged)}"
  [[ -z "$MG" ]] && MG=geom
  [[ -z "$PG" ]] && PG=geom
  if ! [[ "$MG" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ && "$PG" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
    echo "Error: ジオメトリ列名が不正です (OVERVIEW_MUNI_GEOM / OVERVIEW_PARCEL_GEOM)" >&2
    exit 1
  fi

  KEY_Q="$(zure_sql_quote_ident "$KEY_COL")"
  MG_Q="$(zure_sql_quote_ident "$MG")"
  PG_Q="$(zure_sql_quote_ident "$PG")"

  PARCEL_SRID="${OVERVIEW_PARCEL_SRID:-$(zure_read_epsg_from_ogrinfo "${gpkgs_sorted[0]}" kozu_merged)}"
  [[ -z "$PARCEL_SRID" ]] && PARCEL_SRID=4326
  if [[ "$PARCEL_SRID" == "4326" ]]; then
    INTERSECT_PRED="ST_Intersects(m.${MG_Q}, p.${PG_Q})"
  else
    INTERSECT_PRED="ST_Intersects(m.${MG_Q}, ST_Transform(p.${PG_Q}, 4326))"
  fi
  echo "=== 48: 系 kozu_merged の EPSG: ${PARCEL_SRID}（境界は 4326。4326 以外では parcel 側を Transform）==="

  echo "=== 48: 各系ごとに境界 GPKG のコピーへ kozu_one を append し、同一 DB 上で ST_Intersects（ATTACH は使わない）==="
  : > "$HITS_RAW"
  sql_kei="SELECT DISTINCT m.${KEY_Q} AS mk FROM muni_boundary m, kozu_one p WHERE ${INTERSECT_PRED}"
  for g in "${gpkgs_sorted[@]}"; do
    g_abs="$(cd "$(dirname "$g")" && pwd)/$(basename "$g")"
    rm -f "$COMBO_GPKG"
    cp -f "$BOUNDARY_WORK" "$COMBO_GPKG"
    ogr2ogr -skipfailures -update -append -nlt PROMOTE_TO_MULTI "$COMBO_GPKG" "$g_abs" kozu_merged -nln kozu_one
    errf="${TMPDIR:-/tmp}/48_per_kei_sql_${WORK_TAG}.err"
    if ! ogr2ogr -f CSV /vsistdout/ "$COMBO_GPKG" -dialect SQLITE -sql "$sql_kei" 2>"$errf" | tail -n +2 >> "$HITS_RAW"; then
      echo "Error: 系 GPKG との交差クエリに失敗しました: $g_abs" >&2
      echo "  レイヤ kozu_merged・ジオメトリ列・SpatiaLite を確認してください。" >&2
      cat "$errf" >&2 || true
      zure_hint_if_missing_spatialite "$errf"
      rm -f "$errf" "$COMBO_GPKG"
      exit 1
    fi
    rm -f "$errf" "$COMBO_GPKG"
  done

  sort -u "$HITS_RAW" > "$HITS_SORTED"

  echo "=== 48: 交差キー → hit_keys GPKG（件数: $(wc -l < "$HITS_SORTED" | tr -d ' ')）==="
  {
    echo mk
    cat "$HITS_SORTED"
  } > "$HITS_CSV"
  rm -f "$HIT_KEYS_GPKG"
  ogr2ogr -skipfailures -overwrite -f GPKG "$HIT_KEYS_GPKG" "$HITS_CSV" -nln hit_keys -oo AUTODETECT_TYPE=YES -oo EMPTY_STRING_AS_NULL=YES

  MK_Q="$(zure_sql_quote_ident mk)"
  rm -f "$JOIN_WORK_GPKG"
  cp -f "$BOUNDARY_WORK" "$JOIN_WORK_GPKG"
  ogr2ogr -skipfailures -update -append "$JOIN_WORK_GPKG" "$HIT_KEYS_GPKG" hit_keys -nln hit_keys
  sql_final="SELECT b.*, CASE WHEN h.${MK_Q} IS NOT NULL THEN 1 ELSE 0 END AS has_data FROM muni_boundary b LEFT JOIN hit_keys h ON b.${KEY_Q} = h.${MK_Q}"

  echo "=== 48: has_data 付与（境界＋hit_keys を同一 GPKG に集約して LEFT JOIN / SQLITE dialect）==="
  # -skipfailures はジオメトリ異常で全件落ちし空／不正 GPKG になり得るため付けない
  if ! ogr2ogr -f GPKG "$FINAL_GPKG" "$JOIN_WORK_GPKG" -nln overview_municipality -nlt PROMOTE_TO_MULTI \
    -dialect SQLITE -sql "$sql_final" 2>"/tmp/48_overview_sql_${WORK_TAG}.err"; then
    echo "Error: has_data 付与に失敗しました（GDAL の SQLITE dialect / SpatiaLite が無効な可能性）。" >&2
    cat "/tmp/48_overview_sql_${WORK_TAG}.err" >&2 || true
    zure_hint_if_missing_spatialite "/tmp/48_overview_sql_${WORK_TAG}.err"
    rm -f "/tmp/48_overview_sql_${WORK_TAG}.err"
    exit 1
  fi
  rm -f "/tmp/48_overview_sql_${WORK_TAG}.err"
  if [[ ! -s "$FINAL_GPKG" ]]; then
    echo "Error: overview_municipality.gpkg が空です（LEFT JOIN 結果の書き出しに失敗した可能性）。" >&2
    exit 1
  fi
  if ! ogrinfo -so "$FINAL_GPKG" overview_municipality >/dev/null 2>&1; then
    echo "Error: 出力 GPKG を ogrinfo で開けません。45 に渡す前に破損しています。OVERVIEW_KEEP_INTERMEDIATE=1 で中間を残して調査してください。" >&2
    exit 1
  fi
  rm -f "$JOIN_WORK_GPKG"
fi

if [[ "$COVERAGE_MODE" != "1" && "${OVERVIEW_FULL_MERGE:-0}" == "1" ]]; then
  echo "=== 48: 境界を GPKG に取り込み（EPSG:4326）— FULL_MERGE 経路 ==="
  if [[ -n "${OVERVIEW_BOUNDARY_LAYER:-}" ]]; then
    ogr2ogr -skipfailures -f GPKG "$COMBINED_GPKG" "$BOUNDARY_IN" "$OVERVIEW_BOUNDARY_LAYER" -nln muni_boundary -t_srs EPSG:4326
  else
    ogr2ogr -skipfailures -f GPKG "$COMBINED_GPKG" "$BOUNDARY_IN" -nln muni_boundary -t_srs EPSG:4326
  fi

  echo "=== 48: ずれポリゴンを同一 GPKG に追加（kozu_parcels）— FULL_MERGE 経路 ==="
  ogr2ogr -skipfailures -update -append "$COMBINED_GPKG" "$MERGE_GPKG" kozu_merged -nln kozu_parcels

  MG="${OVERVIEW_MUNI_GEOM:-$(read_geom_col "$COMBINED_GPKG" muni_boundary)}"
  PG="${OVERVIEW_PARCEL_GEOM:-$(read_geom_col "$COMBINED_GPKG" kozu_parcels)}"
  [[ -z "$MG" ]] && MG=geom
  [[ -z "$PG" ]] && PG=geom
  if ! [[ "$MG" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ && "$PG" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
    echo "Error: ジオメトリ列名が不正です (OVERVIEW_MUNI_GEOM / OVERVIEW_PARCEL_GEOM)" >&2
    exit 1
  fi

  echo "=== 48: has_data 付与（SpatiaLite / EXISTS）— FULL_MERGE 経路 ==="
  echo "  muni_boundary.$MG × kozu_parcels.$PG で ST_Intersects"
  SQL="SELECT m.*, CASE WHEN EXISTS (SELECT 1 FROM kozu_parcels k WHERE ST_Intersects(m.${MG}, k.${PG})) THEN 1 ELSE 0 END AS has_data FROM muni_boundary m"
  if ! ogr2ogr -skipfailures -f GPKG "$FINAL_GPKG" "$COMBINED_GPKG" -nln overview_municipality -dialect SQLITE -sql "$SQL" 2>"/tmp/48_overview_sql_${WORK_TAG}.err"; then
    echo "Error: has_data 付与に失敗しました（GDAL の SQLITE dialect / SpatiaLite が無効な可能性）。" >&2
    cat "/tmp/48_overview_sql_${WORK_TAG}.err" >&2 || true
    zure_hint_if_missing_spatialite "/tmp/48_overview_sql_${WORK_TAG}.err"
    rm -f "/tmp/48_overview_sql_${WORK_TAG}.err"
    exit 1
  fi
  rm -f "/tmp/48_overview_sql_${WORK_TAG}.err"
fi

if [[ "${OVERVIEW_KEEP_INTERMEDIATE:-0}" != "1" ]]; then
  rm -f "$MERGE_GPKG" "$COMBINED_GPKG" "$BOUNDARY_WORK" "$HITS_RAW" "$HITS_SORTED" "$HIT_KEYS_GPKG" "$HITS_CSV" \
    "$COMBO_GPKG" "$JOIN_WORK_GPKG"
fi

echo "=== 48: PMTiles 化（45）→ $DEFAULT_OUT_DIR/overview.pmtiles ==="
export PMTILES_MINZOOM="${OVERVIEW_PMTILES_MINZOOM:-0}"
export PMTILES_MAXZOOM="${OVERVIEW_PMTILES_MAXZOOM:-8}"
export PMTILES_OUT_BASENAME=overview
if [[ -z "${GDAL_ENV_SH:-}" ]]; then
  _zure_gdal_env="$REPO_ROOT/../maplibre/MapLibre-HandsOn-Beginner/05_ポリゴン表示/gdal-full/env.sh"
  [[ -f "$_zure_gdal_env" ]] && export GDAL_ENV_SH="$_zure_gdal_env"
fi
bash "$SCRIPT_DIR/45-geopackage2pmtiles.sh" "$FINAL_GPKG" "$DEFAULT_OUT_DIR"

if [[ "${OVERVIEW_KEEP_INTERMEDIATE:-0}" != "1" ]]; then
  rm -f "$FINAL_GPKG"
fi

echo "Done. overview.pmtiles を出力しました（MVT レイヤ名: overview_municipality）。"
if [[ "$COVERAGE_MODE" == 1 ]]; then
  echo "（--coverage-bbox: 市区町境界ではなくデータ全体の外接矩形のみ）" >&2
fi
if [[ "${OVERVIEW_FULL_MERGE:-0}" == "1" && "$COVERAGE_MODE" != "1" ]]; then
  echo "（OVERVIEW_FULL_MERGE=1: 全系マージ＋EXISTS 経路を使用）" >&2
fi
