#!/usr/bin/env bash
# GeoPackage を PMTiles に変換する（1 入力ファイル → 1 出力 .pmtiles）。
#
# 【47 との関係】47-geopackage-per-kei2pmtiles.sh は GDAL を持たず、
#   geopackage_per_kei 内の各 *.gpkg について「本スクリプトを bash で 1 回ずつ」呼ぶだけ。
#   迷ったら: 単一 GPKG なら 45 直実行 / 系別フォルダを一括なら 47。
#
# 使い方: bash 02-convert/45-geopackage2pmtiles.sh [入力.gpkg] [出力ディレクトリ]
#   第2引数省略時: 入力と同じディレクトリに .pmtiles（従来どおり）
#   第2引数あり時: そのディレクトリに <入力ベース名>.pmtiles（存在しなければ mkdir -p）
# 環境変数 PMTILES_OUT_DIR で出力先を指定してもよい（第2引数が優先）
# 環境変数 PMTILES_MINZOOM / PMTILES_MAXZOOM（既定 0 / 12。細かい縮尺は 15 等）
# 環境変数 PMTILES_OUT_BASENAME … 出力ファイル名の本体（拡張子なし）。省略時は入力 GPKG のベース名
#
# 【1 タイルあたりの件数・バイト上限】
# 本スクリプトは既定で MAX_FEATURES / MAX_SIZE を **2^31-1** に設定し、
# GDAL ドライバ既定（約 20 万件・約 500KB/タイル）による **明示的な切り捨てを避ける**。
# （メモリ・MVT 仕様・他レイヤー処理で失敗する場合は別。完全保証ではない。）
# 旧ドライバ既定に戻す: PMTILES_MAX_FEATURES=200000 PMTILES_MAX_SIZE=500000
# 任意: PMTILES_SIMPLIFICATION=0 … 単純化を弱める（タイル容量は増える）
#       PMTILES_BUFFER=128     … タイル境界のクリップ緩和
# 既定入力: data/04-merge-geopackage/土地活用推進調査_merged.gpkg
# GDAL: 基本は 20 と同じ（PATH の ogr2ogr / ogrinfo）。無いときだけ次を順に試す:
#   GDAL_ENV_SH、リポジトリ隣の MapLibre HandsOn gdal-full/env.sh（docs/plan.md の配置例）

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
export LANG=C.UTF-8
cd "$REPO_ROOT"

