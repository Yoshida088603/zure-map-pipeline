# zure-map-pipeline

ファイルベースのジオパイプライン（RAW → GeoPackage → マージ → PMTiles → MapLibre）の作業リポジトリです。

## 各スクリプトの役割（`docs/plan.md` §4.2〜4.4 と対応）

番号は **処理の順序**（ゲート）を表す。詳細は `docs/plan.md` の Mermaid 図と検証表。

| 番号 | スクリプト | 役割 |
|------|------------|------|
| **10** | `01-raw-data-preview/10-data-preview.sh` | RAW のベースライン・構造・件数・処理区分（ずれまっぷ/14条/CSV 等）の記録。変換はしない。出力は `data/02-raw-data-preview/`。 |
| **20** | `02-convert/20-shp2geopackage.sh` | **Shapefile → GeoPackage**（`zure` / `14jyo` / `sample`）。**`zure` 既定**は **2 段階**（`-makevalid` なし→`ST_MakeValid`）。**`ZURE_TWO_PASS=0`** で従来の 1 段 `-makevalid` のみ。**`ZURE_ONLY_KEI=03`** で系を限定可能。件数照合は `verify_gpkg_vs_shp`。**`zure` で 2 段階のときは python3** が必要。 |
| **（補助）** | `02-convert/21-zure-two-pass-test.sh` | **`20 zure` のラッパ**（`ZURE_TWO_PASS=1`・`ZURE_ONLY_KEI`・出力先 `two_pass_test_keiNN_<TS>/`）。単一系の試走用。 |
| **25** | `02-convert/25-csv2geopackage.sh` | **CSV → GeoPackage**（土地活用・街区・都市部など）。`data/03-geopackage/csv2geopackage/`。 |
| **30** | `02-convert/30-check-geopackage.sh` | **RAW（公図 SHP）と `geopackage_per_kei/*.gpkg`（`kozu_merged`）のフィーチャ件数突合**（系別＋合計）。`20` の `verify_gpkg_vs_shp` と同じ前提。引数省略時は最新の `run_zure*/geopackage_per_kei`。`ZURE_SHIKUCHOSON` は `20` と同様。NG なら 20/25 に戻る。 |
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
- **Python 3**: `25-csv2geopackage.sh` で使用。`20` の **`zure`（既定の 2 段階）**でも SQL 生成に使用。`30-check-geopackage.sh` は **ogrinfo のみ**（件数照合）。

## SHP と GPKG の件数差（調査サマリ）

`30-check-geopackage.sh` で RAW（`ogrinfo`）と `geopackage_per_kei` の件数がずれることがあった。主因は **1 段の `ogr2ogr … -makevalid`** が、修復不能なジオメトリのフィーチャを**出力から落とす**ことにあった。**現在の `20 zure` 既定（`ZURE_TWO_PASS=1`）**は 2 段階でこの差を抑える。従来動作は **`ZURE_TWO_PASS=0`**。

### 原因の整理

| 要因 | 内容 |
|------|------|
| ソース | 一部ポリゴンが未閉鎖リング・自己交差など、JTS/GEOS 上「壊れた」状態 |
| `-makevalid` | 内部で修復に失敗したフィーチャは**黙って欠落** |
| RAW 側の件数 | `ogrinfo` は**フィーチャ行**を数えるため、ジオメトリが壊れていても件数に含まれる |

### 代表例（3系・広島県府中市）

| 指標 | 件数 |
|------|------|
| RAW `ogrinfo`（`府中市_残差データ抽出.shp`） | 4831 |
| `ogr2ogr -makevalid …` 直後の GPKG | **4830**（1 件欠損） |

欠損は **FID=4614** に特定済み。該当ジオメトリは MULTIPOLYGON だが `Non closed ring` / `IllegalArgumentException: Points of LinearRing do not form a closed linestring` / `Ring Self-intersection` 等が出る。

### 件数整合の改善策（検証済みの方向性）

**2 段階**にすると、府中市では **4831 件を維持したまま**修復に進めることを確認した。

1. **第 1 段**: `-makevalid` **なし**で `-s_srs` / `-t_srs` のみ → GPKG（全件書き出し）
2. **第 2 段**: その GPKG に対し **SpatiaLite** の `ST_MakeValid(geom)` で別 GPKG に書き出し（実測でも **4831 件**）

`ogr2ogr -makevalid` と `ST_MakeValid` は実装が異なり、形状・面積が変わる可能性がある。全国一括へ組み込む場合は処理時間・ディスクも増える。本番の既定は **`20 zure`（`ZURE_TWO_PASS=1`）**に統合済み。

コマンド例・経緯の詳細は **`docs/investigation-shp-gpkg-geometry-loss.md`** を参照。

### 全国 `zure` の件数照合（記録）

**2026-03-22**、ローカルで `bash 02-convert/20-shp2geopackage.sh zure`（既定 `ZURE_TWO_PASS=1`、全市区町村）を実行し、`run.log` 末尾の **`verify_gpkg_vs_shp` が成功**した。

| 項目 | 値 |
|------|-----|
| 出力ディレクトリ | `data/03-geopackage/shp2geopackage/run_zure_20260322_013135/` |
| ログ | 上記の `run.log`（逐次出力・件数照合の確証） |
| 件数照合 | **RAW 公図 SHP 合計 2,312,146 ＝ 各 `NN.gpkg` の `kozu_merged` 合計 2,312,146** |

成果の GPKG は `…/geopackage_per_kei/*.gpkg`。これらとログは容量のため Git 対象外（`.gitignore`）。再現は同コマンドで RAW を置いた環境で実行する。

### 単一系だけ試す（ラッパ）

```bash
bash 02-convert/21-zure-two-pass-test.sh      # 既定 03 系のみ → two_pass_test_kei03_<TS>/
bash 02-convert/21-zure-two-pass-test.sh 08
```

同等の指定: `ZURE_ONLY_KEI=03 ZURE_TWO_PASS=1 bash 02-convert/20-shp2geopackage.sh zure`。成果は `geopackage_per_kei/NN.gpkg`（中間 `.step1.tmp.gpkg` は削除）。

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
