# zure-map-pipeline

ファイルベースのジオパイプライン（RAW → GeoPackage → マージ → PMTiles → MapLibre）の作業リポジトリです。

## レイアウト（`plan.md` §5 準拠）

- `01-raw-data-preview/` — `10-data-preview.sh`
- `02-convert/` — `20`〜`50` の番号付きシェル
- `03-analysis/maplibre/` — 検図（`serve.py` はリポジトリルートをドキュメントルートにする）
- `data/` — 各段のデータ（巨大物は `.gitignore`）

## 前提

- **GDAL**: `ogr2ogr` / `ogrinfo` が **PATH で利用可能**であること（ビルド手順は本 README では扱いません）。
- **Python 3**: `25-csv2geopackage.sh` と `30-check-geopackage.sh`（`osgeo.ogr`）で使用。

## 実行例（リポジトリルートで）

```bash
bash 01-raw-data-preview/10-data-preview.sh
bash 02-convert/25-csv2geopackage.sh -s
bash 02-convert/40-merge-geopackage.sh all
bash 02-convert/45-geopackage2pmtiles.sh
bash 02-convert/50-check-pmtiles.sh
cd 03-analysis/maplibre && python3 serve.py
# ブラウザ: http://localhost:8080/03-analysis/maplibre/index.html
```

詳細な段階・制約はワークスペースの `plan.md`（`cursor/plan.md`）を参照してください。
