#!/usr/bin/env bash
# CSV → GeoPackage（旧 gdal-full/scripts/csv_to_geopackage.sh）。
# Python 前処理は本ファイル内の heredoc から一時ファイルに展開して実行（別 .py は作らない）。
# 使い方: リポジトリルートで bash 02-convert/25-csv2geopackage.sh [-s] [入力ルート]
# 入力既定: data/01-raw-data/.../データ_origin、無ければ .../データ
# 出力: data/03-geopackage/csv2geopackage/
# 前提: ogr2ogr, python3。GDAL ビルドは行わない。

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONVERT_LOG="$REPO_ROOT/data/02-raw-data-preview/convert_log_gpkg.txt"
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" | tee -a "$CONVERT_LOG" >&2; }

DATA_PARENT="$REPO_ROOT/data/01-raw-data/05ホームページ公開用データ及びプログラム"
INPUT_ROOT="${DATA_PARENT}/データ_origin"
SKIP_EXISTING=false
for arg in "$@"; do
  if [[ "$arg" == "-s" ]]; then
    SKIP_EXISTING=true
  else
    INPUT_ROOT="$arg"
  fi
done
OUTPUT_ROOT="$REPO_ROOT/data/03-geopackage/csv2geopackage"

export LANG=C.UTF-8
cd "$REPO_ROOT"

if [[ ! -d "$INPUT_ROOT" && -d "${DATA_PARENT}/データ" ]]; then
  INPUT_ROOT="${DATA_PARENT}/データ"
fi

TMPDIR="${TMPDIR:-/tmp}/csv2geopackage_$$"
mkdir -p "$TMPDIR"
cleanup() { rm -rf "$TMPDIR"; }
trap cleanup EXIT

cat > "$TMPDIR/csv_to_geoparquet_tochi.py" <<'PY'
#!/usr/bin/env python3
import csv
import sys

