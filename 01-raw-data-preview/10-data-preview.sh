#!/usr/bin/env bash
# RAW（data/01-raw-data）のプレビュー・ベースライン（plan §3.2 / §4.3 の「10」）。
# ディレクトリ構造・件数のほか、SHP（ずれまっぷ・14条地図）と基準点系 CSV 3種を【処理区分】として明示する。
# ずれまっぷ直下の 01〜15 は平面直角座標系 1系〜15系ゾーンとの対応をログに書く。
# 使い方: リポジトリルートで bash 01-raw-data-preview/10-data-preview.sh
# 分析結果: data/02-raw-data-preview/raw_data_preview_YYYYMMDD_HHMMSS.txt（毎回新規のみ）
#
# 環境変数:
#   RAW_PREVIEW_CSV_LINES=1  … 全 CSV の行数合計を wc で詳細表示（任意）
#   RAW_PREVIEW_SKIP_SHP_FEATURES=1 … SHP の ogrinfo 集計をスキップ（768 本で時間がかかる場合）
#
# 別 .py は作らない（plan 方針）。新規 .sh も増やさず本ファイルのみ。

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RAW="$REPO_ROOT/data/01-raw-data"
PREVIEW_DIR="$REPO_ROOT/data/02-raw-data-preview"
TS="$(date +%Y%m%d_%H%M%S)"
STAMPED="$PREVIEW_DIR/raw_data_preview_${TS}.txt"

export LANG=C.UTF-8
mkdir -p "$PREVIEW_DIR"

if [[ ! -d "$RAW" ]]; then
  echo "Error: RAW が見つかりません: $RAW" >&2
  exit 1
fi

# DVD 構成の既定パス（HandsOn 由来の RAW 配置）
DATA_DIR="$RAW/05ホームページ公開用データ及びプログラム/データ"
DIR_ZURE="${DATA_DIR}/公図と現況のずれデータ"
DIR_14JO="${DATA_DIR}/14条地図（不足あり）"
DIR_TOCHI="${DATA_DIR}/土地活用推進調査"
DIR_GAIKU="${DATA_DIR}/街区基準点等データ"
DIR_TOSHI="${DATA_DIR}/都市部官民基準点等データ"

count_files() { find "$1" -type f 2>/dev/null | wc -l; }
count_shp() { find "$1" -type f -iname '*.shp' 2>/dev/null | wc -l; }
count_csv() { find "$1" -type f -iname '*.csv' 2>/dev/null | wc -l; }

# ogrinfo -json で各レイヤの featureCount を合計（ポリゴン／線等の区別はしない）
# ※ GDAL 3.8 系では data source だけの ogrinfo -so は Feature Count を出さないことがあるため -json を使う
sum_shp_features() {
  local dir="$1"
  local sum=0 f fc
  [[ -d "$dir" ]] || { echo 0; return; }
  while IFS= read -r -d '' f; do
    [[ -f "$f" ]] || continue
    fc=$(ogrinfo -json "$f" 2>/dev/null \
      | grep -o '"featureCount":[0-9][0-9]*' \
      | sed 's/.*://' \
      | awk '{ s += $1 } END { print s + 0 }')
    sum=$((sum + ${fc:-0}))
  done < <(find "$dir" -type f -iname '*.shp' -print0 2>/dev/null)
  echo "$sum"
}

# CSV: wc -l（xargs 分割時は複数の "total" 行が出るので合算）からファイル数を引く＝推定レコード数
sum_csv_lines_and_records() {
  local dir="$1"
  local nfiles lines rec
  [[ -d "$dir" ]] || { echo "0 0"; return; }
  nfiles=$(find "$dir" -type f -iname '*.csv' 2>/dev/null | wc -l)
  nfiles=$((nfiles + 0))
  [[ "$nfiles" -eq 0 ]] && echo "0 0" && return
  lines=$(find "$dir" -type f -iname '*.csv' -print0 2>/dev/null \
    | xargs -0 wc -l 2>/dev/null | awk '$2 == "total" { s += $1 } END { print s + 0 }')
  lines=$((lines + 0))
  rec=$((lines - nfiles))
  echo "$lines $rec"
}

