# 市区町村 overview PMTiles（48 スクリプト）

低ズーム用の `overview.pmtiles`（市区町村ポリゴン＋`has_data`）を、`geopackage_per_kei` の既存 GPKG と**空間交差**でタグ付けして生成する。

## 確定した既定仕様

| 項目 | 既定 |
|------|------|
| **has_data** | 境界ポリゴンと、**いずれかの系**の `kozu_merged` が **ST_Intersects** すれば `1`、否则 `0`（**detail PMTiles は入力に使わない**） |
| **通常モードのアルゴリズム** | **全系の単一マージ GPKG は作らない**。境界を一度 EPSG:4326 の作業用 GPKG（`muni_boundary`）に書き出し、**各系ごとにそのコピーへ当系だけ `kozu_one` として append** し、**同一 GeoPackage 内**で SpatiaLite `ST_Intersects` して境界キーを収集（`sort -u` で和集合）。SpatiaLite は **`ATTACH` した別 GPKG のジオメトリを GPB のまま扱い交差が常に偽になり得る**ため、交差判定には同一ファイルを使う。続けて `hit_keys` も境界コピーへ append し **LEFT JOIN** で `has_data` を付与 |
| **識別子列** | 既定 **`fid`**（整数想定）。国土数値情報 N03 の GPKG でレイヤ `N03`・ジオメトリ `geom` が一般的。**別データや別版**では **`OVERVIEW_MUNI_KEY_COLUMN`**（例: `N03_001`）に切替。複合キーが必要なら、事前に連結した列を境界データ側に用意してその列名を指定する |
| **中間ファイル** | `data/04-merge-geopackage/` 直下のみ（**新規サブフォルダなし**）。作業用境界 GPKG・ヒットキー CSV/GPKG・従来経路用 `overview_build_*.gpkg` など |
| **出力** | `data/05-pmtiles/zuremap/overview.pmtiles`（`NN.pmtiles` と並ぶ） |
| **PMTiles ズーム** | 既定 **z0–8**（`OVERVIEW_PMTILES_MAXZOOM` で変更） |
| **MVT レイヤ名** | `overview_municipality`（`main.js` の `source-layer` と一致） |
| **座標系** | 市区町境界は取り込み時に **EPSG:4326** に変換（系別 GPKG と揃える。`20 zure` の `T_SRS` 既定と同じ） |

### 計算量の目安

- 系ごとに「境界全件 × 当系ポリゴン」の交差判定が走るため、**合計 CPU 時間は依然として重い**場合がある。一方で、**全系を 1 本の `kozu_merged` に append するディスク負荷**は避ける。
- N03 相当の境界が **約数十万件ポリゴン**でも、キー 1 列のテキストを `sort -u` するコストは、巨大マージ GPKG より現実的なことが多い。

### 従来経路（比較・切り戻し）

**`OVERVIEW_FULL_MERGE=1`** のときのみ、従来どおり `overview_build_parcels_merged.gpkg` に全系をマージし、`overview_build_combined.gpkg` へ `kozu_parcels` を同居させて **`EXISTS` 一括**で `has_data` を付与する（**ディスク・時間とも最大**）。

## MapLibre 側の閾値

- overview レイヤ: **maxzoom 8** まで表示
- 系別 detail レイヤ: **minzoom 9** から表示（低ズームで detail タイル取得を抑止）

## MapLibre ビューアでの目視検図（overview + 詳細ポリゴン）

行政界の **`has_data`（データあり／なし）** と、系別 **ずれ詳細**（`kozu_merged`）を地図上で突き合わせる手順。

### 前提

- **GDAL**: 48 は **SpatiaLite 付き**のビルドが必要。MapLibre HandsOn の **gdal-full** で `libspatialite-dev` を入れてビルドし、`source env.sh && ./scripts/check_gdal_capabilities.sh` が成功してから 48 を実行する（[gdal-full README](../../maplibre/MapLibre-HandsOn-Beginner/05_ポリゴン表示/gdal-full/README.md)）。
- **成果物**: `data/05-pmtiles/zuremap/overview.pmtiles`（48）に加え、検図したい **系別 `NN.pmtiles`**（`47` または `45`）が同じディレクトリにあること。全系を見るなら 47 一括。

### E2E 手順

1. （任意）gdal-full で `check_gdal_capabilities.sh` を成功させる。
2. リポジトリルートで 48 を実行し `overview.pmtiles` を生成する。
3. （任意）`ogrinfo -al -so data/05-pmtiles/zuremap/overview.pmtiles` でレイヤ `overview_municipality` を確認。
4. 系別 PMTiles が無ければ `bash 02-convert/47-geopackage-per-kei2pmtiles.sh` 等で生成する。
5. **`serve.py` で配信**（リポジトリルートをドキュメントルートにする。**`python3 -m http.server` は使わない**。PMTiles に **Range** が必要）。

```bash
cd 03-analysis/maplibre && python3 serve.py
```

起動メッセージの URL をブラウザで開く。WSL2 で Cursor 内蔵ブラウザが届かないときは、Windows の Chrome/Edge か `hostname -I` の IP で同じパスを試す。

### `main.js` の塗り分けとズーム

