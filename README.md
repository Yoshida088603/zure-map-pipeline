# zure-map-pipeline

ファイルベースのジオパイプライン（RAW → GeoPackage → マージ → PMTiles → MapLibre）の作業リポジトリです。

## レイアウト

- `01-raw-data-preview/` — RAW プレビュー・ベースライン（10）
- `02-convert/` — 変換・検証・マージ・PMTiles（20〜50）
- `03-analysis/maplibre/` — 検図用 MapLibre
- `data/` — 各段のデータ（`01-raw-data`・`07-rasters` 等は原則 Git 対象外。`.gitignore` 参照）
- `docs/` — 設計・手順・記録

詳細は `docs/plan.md`（プロジェクト計画）を参照してください。