{
  echo "=== $(date -Iseconds) 10-data-preview ==="
  echo "分析結果の格納: data/02-raw-data-preview/raw_data_preview_${TS}.txt"
  echo "RAW root: $RAW"

  echo "--- 合計サイズ ---"
  du -sh "$RAW" 2>/dev/null || true

  echo "--- ファイル数（RAW 全体） ---"
  find "$RAW" -type f 2>/dev/null | wc -l

  echo "--- ディレクトリ構造プレビュー（主要パスと配下ファイル件数） ---"
  echo "※ RAW は DVD ルート相当。下流の変換はこの大別を前提にする（後述「処理区分」）。"
  while IFS= read -r -d '' p; do
    [[ -d "$p" ]] || continue
    if [[ "$p" == "$RAW" ]]; then
      label="<RAW ルート>/"
    else
      label="${p#$RAW/}/"
    fi
    n=$(count_files "$p")
    printf '%8s  %s\n' "$n" "$label"
  done < <(find "$RAW" \( -path "$RAW" -o -path "$RAW/05ホームページ公開用データ及びプログラム" -o -path "$DATA_DIR" \) -print0 2>/dev/null)

  if [[ -d "$DATA_DIR" ]]; then
    echo "--- データ/ 直下フォルダ（各フォルダ配下のファイル件数） ---"
    shopt -s nullglob
    for d in "$DATA_DIR"/*/; do
      [[ -d "$d" ]] || continue
      n=$(count_files "$d")
      printf '%8s  %s\n' "$n" "$(basename "$d")/"
    done | sort -nr
    shopt -u nullglob
  fi

  echo "--- 構造の内訳（ずれまっぷ・14条地図 = SHP） ---"
  if [[ -d "$DIR_ZURE" ]]; then
    echo "[公図と現況のずれデータ]（ずれまっぷ）直下のブロック → 都道府県フォルダ例"
    echo "  ※ 直下のディレクトリ名 01〜15（2桁）は、日本の平面直角座標系におけるゾーン「1系〜15系」に対応する（01=1系、02=2系、…、15=15系）。"
    echo "     以降の都道府県フォルダは、そのゾーン内のデータ分割。"
    shopt -s nullglob
    for blk in "$DIR_ZURE"/*/; do
      [[ -d "$blk" ]] || continue
      bn=$(basename "$blk")
      nb=$(count_files "$blk")
      printf '  %8s  %s/\n' "$nb" "$bn"
    done | sort -nr
    first_blk=""
    best=0
    for blk in "$DIR_ZURE"/*/; do
      [[ -d "$blk" ]] || continue
      nb=$(count_files "$blk")
      if [[ "$nb" -gt "$best" ]]; then best=$nb; first_blk="$blk"; fi
    done
    if [[ -n "$first_blk" ]]; then
      echo "  （例: 配下ファイル数最大ブロック $(basename "$first_blk") 内の都道府県フォルダ先頭5件）"
      _i=0
      while IFS= read -r -d '' pref; do
        [[ -d "$pref" ]] || continue
        np=$(count_files "$pref")
        printf '    %8s  %s\n' "$np" "$(basename "$pref")"
        _i=$((_i + 1))
        [[ "$_i" -ge 5 ]] && break
      done < <(find "$first_blk" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null)
    fi
    shopt -u nullglob
  else
    echo "(公図と現況のずれデータ なし)"
  fi

  if [[ -d "$DIR_14JO" ]]; then
    echo "[14条地図（不足あり）] 系フォルダ別ファイル件数"
    shopt -s nullglob
    for d in "$DIR_14JO"/*/; do
      [[ -d "$d" ]] || continue
      n=$(count_files "$d")
      printf '  %8s  %s/\n' "$n" "$(basename "$d")"
    done | sort -nr
    shopt -u nullglob
  else
    echo "(14条地図（不足あり） なし)"
  fi

  echo "--- 構造の内訳（基準点系 CSV = 直下フラット想定） ---"
  for name in "土地活用推進調査" "街区基準点等データ" "都市部官民基準点等データ"; do
    p="${DATA_DIR}/${name}"
    if [[ ! -d "$p" ]]; then
      echo "[$name] なし"
      continue
    fi
    nd=$(find "$p" -mindepth 1 -type d 2>/dev/null | wc -l)
    if [[ "$nd" -eq 0 ]]; then
      echo "[$name] サブディレクトリなし（CSV が直下に並ぶ構成） ファイル数=$(count_files "$p")"
    else
      echo "[$name] サブディレクトリあり（$nd 配下） ファイル数=$(count_files "$p")"
    fi
  done

  echo "--- 先頭ディレクトリ（RAW 直下） ---"
  find "$RAW" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -40

  echo "--- 拡張子別ファイル数（上位40、拡張子なしは noext） ---"
  find "$RAW" -type f -printf '%f\n' 2>/dev/null \
    | awk -F. '{
        n = split($0, a, ".")
        if (n >= 2) {
          ext = tolower(a[n])
          if (ext ~ /^[a-z0-9]+$/) c[ext]++
          else c["(other)"]++
        } else c["noext"]++
      }
      END { for (e in c) print c[e], e }' \
    | sort -nr | head -40

  echo "--- 主なジオ関連（件数） ---"
  for ext in shp dbf shx prj csv gpkg geojson json xml; do
    n=$(find "$RAW" -type f -iname "*.${ext}" 2>/dev/null | wc -l)
    printf '%8s  .%s\n' "$n" "$ext"
  done

  echo "--- Shapefile 三部一致チェック（.shp と .dbf/.shx の件数差） ---"
  n_shp=$(find "$RAW" -type f -iname '*.shp' 2>/dev/null | wc -l)
  n_dbf=$(find "$RAW" -type f -iname '*.dbf' 2>/dev/null | wc -l)
  n_shx=$(find "$RAW" -type f -iname '*.shx' 2>/dev/null | wc -l)
  echo "shp=$n_shp dbf=$n_dbf shx=$n_shx"
  if [[ "$n_shp" != "$n_dbf" || "$n_shp" != "$n_shx" ]]; then
    echo "注意: shp/dbf/shx の件数が一致しません（欠損 Shapefile の可能性）。"
  fi

  echo "--- SHP フィーチャ数（ogrinfo -json の featureCount を各 .shp で合計） ---"
  echo "※ 地物数。MultiPolygon 等を含む。線・点レイヤが混在する場合も件数に含まれる。"
  if [[ "${RAW_PREVIEW_SKIP_SHP_FEATURES:-}" == "1" ]]; then
    echo "スキップ（RAW_PREVIEW_SKIP_SHP_FEATURES=1）"
    raw_shp_feat=""; zure_feat=""; jo14_feat=""
  elif command -v ogrinfo >/dev/null 2>&1; then
    echo "集計中（.shp 本数分 ogrinfo を実行するため時間がかかることがあります）…"
    raw_shp_feat=$(sum_shp_features "$RAW")
    echo "  RAW 全体: フィーチャ合計 ${raw_shp_feat}"
    if [[ -d "$DIR_ZURE" ]]; then
      zure_feat=$(sum_shp_features "$DIR_ZURE")
      echo "  ずれまっぷ（公図と現況のずれデータ）: ${zure_feat}"
    else
      zure_feat=""
      echo "  ずれまっぷ: （ディレクトリなし）"
    fi
    if [[ -d "$DIR_14JO" ]]; then
      jo14_feat=$(sum_shp_features "$DIR_14JO")
      echo "  14条地図（不足あり）: ${jo14_feat}"
    else
      jo14_feat=""
      echo "  14条地図: （ディレクトリなし）"
    fi
  else
    echo "ogrinfo なし（PATH に GDAL なし）— フィーチャ数はスキップ"
    raw_shp_feat=""; zure_feat=""; jo14_feat=""
  fi

  echo "--- CSV レコード数（wc -l 実測） ---"
  echo "※ 行数合計から CSV ファイル数を引いた値＝各ファイル先頭1行をヘッダとみなした推定レコード数。"
  read -r raw_csv_lines raw_csv_recs < <(sum_csv_lines_and_records "$RAW")
  echo "  RAW 全体: 行数合計 ${raw_csv_lines} / 推定レコード数 ${raw_csv_recs}"
  read -r tochi_lines tochi_recs < <(sum_csv_lines_and_records "$DIR_TOCHI")
  read -r gaiku_lines gaiku_recs < <(sum_csv_lines_and_records "$DIR_GAIKU")
  read -r toshi_lines toshi_recs < <(sum_csv_lines_and_records "$DIR_TOSHI")
  echo "  土地活用推進調査: 行 ${tochi_lines} / 推定レコード ${tochi_recs}"
  echo "  街区基準点等データ: 行 ${gaiku_lines} / 推定レコード ${gaiku_recs}"
  echo "  都市部官民基準点等データ: 行 ${toshi_lines} / 推定レコード ${toshi_recs}"

  echo "=================================================================================="
  echo "【処理区分】下流（20-shp2geopackage / 25-csv2geopackage 等）で大別する前提"
  echo "=================================================================================="
  echo "■ グループ A — Shapefile（ポリゴン）… ずれまっぷ + 14条地図"
  echo "    ずれまっぷ = [公図と現況のずれデータ]、14条地図 = [14条地図（不足あり）]。"
  echo "    ずれまっぷ直下の 01〜15 は平面直角座標系 1系〜15系ゾーンに対応（上記「構造の内訳」参照）。"
  echo "    CSV 基準点系とは別系統。主に 20 でシェープ→GPKG を想定。"
  if [[ -d "$DIR_ZURE" ]]; then
    zf=$(count_files "$DIR_ZURE"); zs=$(count_shp "$DIR_ZURE")
    if [[ -n "${zure_feat:-}" ]]; then
      echo "    A-1 ずれまっぷ … ${DIR_ZURE#$RAW/} — ファイル ${zf} / .shp ${zs} / フィーチャ数(ogrinfo) ${zure_feat}"
    else
      echo "    A-1 ずれまっぷ … ${DIR_ZURE#$RAW/} — ファイル ${zf} / .shp ${zs} / フィーチャ数（未集計）"
    fi
  else
    echo "    A-1 ずれまっぷ … ディレクトリなし"
  fi
  if [[ -d "$DIR_14JO" ]]; then
    jf=$(count_files "$DIR_14JO"); js=$(count_shp "$DIR_14JO")
    if [[ -n "${jo14_feat:-}" ]]; then
      echo "    A-2 14条地図 … ${DIR_14JO#$RAW/} — ファイル ${jf} / .shp ${js} / フィーチャ数(ogrinfo) ${jo14_feat}"
    else
      echo "    A-2 14条地図 … ${DIR_14JO#$RAW/} — ファイル ${jf} / .shp ${js} / フィーチャ数（未集計）"
    fi
  else
    echo "    A-2 14条地図 … ディレクトリなし"
  fi
  echo "■ グループ B — CSV（基準点・街区・土地活用）… 列仕様がデータセットごとに異なる想定"
  echo "    [土地活用推進調査] [街区基準点等データ] [都市部官民基準点等データ] の3フォルダを大別。"
  echo "    主に 25-csv2geopackage で系統を分けて処理する前提。"
  if [[ -d "$DIR_TOCHI" ]]; then
    tf=$(count_files "$DIR_TOCHI"); tc=$(count_csv "$DIR_TOCHI")
    echo "    B-1 土地活用推進調査 … ${DIR_TOCHI#$RAW/} — ファイル ${tf} / .csv ${tc} / 推定レコード ${tochi_recs}"
  else
    echo "    B-1 土地活用推進調査 … ディレクトリなし"
  fi
  if [[ -d "$DIR_GAIKU" ]]; then
    gf=$(count_files "$DIR_GAIKU"); gc=$(count_csv "$DIR_GAIKU")
    echo "    B-2 街区基準点等データ … ${DIR_GAIKU#$RAW/} — ファイル ${gf} / .csv ${gc} / 推定レコード ${gaiku_recs}"
  else
    echo "    B-2 街区基準点等データ … ディレクトリなし"
  fi
  if [[ -d "$DIR_TOSHI" ]]; then
    sf=$(count_files "$DIR_TOSHI"); sc=$(count_csv "$DIR_TOSHI")
    echo "    B-3 都市部官民基準点等データ … ${DIR_TOSHI#$RAW/} — ファイル ${sf} / .csv ${sc} / 推定レコード ${toshi_recs}"
  else
    echo "    B-3 都市部官民基準点等データ … ディレクトリなし"
  fi
  echo "=================================================================================="

  echo "--- CSV ファイル数（RAW 全体・再掲） ---"
  n_csv=$(find "$RAW" -type f -iname '*.csv' 2>/dev/null | wc -l)
  echo "$n_csv"

  if [[ "${RAW_PREVIEW_CSV_LINES:-}" == "1" ]]; then
    echo "--- 全 CSV 行数 wc 詳細（RAW_PREVIEW_CSV_LINES=1） ---"
    find "$RAW" -type f -iname '*.csv' -print0 2>/dev/null \
      | xargs -0 wc -l 2>/dev/null | tail -1 || echo "(wc 失敗または CSV なし)"
  fi

  if command -v ogrinfo >/dev/null 2>&1; then
    echo "--- ogrinfo（先頭の .shp 1 件、あれば） ---"
    first_shp=$(find "$RAW" -type f -iname '*.shp' -print -quit 2>/dev/null)
    if [[ -n "$first_shp" && -f "$first_shp" ]]; then
      echo "sample: $first_shp"
      ogrinfo -so "$first_shp" 2>/dev/null | head -40 || echo "(ogrinfo 失敗)"
    else
      echo "(.shp なし)"
    fi
  else
    echo "--- ogrinfo なし（PATH に GDAL なし）— CRS/bbox の取得はスキップ ---"
  fi

  echo "--- 練馬区（ずれまっぷ・サンプル確認） ---"
  echo "※ 全域が区界と一致して埋まっているかは、公式の区界ポリゴンとの位相比較が必要（ここでは件数・範囲・面積の目安のみ）。"
  NERIMA_SHP="${DATA_DIR}/公図と現況のずれデータ/09/13東京都/公図/練馬区/練馬区_残差データ抽出.shp"
  NERIMA_LAYER="練馬区_残差データ抽出"
  if [[ ! -f "$NERIMA_SHP" ]]; then
    echo "（${NERIMA_SHP#$RAW/} が無い — スキップ）"
  elif command -v ogrinfo >/dev/null 2>&1; then
    echo "path: ${NERIMA_SHP#$RAW/}"
    ogrinfo -so "$NERIMA_SHP" "$NERIMA_LAYER" 2>/dev/null | grep -E '^(Layer name|Geometry|Feature Count|Extent:)' || true
    sum_area=$(CPL_LOG=/dev/null GDAL_QUIET=YES ogrinfo -q -dialect sqlite \
      -sql "SELECT SUM(ST_Area(GEOMETRY)) AS a FROM \"${NERIMA_LAYER}\"" "$NERIMA_SHP" 2>/dev/null \
      | awk '/a \(Real\)/ { print $NF }')
    if [[ -n "$sum_area" ]]; then
      echo "ポリゴン面積の単純合計（平面直角座標系上の m², ST_Area 合計）: $sum_area"
      echo "参考: 練馬区の区域面積は約 48.08 km²（東京都公式ページ等）≒ 48,080,000 m²。上記と近いなら全域に近いが、重複地物や無効ジオメトリで変動し得る。"
    fi
  else
    echo "path: ${NERIMA_SHP#$RAW/}（ogrinfo なし — 詳細スキップ）"
  fi

  echo "=== end ==="
} | tee "$STAMPED"

echo "分析結果を保存しました: $STAMPED" >&2