zure_try_source_gdal_env() {
  command -v ogr2ogr &>/dev/null && return 0
  local env_sh
  local cands=()
  [[ -n "${GDAL_ENV_SH:-}" ]] && cands+=( "$GDAL_ENV_SH" )
  cands+=(
    "$REPO_ROOT/../maplibre/MapLibre-HandsOn-Beginner/05_ポリゴン表示/gdal-full/env.sh"
    "$REPO_ROOT/../MapLibre-HandsOn-Beginner/05_ポリゴン表示/gdal-full/env.sh"
  )
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
    echo "Error: $cmd が PATH にありません。apt install gdal-bin、または GDAL_ENV_SH / HandsOn の gdal-full/env.sh を用意してください。" >&2
    exit 1
  fi
done

DEFAULT_GPKG="$REPO_ROOT/data/04-merge-geopackage/土地活用推進調査_merged.gpkg"

GPKG="${1:-$DEFAULT_GPKG}"
if [[ ! -f "$GPKG" ]]; then
  echo "Error: GeoPackage not found: $GPKG" >&2
  exit 1
fi

GPKG="$(cd "$(dirname "$GPKG")" && pwd)/$(basename "$GPKG")"
DIR="$(dirname "$GPKG")"
BASE="$(basename "$GPKG" .gpkg)"
OUT_BASE="${PMTILES_OUT_BASENAME:-$BASE}"
OUT_PARENT="${2:-${PMTILES_OUT_DIR:-}}"
if [[ -n "$OUT_PARENT" ]]; then
  mkdir -p "$OUT_PARENT"
  OUT_PARENT="$(cd "$OUT_PARENT" && pwd)"
  OUT_PMTILES="$OUT_PARENT/${OUT_BASE}.pmtiles"
  OUT_PARQUET="$OUT_PARENT/${OUT_BASE}.parquet"
else
  OUT_PMTILES="$DIR/${OUT_BASE}.pmtiles"
  OUT_PARQUET="$DIR/${OUT_BASE}.parquet"
fi

T_SRS="-t_srs EPSG:3857"
PMTILES_MINZOOM="${PMTILES_MINZOOM:-0}"
PMTILES_MAXZOOM="${PMTILES_MAXZOOM:-12}"

# 既定: ドライバの「タイル内件数・バイト」切り捨てを実質無効化（上書き可）
PMTILES_MAX_FEATURES="${PMTILES_MAX_FEATURES:-2147483647}"
PMTILES_MAX_SIZE="${PMTILES_MAX_SIZE:-2147483647}"

PMTILES_EXTRA_DSCO=(
  -dsco "MAX_FEATURES=$PMTILES_MAX_FEATURES"
  -dsco "MAX_SIZE=$PMTILES_MAX_SIZE"
)
[[ -n "${PMTILES_SIMPLIFICATION:-}" ]] && PMTILES_EXTRA_DSCO+=( -dsco "SIMPLIFICATION=$PMTILES_SIMPLIFICATION" )
[[ -n "${PMTILES_SIMPLIFICATION_MAX_ZOOM:-}" ]] && PMTILES_EXTRA_DSCO+=( -dsco "SIMPLIFICATION_MAX_ZOOM=$PMTILES_SIMPLIFICATION_MAX_ZOOM" )
[[ -n "${PMTILES_BUFFER:-}" ]] && PMTILES_EXTRA_DSCO+=( -dsco "BUFFER=$PMTILES_BUFFER" )
[[ -n "${PMTILES_EXTENT:-}" ]] && PMTILES_EXTRA_DSCO+=( -dsco "EXTENT=$PMTILES_EXTENT" )

echo "Converting: $GPKG -> $OUT_PMTILES (MINZOOM=$PMTILES_MINZOOM MAXZOOM=$PMTILES_MAXZOOM MAX_FEATURES=$PMTILES_MAX_FEATURES MAX_SIZE=$PMTILES_MAX_SIZE)"
err=$(ogr2ogr -skipfailures -nlt PROMOTE_TO_MULTI $T_SRS \
  -dsco "MINZOOM=$PMTILES_MINZOOM" -dsco "MAXZOOM=$PMTILES_MAXZOOM" \
  "${PMTILES_EXTRA_DSCO[@]}" \
  -f "PMTiles" "$OUT_PMTILES" "$GPKG" 2>&1) || true
if [[ -f "$OUT_PMTILES" ]]; then
  echo "Done. Output: $OUT_PMTILES"
  exit 0
fi
if echo "$err" | grep -q "does not support data source creation"; then
  echo "PMTiles 直接出力は非対応のため、GeoParquet を経由します。" >&2
else
  echo "$err" >&2
fi

echo "Writing GeoParquet: $OUT_PARQUET"
if ! ogr2ogr -skipfailures $T_SRS -f Parquet -lco GEOMETRY_ENCODING=WKB "$OUT_PARQUET" "$GPKG" 2>&1; then
  echo "Error: GeoParquet の作成に失敗しました。" >&2
  exit 1
fi
[[ -f "$OUT_PARQUET" ]] || { echo "Error: Parquet が生成されませんでした。" >&2; exit 1; }

echo "Writing PMTiles: $OUT_PMTILES (MINZOOM=$PMTILES_MINZOOM MAXZOOM=$PMTILES_MAXZOOM MAX_FEATURES=$PMTILES_MAX_FEATURES MAX_SIZE=$PMTILES_MAX_SIZE)"
pmt_err=$(ogr2ogr -skipfailures -s_srs EPSG:3857 $T_SRS \
  -dsco "MINZOOM=$PMTILES_MINZOOM" -dsco "MAXZOOM=$PMTILES_MAXZOOM" \
  "${PMTILES_EXTRA_DSCO[@]}" \
  -f "PMTiles" \
  "$OUT_PMTILES" "$OUT_PARQUET" 2>&1) || true

if [[ -f "$OUT_PMTILES" ]]; then
  rm -f "$OUT_PARQUET"
  echo "Done. Output: $OUT_PMTILES"
  exit 0
fi

if echo "$pmt_err" | grep -q "does not support data source creation"; then
  echo "" >&2
  echo "この GDAL では PMTiles 書き込みが無効の可能性があります。" >&2
  echo "GeoParquet は出力済み: $OUT_PARQUET" >&2
else
  echo "$pmt_err" >&2
  echo "Parquet は残しています: $OUT_PARQUET" >&2
fi
exit 1
