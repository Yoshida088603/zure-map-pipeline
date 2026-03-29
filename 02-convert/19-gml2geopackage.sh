#!/usr/bin/env bash
# 国土数値情報 N03 行政区域 GML（ZIP）を raw に複製・展開し、gdal-full の ogr2ogr で
# 全 GML を 1 本の GeoPackage にマージする。
#
# 使い方（リポジトリルートで）:
#   bash 02-convert/19-gml2geopackage.sh [ZIPパス]
# 環境変数:
#   N03_ZIP_SOURCE   入力 ZIP（第1引数が優先）
#   N03_GPKG_NAME    出力 .gpkg のファイル名のみ（例: foo.gpkg）。未設定時は ZIP 名から生成
#   N03_LAYER_NAME   GPKG 内レイヤ名（既定: N03）
#   GDAL_ENV_SH      gdal-full の env.sh を明示
#   OGR2OGR_NO_MAKEVALID=1  で -makevalid を付けない（トラブル時）
#   VERIFY_GPKG_COUNT=0     で入力件数と出力件数の照合を省略
#   N03_FORCE_SHP=1          で .xml/.gml を使わず同梱 .shp のみ変換（明示運用）
#
# 前提: 複製先 data/01-raw-data/行政区域ポリゴン・出力先 data/03-geopackage/gml2geopackage が既に存在すること。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RAW_DIR="$REPO_ROOT/data/01-raw-data/行政区域ポリゴン"
GPKG_DIR="$REPO_ROOT/data/03-geopackage/gml2geopackage"
export LANG=C.UTF-8
cd "$REPO_ROOT"

DEFAULT_ZIP="/mnt/c/Users/shiro/Downloads/N03-20250101_GML.zip"
ZIP_SRC="${1:-${N03_ZIP_SOURCE:-$DEFAULT_ZIP}}"

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
    echo "Error: $cmd が PATH にありません。GDAL_ENV_SH または HandsOn の gdal-full/env.sh を参照してください。" >&2
    exit 1
  fi
done

if [[ ! -d "$RAW_DIR" ]]; then
  echo "Error: 複製先がありません: $RAW_DIR" >&2
  exit 1
fi
if [[ ! -d "$GPKG_DIR" ]]; then
  echo "Error: 出力先がありません: $GPKG_DIR" >&2
  exit 1
fi

if [[ ! -f "$ZIP_SRC" ]]; then
  echo "Error: ZIP が見つかりません: $ZIP_SRC" >&2
  echo "  第1引数または N03_ZIP_SOURCE でパスを指定してください。" >&2
  exit 1
fi

ZIP_BASENAME="$(basename "$ZIP_SRC")"
DEST_ZIP="$RAW_DIR/$ZIP_BASENAME"

echo "コピー: $ZIP_SRC -> $DEST_ZIP" >&2
cp -- "$ZIP_SRC" "$DEST_ZIP"

echo "展開: $DEST_ZIP （先: $RAW_DIR）" >&2
if command -v unzip &>/dev/null; then
  unzip -o -q "$DEST_ZIP" -d "$RAW_DIR"
else
  python3 -c 'import sys, zipfile; z=zipfile.ZipFile(sys.argv[1]); z.extractall(sys.argv[2])' "$DEST_ZIP" "$RAW_DIR"
fi

