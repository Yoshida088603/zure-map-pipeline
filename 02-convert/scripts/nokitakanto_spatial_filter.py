#!/usr/bin/env python3
"""
GeoPackage の 1 レイヤについて、OGR の属性フィルタに通った地物のうち、
マスクレイヤのジオメトリと交差するものを除いて別 GPKG に書き出す。
（SpatiaLite 非リンクの ogr2ogr でも空間除外できるようにする）
"""
from __future__ import annotations

import argparse
import os
import sys

from osgeo import gdal, ogr

ogr.UseExceptions()
gdal.UseExceptions()


def _union_mask_geometries(layer: ogr.Layer) -> ogr.Geometry | None:
    union: ogr.Geometry | None = None
    layer.ResetReading()
    feat = layer.GetNextFeature()
    while feat is not None:
        g = feat.GetGeometryRef()
        if g is not None and not g.IsEmpty():
            gc = g.Clone()
            union = gc if union is None else union.Union(gc)
        feat = layer.GetNextFeature()
    return union


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--in-gpkg", required=True)
    p.add_argument("--in-layer", required=True)
    p.add_argument(
        "--attr-where",
        required=True,
        help="OGR SetAttributeFilter に渡す式（例: PREFCODE IS NULL OR (...)）",
    )
    p.add_argument("--mask-gpkg", required=True)
    p.add_argument("--mask-layer", required=True)
    p.add_argument("--out-gpkg", required=True)
    p.add_argument("--out-layer", required=True)
    args = p.parse_args()

    mask_ds = ogr.Open(args.mask_gpkg, gdal.GA_ReadOnly)
    if mask_ds is None:
        print(f"Error: マスクを開けません: {args.mask_gpkg}", file=sys.stderr)
        return 1
    mlayer = mask_ds.GetLayerByName(args.mask_layer)
    if mlayer is None:
        print(f"Error: マスクレイヤがありません: {args.mask_layer}", file=sys.stderr)
        return 1

    mask_u = _union_mask_geometries(mlayer)
    if mask_u is None or mask_u.IsEmpty():
        print("Error: マスクにジオメトリがありません。", file=sys.stderr)
        return 1

    in_ds = ogr.Open(args.in_gpkg, gdal.GA_ReadOnly)
    if in_ds is None:
        print(f"Error: 入力を開けません: {args.in_gpkg}", file=sys.stderr)
        return 1
    ilayer = in_ds.GetLayerByName(args.in_layer)
    if ilayer is None:
        print(f"Error: 入力レイヤがありません: {args.in_layer}", file=sys.stderr)
        return 1

    ilayer.SetAttributeFilter(args.attr_where)

    if os.path.exists(args.out_gpkg):
        os.remove(args.out_gpkg)

    drv = ogr.GetDriverByName("GPKG")
    out_ds = drv.CreateDataSource(args.out_gpkg)
    srs = ilayer.GetSpatialRef()
    # 入力が Polygon 指定でも MultiPolygon 等が混在することがあるため Unknown で受ける
    out_lyr = out_ds.CreateLayer(args.out_layer, srs, ogr.wkbUnknown)

    idefn = ilayer.GetLayerDefn()
    for i in range(idefn.GetFieldCount()):
        out_lyr.CreateField(idefn.GetFieldDefn(i))

    ilayer.ResetReading()
    n_read = 0
    n_kept = 0
    n_spatial_drop = 0
    feat = ilayer.GetNextFeature()
    while feat is not None:
        n_read += 1
        g = feat.GetGeometryRef()
        if g is not None and not g.IsEmpty() and mask_u.Intersects(g):
            n_spatial_drop += 1
        else:
            out_lyr.CreateFeature(feat)
            n_kept += 1
        feat = ilayer.GetNextFeature()

    out_ds.FlushCache()
    out_ds = None
    print(
        f"nokitakanto_spatial_filter: attr通過={n_read} 保持={n_kept} マスク交差で除外={n_spatial_drop}",
        file=sys.stderr,
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
