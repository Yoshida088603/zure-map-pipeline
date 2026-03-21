#!/usr/bin/env bash
# 個別 GPKG の検査。パイプライン上の品質の主眼は RAW（SHP）と GPKG の整合（ポリゴン数・面積の一致）。
# 下記の埋め込み Python は旧 check_unclosed_rings 由来の補助スキャン（リング未閉合の列挙）であり、主ゲートの定義ではない。
# 使い方: bash 02-convert/30-check-geopackage.sh [入力GPKGまたはディレクトリ] [出力CSV]
# 既定: data/03-geopackage/shp2geopackage/run_zure*/geopackage_per_kei（最新の run ディレクトリ）、なければ csv2geopackage
# 出力CSV既定: data/02-raw-data-preview/閉じていないリング一覧.csv
# 前提: python3 + osgeo.ogr。GDAL ビルドは行わない。

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
export REPO_ROOT

TMP="$TMPDIR/check_gpkg_$$"
mkdir -p "$TMP"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/check_unclosed.py" <<'PY'
import csv
import os
import sys

TOL = 1e-9

def ring_is_closed(ring):
    n = ring.GetPointCount()
    if n < 4:
        return False
    x0, y0 = ring.GetX(0), ring.GetY(0)
    x1, y1 = ring.GetX(n - 1), ring.GetY(n - 1)
    return abs(x0 - x1) <= TOL and abs(y0 - y1) <= TOL

def collect_rings(geom, rings_out):
    if geom is None:
        return
    t = geom.GetGeometryType()
    if t == 3:
        for i in range(geom.GetGeometryCount()):
            ring = geom.GetGeometryRef(i)
            if ring is not None:
                rings_out.append((ring, i))
    elif t == 6:
        for j in range(geom.GetGeometryCount()):
            poly = geom.GetGeometryRef(j)
            if poly is not None:
                for i in range(poly.GetGeometryCount()):
                    ring = poly.GetGeometryRef(i)
                    if ring is not None:
                        rings_out.append((ring, i))

def get_field(feat, name, default=""):
    idx = feat.GetFieldIndex(name)
    if idx < 0:
        return default
    v = feat.GetField(idx)
    return default if v is None else str(v)

def scan_gpkg(gpkg_path, layer_name, source_name, results, stats):
    from osgeo import ogr
    ds = ogr.Open(gpkg_path, 0)
    if ds is None:
        sys.stderr.write("Warning: Could not open {}\n".format(gpkg_path))
        return
    lyr = ds.GetLayerByName(layer_name) if layer_name else ds.GetLayer(0)
    if lyr is None:
        ds = None
        return
    for feat in lyr:
        stats["total"] += 1
        geom = feat.GetGeometryRef()
        if geom is None:
            continue
        rings = []
        collect_rings(geom, rings)
        unclosed = [idx for (ring, idx) in rings if not ring_is_closed(ring)]
        if not unclosed:
            stats["closed"] += 1
        else:
            area = geom.GetArea()
            fid = feat.GetFID()
            results.append({
                "source": source_name,
                "fid": fid,
                "id": get_field(feat, "id"),
                "ooaza": get_field(feat, "ooaza"),
                "koaza": get_field(feat, "koaza"),
                "chiban": get_field(feat, "chiban"),
                "zumen": get_field(feat, "zumen"),
                "area": area,
                "ring_count": len(rings),
                "unclosed_ring_indices": ",".join(map(str, unclosed)),
                "unclosed_count": len(unclosed),
            })
    ds = None

def main():
    rr = os.environ.get("REPO_ROOT", "")
    alt = os.path.join(rr, "data", "03-geopackage", "csv2geopackage")
    shp2g = os.path.join(rr, "data", "03-geopackage", "shp2geopackage")
    default_in = alt
    if os.path.isdir(shp2g):
        import glob
        runs = sorted(
            glob.glob(os.path.join(shp2g, "run_zure*", "geopackage_per_kei")),
            key=os.path.getmtime,
            reverse=True,
        )
        if runs:
            default_in = runs[0]
        else:
            legacy = os.path.join(shp2g, "zure-work", "geopackage_マージ前")
            if os.path.isdir(legacy):
                default_in = legacy
    default_csv = os.path.join(rr, "data", "02-raw-data-preview", "閉じていないリング一覧.csv")
    inp = sys.argv[1] if len(sys.argv) > 1 else default_in
    out_csv = sys.argv[2] if len(sys.argv) > 2 else default_csv
    os.makedirs(os.path.dirname(out_csv) or ".", exist_ok=True)
    results = []
    stats = {"total": 0, "closed": 0}
    layer_name = "kozu_merged"
    if os.path.isfile(inp):
        sys.stderr.write("Scanning single GPKG: {}\n".format(inp))
        scan_gpkg(inp, layer_name, os.path.basename(inp), results, stats)
    elif os.path.isdir(inp):
        for f in sorted(os.listdir(inp)):
            if f.endswith(".gpkg"):
                path = os.path.join(inp, f)
                sys.stderr.write("Scanning {}\n".format(path))
                scan_gpkg(path, layer_name, f, results, stats)
    else:
        sys.stderr.write("Error: Not a file or directory: {}\n".format(inp))
        sys.exit(1)
    n_unclosed = len(results)
    n_total = stats["total"]
    n_closed = stats["closed"]
    total_area = sum(r["area"] for r in results)
    total_rings = sum(r["unclosed_count"] for r in results)
    fieldnames = [
        "source", "fid", "id", "ooaza", "koaza", "chiban", "zumen",
        "area", "ring_count", "unclosed_ring_indices", "unclosed_count",
    ]
    with open(out_csv, "w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fieldnames)
        w.writeheader()
        w.writerows(results)
    print("")
    print("=== 補助スキャン: 閉じていないリング（主品質は SHP↔GPKG の件数・面積の突合。20 の verify_gpkg_vs_shp 等）===")
    print("  対象: {}".format(inp))
    print("  スキャンしたポリゴン総数: {} 件".format(n_total))
    print("  閉じているポリゴン数: {} 件".format(n_closed))
    print("  閉じていないリングがあるポリゴン数: {} 件".format(n_unclosed))
    print("  閉じていないリングの延べ数: {} リング".format(total_rings))
    print("  該当ポリゴンの面積合計: {:.6g}".format(total_area))
    print("  詳細 CSV: {}".format(out_csv))

if __name__ == "__main__":
    main()
PY

if ! command -v python3 &>/dev/null; then
  echo "Error: python3 が必要です。" >&2
  exit 1
fi
python3 "$TMP/check_unclosed.py" "$@"
exit $?
