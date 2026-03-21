#!/usr/bin/env bash
# RAW（公図と現況のずれデータ）の SHP フィーチャ数と、変換後 geopackage_per_kei/*.gpkg（レイヤ kozu_merged）の件数を突合する。
# 20-shp2geopackage.sh zure の verify_gpkg_vs_shp と同じ考え方（系別＋合計）。
#
# 使い方: bash 02-convert/30-check-geopackage.sh [geopackage_per_kei ディレクトリ]
# 既定: data/03-geopackage/shp2geopackage/run_zure*/geopackage_per_kei（更新日時が最新の run）
#
# 環境変数（20 と同じ意味）:
#   ZURE_SHIKUCHOSON=練馬区[,区名...]  …  */公図/<市区町村名>/* の SHP のみ集計（部分実行の成果と照合するとき）
#   ORIGIN_ROOT=…  … RAW「公図と現況のずれデータ」のルート（省略時は data_origin / データ の既知パスから解決）
#
# 終了コード: すべて一致で 0、1 件でも不一致で 1
# 前提: ogrinfo（GDAL）。Python は不要。

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DATA_DVD="$REPO_ROOT/data/01-raw-data/05ホームページ公開用データ及びプログラム"
export LANG=C.UTF-8
cd "$REPO_ROOT"

for cmd in ogrinfo; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "Error: $cmd が PATH にありません。" >&2
    exit 1
  fi
done

# --- 以下、20-shp2geopackage.sh と同系の集計（VRT 経由ではなく素の SHP を ogrinfo する）---

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

gpkg_layer_feature_count() {
  sum_ogrjson_feature_count "$1" "$2"
}

# ずれまっぷ RAW 配下の公図 *.shp を列挙（-print0）
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

# 指定ディレクトリ以下の公図 SHP のフィーチャ数合計
sum_shp_features_under() {
  local root="$1"
  local sum=0 f fc
  while IFS= read -r -d '' f; do
    [[ -f "$f" ]] || continue
    fc=$(sum_ogrjson_feature_count "$f")
    sum=$((sum + fc))
  done < <(zure_find_shp_print0 "$root")
  echo "$sum"
}

resolve_origin_root() {
  if [[ -n "${ORIGIN_ROOT:-}" && -d "$ORIGIN_ROOT" ]]; then
    echo "$ORIGIN_ROOT"
    return
  fi
  local d
  for d in \
    "$DATA_DVD/データ_origin/公図と現況のずれデータ" \
    "$DATA_DVD/データ/公図と現況のずれデータ"
  do
    if [[ -d "$d" ]]; then
      echo "$d"
      return
    fi
  done
  echo ""
}

default_geopackage_per_kei() {
  local shp2g="$REPO_ROOT/data/03-geopackage/shp2geopackage"
  local best="" t_best=-1 g t
  shopt -s nullglob
  for g in "$shp2g"/run_zure*/geopackage_per_kei; do
    [[ -d "$g" ]] || continue
    t=$(stat -c %Y "$g" 2>/dev/null || stat -f %m "$g" 2>/dev/null || echo 0)
    if [[ "$t" -gt "$t_best" ]]; then
      best="$g"
      t_best="$t"
    fi
  done
  if [[ -n "$best" ]]; then
    echo "$best"
    return
  fi
  local legacy="$shp2g/zure-work/geopackage_マージ前"
  if [[ -d "$legacy" ]]; then
    echo "$legacy"
    return
  fi
  echo ""
}

GPKG_DIR="${1:-$(default_geopackage_per_kei)}"
ORIGIN_ROOT="$(resolve_origin_root)"

if [[ -z "$GPKG_DIR" || ! -d "$GPKG_DIR" ]]; then
  echo "Error: geopackage_per_kei がありません: ${GPKG_DIR:-（既定も未検出）}" >&2
  echo "  引数でディレクトリを指定するか、shp2geopackage/run_zure*/geopackage_per_kei を用意してください。" >&2
  exit 1
fi

if [[ -z "$ORIGIN_ROOT" ]]; then
  echo "Error: RAW の 公図と現況のずれデータ が見つかりません。ORIGIN_ROOT= を指定してください。" >&2
  exit 1
fi

LAYER_NAME="${LAYER_NAME:-kozu_merged}"
any=0
fail=0
total_exp=0
total_act=0

echo "=== 30-check-geopackage（RAW SHP ↔ GPKG 件数）==="
echo "ORIGIN_ROOT=$ORIGIN_ROOT"
echo "GPKG_DIR=$GPKG_DIR"
echo "LAYER=$LAYER_NAME"
echo "ZURE_SHIKUCHOSON=${ZURE_SHIKUCHOSON:-（全市区町村）}"
echo ""

for k in 01 02 03 04 05 06 07 08 09 10 11 12 13 14 15; do
  gf="$GPKG_DIR/${k}.gpkg"
  [[ -f "$gf" ]] || continue
  any=1
  kei_dir="$ORIGIN_ROOT/$k"
  if [[ ! -d "$kei_dir" ]]; then
    echo "[系 $k] Error: RAW 側にディレクトリがありません: $kei_dir" >&2
    fail=1
    continue
  fi
  exp_k=$(sum_shp_features_under "$kei_dir")
  act_k=$(gpkg_layer_feature_count "$gf" "$LAYER_NAME")
  total_exp=$((total_exp + exp_k))
  total_act=$((total_act + act_k))
  if [[ "$exp_k" == "$act_k" ]]; then
    echo "[系 $k] OK  SHP=${exp_k}  GPKG=${act_k}"
  else
    echo "[系 $k] NG  SHP=${exp_k}  GPKG=${act_k}" >&2
    fail=1
  fi
done

if [[ "$any" -eq 0 ]]; then
  echo "Error: $GPKG_DIR に 01.gpkg … 15.gpkg がありません（空または別レイアウト）。" >&2
  exit 1
fi

echo ""
echo "[件数照合 合計（対象系のみ）] SHP=${total_exp}  GPKG=${total_act}"
if [[ "$fail" -eq 0 && "$total_exp" == "$total_act" ]]; then
  echo "結果: OK"
  exit 0
fi
echo "結果: NG（系別または合計の不一致）" >&2
exit 1
