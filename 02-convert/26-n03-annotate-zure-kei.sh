#!/usr/bin/env bash
# N03 行政区域 GPKG の各ポリゴンに、「系別公図ずれ（geopackage_per_kei/NN.gpkg の kozu_merged）と
# ジオメトリが交差するか」のフラグ列を付与した GPKG を出力する。
#
# 判定: GeoPandas sjoin（predicate=intersects）。CRS はいずれも EPSG:4326 想定。
#
# 使い方（リポジトリルートで）:
#   bash 02-convert/26-n03-annotate-zure-kei.sh [入力N03.gpkg] [出力.gpkg] [geopackage_per_keiディレクトリ]
#
# 既定（引数省略時）:
#   入力: data/03-geopackage/shp2geopackage/run_n03_*/ の最新の *_行政区域.gpkg（1件のみならそれ）
#   出力: data/03-geopackage/shp2geopackage/N03_zure_kei_flags.gpkg
#   系別: data/03-geopackage/shp2geopackage/geopackage_per_kei/
#
# 前提: Python3 仮想環境に geopandas（と高速化のため pyogrio 推奨）
#   python3 -m venv .venv
#   .venv/bin/pip install geopandas pyogrio
#   source .venv/bin/activate
#   bash 02-convert/26-n03-annotate-zure-kei.sh
#
# 環境変数:
#   PYTHON3 … 使用する python（既定: PATH の python3、無ければ $REPO_ROOT/.venv/bin/python3）
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
export LANG=C.UTF-8
cd "$REPO_ROOT"

SHP2GPKG="$REPO_ROOT/data/03-geopackage/shp2geopackage"
DEFAULT_PER_KEI="$SHP2GPKG/geopackage_per_kei"
DEFAULT_OUT="$SHP2GPKG/N03_zure_kei_flags.gpkg"

resolve_default_n03() {
  local latest="" d
  shopt -s nullglob
  local -a runs=( "$SHP2GPKG"/run_n03_*/*.gpkg )
  if [[ ${#runs[@]} -eq 1 ]]; then
    printf '%s' "${runs[0]}"
    return
  fi
  latest=""
  for d in "$SHP2GPKG"/run_n03_*; do
    [[ -d "$d" ]] || continue
    for f in "$d"/*_行政区域.gpkg "$d"/*.gpkg; do
      [[ -f "$f" ]] || continue
      if [[ -z "$latest" || "$f" -nt "$latest" ]]; then
        latest="$f"
      fi
    done
  done
  [[ -n "$latest" ]] && printf '%s' "$latest" && return
  echo "Error: 既定の N03 .gpkg が見つかりません。第1引数でパスを指定してください。" >&2
  exit 1
}

IN_GPKG="${1:-}"
OUT_GPKG="${2:-$DEFAULT_OUT}"
PER_KEI="${3:-$DEFAULT_PER_KEI}"

if [[ -z "$IN_GPKG" ]]; then
  IN_GPKG="$(resolve_default_n03)"
fi

if [[ ! -f "$IN_GPKG" ]]; then
  echo "Error: 入力 GPKG がありません: $IN_GPKG" >&2
  exit 1
fi
if [[ ! -d "$PER_KEI" ]]; then
  echo "Error: geopackage_per_kei がありません: $PER_KEI" >&2
  exit 1
fi

PY="${PYTHON3:-}"
if [[ -z "$PY" ]]; then
  if command -v python3 &>/dev/null; then
    PY="$(command -v python3)"
  elif [[ -x "$REPO_ROOT/.venv/bin/python3" ]]; then
    PY="$REPO_ROOT/.venv/bin/python3"
  else
    echo "Error: python3 が見つかりません。PYTHON3= または .venv を用意してください。" >&2
    exit 1
  fi
fi

if ! "$PY" -c "import geopandas" 2>/dev/null; then
  echo "Error: geopandas が $PY に入っていません。" >&2
  echo "  $REPO_ROOT で: python3 -m venv .venv && .venv/bin/pip install geopandas pyogrio" >&2
  exit 1
fi

TMPDIR="${TMPDIR:-/tmp}/n03_ann_$$"
mkdir -p "$TMPDIR"
cleanup() { rm -rf "$TMPDIR"; }
trap cleanup EXIT

cat > "$TMPDIR/annotate.py" <<'PY'
#!/usr/bin/env python3
import os
import sys
from pathlib import Path

import geopandas as gpd


def main() -> int:
    in_gpkg = Path(os.environ["N03_IN_GPKG"])
    out_gpkg = Path(os.environ["N03_OUT_GPKG"])
    per_kei = Path(os.environ["N03_PER_KEI"])
    layer = os.environ.get("N03_LAYER", "N03")
    kozu_layer = os.environ.get("KOZU_LAYER", "kozu_merged")

    gpkg_files = sorted(per_kei.glob("*.gpkg"))
    if not gpkg_files:
        print("Error: no *.gpkg in", per_kei, file=sys.stderr)
        return 1

    print("Reading", in_gpkg, "layer=", layer, flush=True)
    n03 = gpd.read_file(in_gpkg, layer=layer)
    if n03.empty:
        print("Error: N03 layer empty", file=sys.stderr)
        return 1
    geom_col = n03.geometry.name
    n_in = len(n03)
    # 安定した行順（fid があればソート）
    if "fid" in n03.columns:
        n03 = n03.sort_values("fid").reset_index(drop=True)

    for gf in gpkg_files:
        kei = gf.stem
        col = f"zure_kei_{kei}"
        if col in n03.columns:
            print("skip existing column", col, flush=True)
            continue
        print("  kei", kei, "from", gf.name, flush=True)
        kozu = gpd.read_file(gf, layer=kozu_layer)
        if kozu.empty:
            n03[col] = 0
            continue
        if kozu.crs != n03.crs:
            kozu = kozu.to_crs(n03.crs)
        n03[col] = 0
        # 交差する N03 行（index）を取得
        left = n03[[geom_col]].copy()
        left["_row"] = range(len(left))
        right = kozu[[kozu.geometry.name]]
        joined = gpd.sjoin(left, right, how="inner", predicate="intersects")
        hit_rows = joined["_row"].unique()
        n03.loc[hit_rows, col] = 1

    out_gpkg.parent.mkdir(parents=True, exist_ok=True)
    if out_gpkg.exists():
        out_gpkg.unlink()
    # pyogrio があればエンジン指定
    try:
        import pyogrio  # noqa: F401

        n03.to_file(out_gpkg, driver="GPKG", layer=layer, engine="pyogrio")
    except Exception:
        n03.to_file(out_gpkg, driver="GPKG", layer=layer)
    print("Wrote", out_gpkg, "features=", len(n03), "(input was", n_in, ")", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
PY

export N03_IN_GPKG="$IN_GPKG"
export N03_OUT_GPKG="$OUT_GPKG"
export N03_PER_KEI="$PER_KEI"
export N03_LAYER="${N03_LAYER:-N03}"
export KOZU_LAYER="${KOZU_LAYER:-kozu_merged}"

echo "入力: $IN_GPKG" >&2
echo "出力: $OUT_GPKG" >&2
echo "系別: $PER_KEI" >&2
echo "Python: $PY" >&2

"$PY" "$TMPDIR/annotate.py"

echo "完了: $OUT_GPKG" >&2