- **`?mode=z12`** または **`?mode=all-kei`** のときだけ、`overview.pmtiles` を HEAD で確認のうえソース追加する（それ以外のモードでは overview は載らない）。
- **`has_data === 1`**: 緑系の塗り（低ズームの行政界）
- **`has_data === 0`**: 薄い灰の塗り
- overview は **z0–8**、詳細の `kozu_merged` は **z9 以降**。**まず低ズームで緑／灰の分布**を見てから、**ズームインして詳細ポリゴンと整合**を確認する。

### 検図用 URL（Markdown リンク例）

ホスト・ポートは環境に合わせて変える（既定 **8080**）。コピー用に **`03-analysis/maplibre/print_zure_verification_urls.sh`**（`BASE_URL` で基底 URL を上書き可）でも同じ行を出力できる。

- [単系 + overview（既定 09 系）](http://localhost:8080/03-analysis/maplibre/index.html?mode=z12)
- [単系を指定（例: 01）](http://localhost:8080/03-analysis/maplibre/index.html?mode=z12&kei=01)
- [全系 + overview](http://localhost:8080/03-analysis/maplibre/index.html?mode=all-kei)

`?noOverview=1` で overview だけオフ、`?overview=0` で HEAD プローブを抑止（未配置時の DevTools 404 対策）。詳細は `03-analysis/maplibre/index.html` のメタ説明を参照。

### 表示確認のチェックリスト

| 項目 | 期待 |
|------|------|
| 低ズーム（〜8） | 行政界が **緑＝has_data 1**、**薄灰＝has_data 0** で見える |
| 高ズーム（9〜） | 対象地域で **ずれ詳細**（`kozu_merged`）が重なり、緑域と大まかに整合する |
| 系の切替 | `?kei=NN` で `NN.pmtiles` に切り替え、同様に確認 |
| overview 未生成 | HUD に案内。生成後は `overview.pmtiles` が配信されレイヤが載る |

## 市区町村境界データ

リポジトリには境界ファイルを**同梱しない**。利用者が入手したシェープファイル等を**第1引数**で渡す（出所・ライセンスは利用者が管理）。

- 国土数値情報の行政区域データ等を想定
- レイヤが複数ある GPKG のときは **`OVERVIEW_BOUNDARY_LAYER`** で指定

## 依存（GDAL）

- `ogr2ogr` / `ogrinfo`（PATH）
- **SQLite dialect** の **空間述語**（`ST_Intersects`）を使用。**SpatiaLite が有効な GDAL** が必要な環境がある（無効ならエラーで終了し、メッセージを表示）
- 通常モードでは交差判定に **`ATTACH` は使わない**（別 GPKG のジオメトリが SpatiaLite で正しく交差判定されないことがあるため）。系ごとに作業用 GPKG を `cp` して `kozu_one` を append する

## ゲート（plan §4）

- **42 OK 後**かつ **系別 GPKG が最新**であることを推奨（`has_data` の根拠が `geopackage_per_kei` のため）
- **47 と独立**（detail PMTiles の再生成は不要）
- 生成後は **`50-check-pmtiles.sh`** で環境確認済みであること。`overview.pmtiles` 本体の突合は **`ogrinfo -al -so data/05-pmtiles/zuremap/overview.pmtiles`** 等で任意

## 実行例

```bash
# リポジトリルートで（境界は例。実パスに置き換え）
bash 02-convert/48-overview-municipality-pmtiles.sh /path/to/N03-20240101_01_GML/N03-20240101_01.shp

# 系別 GPKG のディレクトリを明示
bash 02-convert/48-overview-municipality-pmtiles.sh /path/to/boundary.shp /path/to/geopackage_per_kei

# 小さな検証: 1〜2 系だけ入ったディレクトリをコピーして GPKG_PER_KEI_DIR を向ける
GPKG_PER_KEI_DIR=/path/to/geopackage_per_kei_subset bash 02-convert/48-overview-municipality-pmtiles.sh /path/to/N03.gpkg N03
```

中間ファイルを残す: `OVERVIEW_KEEP_INTERMEDIATE=1`  
従来の全系マージ経路: `OVERVIEW_FULL_MERGE=1`

### 交差が 0 件になる・PMTiles 化で GPKG を開けないとき

- **座標系**: 境界はスクリプト内で **EPSG:4326** にそろえます。系 `kozu_merged` が **4326 以外**（例: JGD2011 の **6668**）のとき、既定では先頭系 GPKG の `ogrinfo` から EPSG を推定し、parcel 側を **`ST_Transform(..., 4326)`** してから `ST_Intersects` します。推定が合わない場合は **`OVERVIEW_PARCEL_SRID=6668`** のように明示してください。
- **出力 GPKG**: 最終 `ogr2ogr` は **`-skipfailures` を付けていません**。ジオメトリエラーで全件落ちると空ファイルになり、その後の 45 で「datasource を開けない」に見えます。`OVERVIEW_KEEP_INTERMEDIATE=1` で `overview_municipality.gpkg` を残し、`ogrinfo -so … overview_municipality` を確認してください。

## 検証のヒント

- 既存 `overview.pmtiles` と **件数・サンプル地点**を目視比較する（完全一致は保証しないが、`has_data=1` の広がりが極端にずれていないか）
- `ogrinfo -so` で境界レイヤの `fid`（または `OVERVIEW_MUNI_KEY_COLUMN`）が想定どおりか確認する
