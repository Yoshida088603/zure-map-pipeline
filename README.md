# zure-map-pipeline

ファイルベースのジオパイプライン（RAW → GeoPackage → マージ → PMTiles → MapLibre）の作業リポジトリです。

## 各スクリプトの役割（`docs/plan.md` §4.2〜4.4 と対応）

番号は **処理の順序**（ゲート）を表す。詳細は `docs/plan.md` の Mermaid 図と検証表。

| 番号 | スクリプト | 役割 |
|------|------------|------|
| **10** | `01-raw-data-preview/10-data-preview.sh` | RAW のベースライン・構造・件数・処理区分（ずれまっぷ/14条/CSV 等）の記録。変換はしない。出力は `data/02-raw-data-preview/`。 |
| **20** | `02-convert/20-shp2geopackage.sh` | **Shapefile → GeoPackage**（`zure` / `14jyo` / `sample`）。**SHP 系（`zure`・`14jyo`）では変換末尾に、SHP 側のフィーチャ合計と GPKG の件数を照合**（`verify_gpkg_vs_shp`）。マージ・PMTiles は行わない。成果は `data/03-geopackage/shp2geopackage/`。 |
| **25** | `02-convert/25-csv2geopackage.sh` | **CSV → GeoPackage**（土地活用・街区・都市部など）。`data/03-geopackage/csv2geopackage/`。 |
| **30** | `02-convert/30-check-geopackage.sh` | **個別 GPKG の追加チェック**。品質の考え方としては RAW と GPKG の論理整合（件数・面積）だが、**件数の主たる自動照合は SHP 経路では `20` が担当**。**現行実装**は `kozu_merged` レイヤの**補助スキャン**（リング未閉合の列挙）。面積の自動突合は未実装。NG なら 20/25 に戻る。 |
| **40** | `02-convert/40-merge-geopackage.sh` | **用途別マージ** → `data/04-merge-geopackage/`。`tochi`/`gaiku`/`toshi`/`kozu`（CSV 系）に加え、ずれまっぷ SHP 経路は **`zure`**（`20` の `geopackage_per_kei` を統合）。 |
| **42** | `02-convert/42-check-merge-geopackage.sh` | **統合 GPKG の ogrinfo 出力**（レイヤ名・件数・投影などの**目視確認用**。自動の合格／不合格判定はしない）。 |
| **45** | `02-convert/45-geopackage2pmtiles.sh` | **GPKG → PMTiles**。出力は**入力 GPKG と同じディレクトリ**（既定例は `data/04-merge-geopackage/*.pmtiles`）。公図ずれなら引数で `…/公図と現況のずれデータ_merged.gpkg` を指定。 |
| **50** | `02-convert/50-check-pmtiles.sh` | **GDAL の PMTiles ドライバ登録と最小 GPKG→PMTiles 書き出し**の環境スモーク。特定の本番 GPKG／PMTiles との論理突合はしない。 |
| （検図） | `03-analysis/maplibre/serve.py` | PMTiles を **Range 対応 HTTP** で配信。`python -m http.server` では足りない。 |

**注意**: `40` の **`kozu`** は `csv2geopackage/公図と現況のずれデータ/*_残差データ抽出.gpkg` という別レイアウト想定。DVD からの **SHP 主経路**は **`20 zure` → `40 zure`**。

## レイアウト（`plan.md` §5 準拠）

- `01-raw-data-preview/` — `10-data-preview.sh`
- `02-convert/` — `20`〜`50` の番号付きシェル
- `03-analysis/maplibre/` — 検図（`serve.py` はリポジトリルートをドキュメントルートにする）
- `data/` — 各段のデータ（巨大物は `.gitignore`）

## 前提

- **GDAL**: `ogr2ogr` / `ogrinfo` が **PATH で利用可能**であること（ビルド手順は本 README では扱いません）。`10-data-preview.sh` の **SHP フィーチャ数**は `ogrinfo` が必要です（未導入時はスキップ）。
- **Python 3**: `25-csv2geopackage.sh` と `30-check-geopackage.sh`（`osgeo.ogr`）で使用。

## 実行例（リポジトリルートで）

**CSV 主経路**（plan の順序: 10→25→30→40→42→45→50→MapLibre。**20 は SHP 系**。省略可だが NG 時は戻る）:

```bash
bash 01-raw-data-preview/10-data-preview.sh
bash 02-convert/25-csv2geopackage.sh -s
bash 02-convert/30-check-geopackage.sh
bash 02-convert/40-merge-geopackage.sh all
bash 02-convert/42-check-merge-geopackage.sh
bash 02-convert/45-geopackage2pmtiles.sh
bash 02-convert/50-check-pmtiles.sh
cd 03-analysis/maplibre && python3 serve.py
```

`10` の全 CSV 行数（重い）: `RAW_PREVIEW_CSV_LINES=1 bash 01-raw-data-preview/10-data-preview.sh`

### ずれまっぷ（`20-shp2geopackage.sh zure`）を一部市区町村だけで試す

RAW のパスは `*/公図/<市区町村フォルダ名>/*.shp` 想定。テスト時は環境変数でフォルダ名を指定（カンマ区切りで複数可）。

成果物と逐次ログは **タイムスタンプ付きディレクトリ**に出力される（上書きしない）。例:

- `data/03-geopackage/shp2geopackage/run_zure_YYYYMMDD_HHMMSS/`（全国）
- `data/03-geopackage/shp2geopackage/run_zure_partial_YYYYMMDD_HHMMSS/`（`ZURE_SHIKUCHOSON` 指定時）

`20` は **SHP→GPKG（系別 `geopackage_per_kei/`）まで**。全系の 1 本への統合は **`40-merge-geopackage.sh zure`**、PMTiles は **`45-geopackage2pmtiles.sh`**（入力に `data/04-merge-geopackage/公図と現況のずれデータ_merged.gpkg` 等）。

各 run の `run.log` に標準出力・標準エラー相当が追記される。

```bash
ZURE_SHIKUCHOSON=練馬区 bash 02-convert/20-shp2geopackage.sh zure
bash 02-convert/40-merge-geopackage.sh zure
bash 02-convert/45-geopackage2pmtiles.sh data/04-merge-geopackage/公図と現況のずれデータ_merged.gpkg
```

詳細な段階・制約は `docs/plan.md` を参照してください。