# ベクタソース一覧: .gml に加え、国土数値情報 JPGIS は主データが .xml（例: N03-20250101.xml）
# KS-META-*.xml はメタデータのみのため除外
mapfile -t GML_FILES < <(
  find "$RAW_DIR" -type f \( -iname '*.gml' -o \( -iname '*.xml' ! -iname 'KS-META*' \) \) ! -path '*/.*' | LC_ALL=C sort
)
if [[ ${#GML_FILES[@]} -eq 0 ]]; then
  echo "Error: $RAW_DIR 配下に .gml / 対象 .xml が見つかりません（展開失敗または別構成の ZIP の可能性）。" >&2
  exit 1
fi

if [[ "${N03_FORCE_SHP:-0}" == "1" ]]; then
  mapfile -t GML_FILES < <(find "$RAW_DIR" -type f -iname '*.shp' ! -path '*/.*' | LC_ALL=C sort)
  if [[ ${#GML_FILES[@]} -eq 0 ]]; then
    echo "Error: N03_FORCE_SHP=1 ですが $RAW_DIR に .shp がありません。" >&2
    exit 1
  fi
  echo "N03_FORCE_SHP: Shapefile のみ使用 (${#GML_FILES[@]} 件)" >&2
fi

# JPGIS の行政区域 .xml は GML ドライバではジオメトリが None（属性のみ）になることがある。
# 国土数値情報の同一 ZIP に同梱の .shp がある場合はそちらでポリゴンを取り込む。
ogr_first_layer_geometry() {
  local f="$1" lyr geom
  lyr=$(ogrinfo -q "$f" 2>/dev/null | head -1 | sed -E 's/^[0-9]+: ([^ ]+) .*/\1/')
  [[ -z "$lyr" ]] && { echo "NONE"; return; }
  geom=$(ogrinfo -so "$f" "$lyr" 2>/dev/null | grep '^Geometry:' || true)
  echo "${geom#Geometry: }"
}

if [[ "${N03_FORCE_SHP:-0}" != "1" ]]; then
  _g="$(ogr_first_layer_geometry "${GML_FILES[0]}")"
  if [[ "$_g" == *None* ]] || [[ -z "$_g" ]]; then
    mapfile -t SHP_CANDS < <(find "$RAW_DIR" -type f -iname '*.shp' ! -path '*/.*' | LC_ALL=C sort)
    if [[ ${#SHP_CANDS[@]} -eq 0 ]]; then
      echo "Error: 先頭ソースのジオメトリが None で、フォールバック用の .shp も見つかりません: ${GML_FILES[0]}" >&2
      exit 1
    fi
    echo "注意: JPGIS .xml は OGR ではジオメトリを持たないため、同梱の Shapefile (${#SHP_CANDS[@]} 件) を変換します。" >&2
    GML_FILES=("${SHP_CANDS[@]}")
  fi
fi

echo "変換ソースファイル数: ${#GML_FILES[@]}" >&2

# 出力 GPKG 名
if [[ -n "${N03_GPKG_NAME:-}" ]]; then
  OUT_GPKG="$GPKG_DIR/$N03_GPKG_NAME"
else
  STEM="${ZIP_BASENAME%.zip}"
  STEM="${STEM%.ZIP}"
  if [[ "$STEM" == *_GML ]]; then
    STEM="${STEM%_GML}"
  elif [[ "$STEM" == *-GML ]]; then
    STEM="${STEM%-GML}"
  fi
  OUT_GPKG="$GPKG_DIR/${STEM}_行政区域.gpkg"
fi

LAYER_NAME="${N03_LAYER_NAME:-N03}"

OGR2OGR_MV=()
if [[ "${OGR2OGR_NO_MAKEVALID:-0}" != "1" ]]; then
  OGR2OGR_MV=( -makevalid )
fi

OGR_EXTRA=( -nlt PROMOTE_TO_MULTI )

rm -f "$OUT_GPKG"

FIRST="${GML_FILES[0]}"
echo "1/ 作成: $OUT_GPKG <- $(basename "$FIRST") (layer=$LAYER_NAME)" >&2
ogr2ogr -f GPKG -nln "$LAYER_NAME" "${OGR2OGR_MV[@]}" "${OGR_EXTRA[@]}" "$OUT_GPKG" "$FIRST"

for ((i = 1; i < ${#GML_FILES[@]}; i++)); do
  f="${GML_FILES[i]}"
  echo "  append ($((i + 1))/${#GML_FILES[@]}): $(basename "$f")" >&2
  ogr2ogr -update -append -nln "$LAYER_NAME" "${OGR2OGR_MV[@]}" "${OGR_EXTRA[@]}" "$OUT_GPKG" "$f"
done

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

if [[ "${VERIFY_GPKG_COUNT:-1}" != "0" ]]; then
  sum_in=0
  for f in "${GML_FILES[@]}"; do
    fc=$(sum_ogrjson_feature_count "$f")
    sum_in=$((sum_in + fc))
  done
  sum_out=$(sum_ogrjson_feature_count "$OUT_GPKG" "$LAYER_NAME")
  echo "件数: 入力ソース合計=$sum_in / GPKG レイヤ $LAYER_NAME=$sum_out" >&2
  if [[ "$sum_in" != "$sum_out" ]]; then
    echo "Error: 件数が一致しません。スキップやレイヤ構成の差の可能性があります。" >&2
    exit 1
  fi
fi

echo "完了: $OUT_GPKG" >&2
ogrinfo -json "$OUT_GPKG" "$LAYER_NAME" 2>/dev/null | head -c 800 || true
echo >&2
