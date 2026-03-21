# 調査: SHP→GPKG での件数欠損と修復パイプライン

## 背景

`30-check-geopackage.sh` で RAW（ogrinfo）と `geopackage_per_kei` の件数が一致しない系（例: 3・8・9 系）があり、原因は **`20-shp2geopackage.sh` の `ogr2ogr … -makevalid`** 経由で一部フィーチャが書き出されないことであると特定した。

本メモでは、**代表例での原因の特定**と、**整合改善が期待できる修復手順（検証済み）**を記録する。

## 1. 代表例（3系・広島県府中市）

### 1.1 件数

| 指標 | 件数 |
|------|------|
| RAW `ogrinfo`（府中市_残差データ抽出.shp） | 4831 |
| `ogr2ogr -makevalid -s_srs EPSG:6671 -t_srs EPSG:4326` → GPKG | **4830**（1 件欠損） |

### 1.2 欠損フィーチャの特定

`FID` 範囲を二分探索し、**欠損は FID=4614 の 1 件**に限定されることを確認した。

`ogrinfo -al -fid 4614` では **MULTIPOLYGON** が報告され、警告として

- `Non closed ring detected`
- `IllegalArgumentException: Points of LinearRing do not form a closed linestring`
- `Ring Self-intersection`

が出る。ジオメトリは **未閉鎖リング** と **自己交差** を併せ持つ。

### 1.3 OGR API での挙動（参考）

- `Geometry.IsValid()` → **False**
- `Geometry.MakeValid()` → **RuntimeError**（上記 `IllegalArgumentException` のため処理不能）
- `Geometry.Buffer(0)` も同様に失敗

つまり **GEOS が読み取り可能な多角形として組み立てられない段階**があり、`ogr2ogr` の **`-makevalid`** が内部で同系の処理に失敗し、**該当フィーチャが出力されない**。

## 2. 根本原因の整理

| 要因 | 説明 |
|------|------|
| ソースデータ | 一部ポリゴンが JTS/GEOS 上「壊れた」状態（未閉鎖・自己交差など） |
| `ogr2ogr -makevalid` | 修復不能なフィーチャは **黙って欠落**（ログに ERROR が出るが処理は継続） |
| RAW 側の件数 | `ogrinfo` は **フィーチャ行として数える**ため、ジオメトリが壊れていても件数に含まれる |

そのため **「RAW 件数 = 変換後件数」** を `-makevalid` 単体で厳密に満たすことは、**ソースを直すか、別経路で修復する**必要がある。

## 3. 検証した修復パイプライン（府中市・実測）

**2 段階**にすると、**件数 4831 を維持したまま** `ST_MakeValid` まで通せることを確認した。

### 手順（概念）

1. **第 1 段**: `ogr2ogr` で **`-makevalid` を付けず**、`-s_srs` / `-t_srs` のみで GPKG に書く（このとき **4831 件すべて**が入る）。
2. **第 2 段**: 同一 GPKG を入力に、`ogr2ogr` の **SQLite/SpatiaLite ダイアレクト**で  
   `SELECT ST_MakeValid(geom) AS geom, …` として **別 GPKG** に書く。

### 実測結果（府中市 1 ファイル）

- 第 1 段 GPKG: **Feature Count 4831**
- 第 2 段（`ST_MakeValid` 後）: **Feature Count 4831**

※ 属性列は `SELECT` 句で明示する必要があり、本番では `20` のレイヤ定義に合わせた列一覧が必要。

### 注意（リスク）

- **SpatiaLite の `ST_MakeValid`** と **`ogr2ogr -makevalid`** は実装が異なり、形状・面積が変わる可能性がある。
- 全国 VRT 一括に組み込む場合は **ディスク・時間**が増える。
- 第 1 段で無効ジオメトリをそのまま載せるため、**中間成果物の用途**（検証限定か本番か）を分けると安全。

## 4. 推奨される次のステップ

1. **試験**: 3系または府中市単体で、上記 2 段階パイプラインを `20` と同じ CRS・レイヤ名で再現し、`30-check-geopackage.sh` で件数が揃うか確認する。
2. **本番反映の判断**: 形状の変化許容範囲を定めたうえで、`20-shp2geopackage.sh` の `run_zure` 内 ogr2ogr を **2 段階化**するか、オプション環境変数（例: `ZURE_TWO_PASS_MAKEVALID=1`）で切り替え可能にする。
3. **データ元の修正**: 国交省データ側の更新や、QGIS「ジオメトリ修復」で **元 SHP を直す**のが、長期的には最も追いやすい。

## 5. 参考コマンド（府中市・再現用）

パスは環境に合わせて読み替える。

```bash
SHP="…/03/34広島県/公図/府中市/府中市_残差データ抽出.shp"
ogr2ogr -s_srs EPSG:6671 -t_srs EPSG:4326 -f GPKG /tmp/nomv.gpkg "$SHP" -nln k
ogr2ogr -f GPKG /tmp/mv2.gpkg /tmp/nomv.gpkg -dialect sqlite \
  -sql 'SELECT ST_MakeValid(geom) AS geom, fid, id, ooaza, koaza, chiban, jyotai, zumen, "XY19", PREFCODE, CITYCODE, BFR_GOSA, BFR_RANK, AFT_GOSA, AFT_RANK FROM k'
ogrinfo -so /tmp/mv2.gpkg | grep -i count
```

（列名は `ogrinfo -so /tmp/nomv.gpkg k` で要確認。）

---

*調査日: 環境 GDAL 3.8 系 / SpatiaLite 利用可能な `ogr2ogr`。*