def main():
    args = [a for a in sys.argv[1:] if a != "--print-zukei"]
    print_zukei = len(args) != len(sys.argv) - 1
    if len(args) != 2:
        sys.stderr.write("Usage: ... <input.csv> <output.csv> [--print-zukei]\n")
        sys.exit(1)
    src, dst = args[0], args[1]
    encodings = ["cp932", "utf-8", "utf-8-sig", "utf-8", "cp932"]
    errors_options = ["strict", "strict", "strict", "replace", "replace"]
    rows = None
    for enc, err in zip(encodings, errors_options):
        try:
            with open(src, "r", encoding=enc, newline="", errors=err) as f:
                reader = csv.reader(f)
                rows = list(reader)
            break
        except (UnicodeDecodeError, UnicodeError, OSError):
            continue
    if rows is None:
        sys.stderr.write("Failed to read CSV with cp932/utf-8\n")
        sys.exit(1)
    if not rows:
        sys.stderr.write("Empty CSV\n")
        sys.exit(1)
    first = rows[0]
    is_gaiku = "座標系" in first and "X座標" in first
    if is_gaiku:
        zukei_col = 11
        if len(rows) > 1 and len(rows[1]) > zukei_col:
            try:
                z = int(rows[1][zukei_col].strip())
                if 1 <= z <= 19 and print_zukei:
                    print(z)
            except ValueError:
                pass
        out_rows = [list(rows[0])]
        for i, cell in enumerate(out_rows[0]):
            if cell == "X座標":
                out_rows[0][i] = "Y座標"
            elif cell == "Y座標":
                out_rows[0][i] = "X座標"
        out_rows.extend(rows[1:])
        try:
            with open(dst, "w", encoding="utf-8", newline="") as f:
                writer = csv.writer(f)
                writer.writerows(out_rows)
        except OSError as e:
            sys.stderr.write(f"Failed to write {dst}: {e}\n")
            sys.exit(1)
        return
    ncols = len(first)
    header = [f"col{i}" for i in range(ncols)]
    if ncols > 8:
        header[7] = "y"
    if ncols > 9:
        header[8] = "x"
    zukei_col = 5
    if len(rows) > 1 and len(rows[1]) > zukei_col and print_zukei:
        try:
            z = int(rows[1][zukei_col].strip())
            if 1 <= z <= 19:
                print(z)
        except ValueError:
            pass
    try:
        with open(dst, "w", encoding="utf-8", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(header)
            writer.writerows(rows)
    except OSError as e:
        sys.stderr.write(f"Failed to write {dst}: {e}\n")
        sys.exit(1)

if __name__ == "__main__":
    main()
PY

cat > "$TMPDIR/csv_to_geoparquet_kozu.py" <<'PY'
#!/usr/bin/env python3
import csv
import sys

def main():
    if len(sys.argv) != 3:
        sys.stderr.write("Usage: ... <input.csv> <output.csv>\n")
        sys.exit(1)
    src = sys.argv[1]
    dst = sys.argv[2]
    encodings = ["cp932", "utf-8", "utf-8-sig", "utf-8"]
    errors_opts = ["strict", "strict", "strict", "replace"]
    rows = None
    for enc, err in zip(encodings, errors_opts):
        try:
            with open(src, "r", encoding=enc, newline="", errors=err) as f:
                reader = csv.reader(f)
                rows = list(reader)
            break
        except (UnicodeDecodeError, UnicodeError, OSError):
            continue
    if rows is None:
        sys.stderr.write("Failed to read CSV\n")
        sys.exit(1)
    if not rows:
        sys.stderr.write("Empty CSV\n")
        sys.exit(1)
    header = rows[0]
    colmap = {}
    for i, h in enumerate(header):
        hnorm = h.strip().upper().replace(" ", "")
        if hnorm in ("X1", "Y1", "X2", "Y2", "X3", "Y3", "X4", "Y4"):
            colmap[hnorm] = i
    required = ["X1", "Y1", "X2", "Y2", "X3", "Y3", "X4", "Y4"]
    if not all(k in colmap for k in required):
        idx_x1 = idx_y1 = idx_x2 = idx_y2 = idx_x3 = idx_y3 = idx_x4 = idx_y4 = None
        for i, h in enumerate(header):
            hnorm = h.strip().upper()
            if hnorm == "X1": idx_x1 = i
            elif hnorm == "Y1": idx_y1 = i
            elif hnorm == "X2": idx_x2 = i
            elif hnorm == "Y2": idx_y2 = i
            elif hnorm == "X3": idx_x3 = i
            elif hnorm == "Y3": idx_y3 = i
            elif hnorm == "X4": idx_x4 = i
            elif hnorm == "Y4": idx_y4 = i
        if all(x is not None for x in (idx_x1, idx_y1, idx_x2, idx_y2, idx_x3, idx_y3, idx_x4, idx_y4)):
            colmap = {"X1": idx_x1, "Y1": idx_y1, "X2": idx_x2, "Y2": idx_y2,
                      "X3": idx_x3, "Y3": idx_y3, "X4": idx_x4, "Y4": idx_y4}
        elif len(header) >= 13:
            colmap = {"X1": 5, "Y1": 6, "X2": 7, "Y2": 8, "X3": 9, "Y3": 10, "X4": 11, "Y4": 12}
        else:
            sys.stderr.write("Could not find X1,Y1,...\n")
            sys.exit(1)
    out_header = list(header) + ["WKT"]
    try:
        with open(dst, "w", encoding="utf-8", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(out_header)
            for row in rows[1:]:
                if len(row) <= max(colmap.values()):
                    continue
                try:
                    x1 = float(row[colmap["X1"]])
                    y1 = float(row[colmap["Y1"]])
                    x2 = float(row[colmap["X2"]])
                    y2 = float(row[colmap["Y2"]])
                    x3 = float(row[colmap["X3"]])
                    y3 = float(row[colmap["Y3"]])
                    x4 = float(row[colmap["X4"]])
                    y4 = float(row[colmap["Y4"]])
                except (ValueError, IndexError):
                    wkt = ""
                else:
                    wkt = f"POLYGON(({x1} {y1},{x2} {y2},{x3} {y3},{x4} {y4},{x1} {y1}))"
                writer.writerow(list(row) + [wkt])
    except OSError as e:
        sys.stderr.write(f"Failed to write {dst}: {e}\n")
        sys.exit(1)

if __name__ == "__main__":
    main()
PY

if ! command -v ogr2ogr &>/dev/null || ! command -v python3 &>/dev/null; then
  echo "Error: ogr2ogr と python3 が必要です。" >&2
  exit 1
fi

: > "$CONVERT_LOG"
log "csv_to_geopackage: REPO_ROOT=$REPO_ROOT"
log "INPUT_ROOT=$INPUT_ROOT OUTPUT_ROOT=$OUTPUT_ROOT"

if [[ ! -d "$INPUT_ROOT" ]]; then
  log "Error: Input root not found: $INPUT_ROOT"
  exit 1
fi
log "Starting (skip_existing=$SKIP_EXISTING)"
mkdir -p "$OUTPUT_ROOT"
FAILED=0

GAIKU_PY="$TMPDIR/csv_to_geoparquet_tochi.py"
KOZU_PY="$TMPDIR/csv_to_geoparquet_kozu.py"

FOLDER="街区基準点等データ"
IN_DIR="$INPUT_ROOT/$FOLDER"
OUT_DIR="$OUTPUT_ROOT/$FOLDER"
if [[ -d "$IN_DIR" ]]; then
  mkdir -p "$OUT_DIR"
  for csv in "$IN_DIR"/*.csv; do
    [[ -f "$csv" ]] || continue
    base=$(basename "$csv" .csv)
    out="$OUT_DIR/${base}.gpkg"
    if [[ "$SKIP_EXISTING" == true && -f "$out" ]]; then
      echo "[SKIP] $FOLDER/$base.csv"
      continue
    fi
    echo "[街区] $base.csv"
    tmp_csv="$TMPDIR/gaiku_${base}.csv"
    ZONE=$(python3 "$GAIKU_PY" "$csv" "$tmp_csv" --print-zukei 2>/dev/null | tail -1)
    if ! [[ "$ZONE" =~ ^[0-9]+$ ]] || (( ZONE < 1 || ZONE > 19 )); then
      echo "Warning: $FOLDER/$base.csv ZONE=$ZONE" >&2
      FAILED=1
      continue
    fi
    EPSG=$((6668 + ZONE))
    if ! ogr2ogr -skipfailures -f GPKG -nlt POINT \
      -s_srs "EPSG:$EPSG" -t_srs EPSG:3857 \
      -oo X_POSSIBLE_NAMES=X座標 \
      -oo Y_POSSIBLE_NAMES=Y座標 \
      "$out" "$tmp_csv" 2>&1; then
      echo "Warning: $FOLDER/$base.csv failed" >&2
      FAILED=1
    fi
  done
fi

FOLDER="都市部官民基準点等データ"
IN_DIR="$INPUT_ROOT/$FOLDER"
OUT_DIR="$OUTPUT_ROOT/$FOLDER"
if [[ -d "$IN_DIR" ]]; then
  mkdir -p "$OUT_DIR"
  for csv in "$IN_DIR"/*.csv; do
    [[ -f "$csv" ]] || continue
    base=$(basename "$csv" .csv)
    out="$OUT_DIR/${base}.gpkg"
    if [[ "$SKIP_EXISTING" == true && -f "$out" ]]; then
      echo "[SKIP] $FOLDER/$base.csv"
      continue
    fi
    echo "[都市部] $base.csv"
    tmp_csv="$TMPDIR/toshi_${base}.csv"
    ZONE=$(python3 "$GAIKU_PY" "$csv" "$tmp_csv" --print-zukei 2>/dev/null | tail -1)
    if ! [[ "$ZONE" =~ ^[0-9]+$ ]] || (( ZONE < 1 || ZONE > 19 )); then
      echo "Warning: $FOLDER/$base.csv ZONE=$ZONE" >&2
      FAILED=1
      continue
    fi
    EPSG=$((6668 + ZONE))
    if ! ogr2ogr -skipfailures -f GPKG -nlt POINT \
      -s_srs "EPSG:$EPSG" -t_srs EPSG:3857 \
      -oo X_POSSIBLE_NAMES=X座標 \
      -oo Y_POSSIBLE_NAMES=Y座標 \
      "$out" "$tmp_csv" 2>&1; then
      echo "Warning: $FOLDER/$base.csv failed" >&2
      FAILED=1
    fi
  done
fi

FOLDER="土地活用推進調査"
IN_DIR="$INPUT_ROOT/$FOLDER"
OUT_DIR="$OUTPUT_ROOT/$FOLDER"
if [[ -d "$IN_DIR" ]]; then
  mkdir -p "$OUT_DIR"
  for csv in "$IN_DIR"/*.csv; do
    [[ -f "$csv" ]] || continue
    base=$(basename "$csv" .csv)
    out="$OUT_DIR/${base}.gpkg"
    if [[ "$SKIP_EXISTING" == true && -f "$out" ]]; then
      echo "[SKIP] $FOLDER/$base.csv"
      continue
    fi
    echo "[土地活用] $base.csv"
    tmp_csv="$TMPDIR/${base}_tochi.csv"
    if ! python3 "$GAIKU_PY" "$csv" "$tmp_csv"; then
      echo "Warning: preprocess failed $base" >&2
      FAILED=1
      continue
    fi
    if ! ogr2ogr -skipfailures -f GPKG \
      -oo X_POSSIBLE_NAMES=x \
      -oo Y_POSSIBLE_NAMES=y \
      "$out" "$tmp_csv" 2>&1; then
      echo "Warning: ogr2ogr failed $base" >&2
      FAILED=1
    fi
  done
fi

FOLDER="公図と現況のずれデータ"
IN_DIR="$INPUT_ROOT/$FOLDER"
OUT_DIR="$OUTPUT_ROOT/$FOLDER"
if [[ -d "$IN_DIR" ]]; then
  mkdir -p "$OUT_DIR"
  for subdir in "$IN_DIR"/*/; do
    [[ -d "$subdir" ]] || continue
    subname=$(basename "$subdir")
    csv="$subdir/配置テキスト.csv"
    [[ -f "$csv" ]] || continue
    base="${subname}_配置テキスト"
    out="$OUT_DIR/${base}.gpkg"
    if [[ "$SKIP_EXISTING" == true && -f "$out" ]]; then
      echo "[SKIP] $FOLDER/$subname/配置テキスト.csv"
      continue
    fi
    echo "[公図] $subname/配置テキスト.csv"
    tmp_csv="$TMPDIR/kozu_${subname}.csv"
    if ! python3 "$KOZU_PY" "$csv" "$tmp_csv"; then
      FAILED=1
      continue
    fi
    if ! ogr2ogr -skipfailures -f GPKG "$out" "$tmp_csv" 2>&1; then
      FAILED=1
    fi
  done
  for csv in "$IN_DIR"/*.csv; do
    [[ -f "$csv" ]] || continue
    base=$(basename "$csv" .csv)
    out="$OUT_DIR/${base}.gpkg"
    if [[ "$SKIP_EXISTING" == true && -f "$out" ]]; then
      echo "[SKIP] $FOLDER/$base.csv"
      continue
    fi
    echo "[公図] $base.csv"
    tmp_csv="$TMPDIR/kozu_${base}.csv"
    if ! python3 "$KOZU_PY" "$csv" "$tmp_csv"; then
      FAILED=1
      continue
    fi
    if ! ogr2ogr -skipfailures -f GPKG "$out" "$tmp_csv" 2>&1; then
      FAILED=1
    fi
  done
fi

[[ $FAILED -eq 0 ]] || log "一部でエラーがありました。"
log "Done. Outputs in $OUTPUT_ROOT"
