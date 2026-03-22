// PMTiles プロトコルを登録（Range リクエスト用）。metadata: true でソースの minzoom/maxzoom を取得
let protocol = new pmtiles.Protocol({ metadata: true });
maplibregl.addProtocol('pmtiles', protocol.tile);
// serve.py がリポジトリルートをドキュメントルートにする場合のデータ URL 基底
var DATA = location.origin + '/data';

var params = new URLSearchParams(location.search);
// 系別単体検図: ?mode=z12（URL 互換）。PMTiles のタイルは z0–11 まで。地図の maxZoom は高めにし overzoom で拡大操作可能にする。
// 既定 PMTiles: 47-geopackage-per-kei2pmtiles.sh が geopackage_per_kei/NN.gpkg → 05-pmtiles/NN.pmtiles
// ?kei=09 で 05-pmtiles/09.pmtiles、?pmtiles= で任意パス（data/ からの相対）
var _mode = params.get('mode');
var isZ12KeiMode = _mode === 'z12' || _mode === 'z13';
// data/05-pmtiles の系別ずれ PMTiles（47 出力）をまとめて表示
var isAllKeiPmtilesMode = _mode === 'all-kei' || _mode === 'allkei';
/** 現行ビルドのファイル名（14 系が無い場合はスキップ。増えたらここに追加） */
var ALL_KEI_PMTILES_STEMS = ['01', '02', '03', '04', '05', '06', '07', '08', '09', '10', '11', '12', '13', '15'];
var _kei = params.get('kei');
var _keiStem = _kei && /^[0-9]{2}$/.test(_kei) ? _kei : null;
var z12KeiPmtilesRel =
  params.get('pmtiles') || (_keiStem ? '05-pmtiles/' + _keiStem + '.pmtiles' : '05-pmtiles/09.pmtiles');

function z12KeiLogLine(msg, err) {
  var line = msg + (err && err.message != null ? ': ' + err.message : err ? ': ' + String(err) : '');
  console.error(line);
  var el = document.getElementById('z12-kei-console');
  if (el) {
    el.textContent = el.textContent ? el.textContent + '\n' + line : line;
  }
}

if (isZ12KeiMode || isAllKeiPmtilesMode) {
  document.body.classList.add('mode-z12-kei');
  window.addEventListener('error', function (ev) {
    z12KeiLogLine('window.error', ev.error || ev.message);
  });
  window.addEventListener('unhandledrejection', function (ev) {
    z12KeiLogLine('unhandledrejection', ev.reason);
  });
  if (location.protocol === 'file:') {
    z12KeiLogLine('file:// 不可。serve.py 起動後 http://localhost:8080/03-analysis/maplibre/index.html を開く');
  }
  var z12Hud = document.getElementById('z12-kei-hud');
  if (z12Hud) {
    if (isAllKeiPmtilesMode) {
      z12Hud.textContent =
        '全系: data/05-pmtiles の ' +
        ALL_KEI_PMTILES_STEMS.length +
        ' 本（' +
        ALL_KEI_PMTILES_STEMS.join(', ') +
        '）・タイル z0–11・overzoom 可';
    } else {
      z12Hud.textContent =
        'PMTiles: ' +
          z12KeiPmtilesRel +
          '（タイル z0–11・地図は overzoom で拡大可。?kei=09 / ?pmtiles=…）';
    }
  }
}

// 公図と現況のずれデータは東京付近など全国に分布。初期視点はずれデータの例の座標。
// 庭園路ポリゴンは神戸・大阪付近、工業用地は東京付近。
// ?mode=z12 … ベクタは PMTiles（z11 まで）。maxZoom は 22 にしてホイール／ピンチで拡大続行（z11 タイルの overzoom）
var map = new maplibregl.Map({
  container: 'map',
  style: 'https://tile.openstreetmap.jp/styles/osm-bright-ja/style.json', // 地図のスタイル
  center: isZ12KeiMode || isAllKeiPmtilesMode ? (isAllKeiPmtilesMode ? [137.5, 36.2] : [139.45, 35.68]) : [139.619109, 35.768183],
  zoom: isAllKeiPmtilesMode ? 5.2 : isZ12KeiMode ? 8 : 12,
  minZoom: 0,
  maxZoom: 22,
});

// 背景スタイル（osm-bright-ja）で参照される POI アイコンが不足している場合の警告を抑える
map.on('styleimagemissing', (e) => {
  var id = e.id;
  if (!map.hasImage(id)) {
    map.addImage(id, { width: 1, height: 1, data: new Uint8Array([0, 0, 0, 0]) });
  }
});

map.on('error', (e) => {
  console.error('MapLibre error:', e);
  if (isZ12KeiMode || isAllKeiPmtilesMode) {
    z12KeiLogLine('MapLibre map.error', e.error || e);
  }
});

// 色分けの入力（m）= BFR_GOSA（ずれ・前）。BFR_RANK は 1〜5 の区分コードであり RANK−GOSA はメートルにならない（凡例と一致しない）
// 欠落・負値（想定外センチネル）は #bdbdbd。凡例: docs/legend-zure-deviation.md
var zureDeviationFillColor = [
  'case',
  ['any', ['!', ['has', 'BFR_GOSA']], ['<', ['to-number', ['get', 'BFR_GOSA']], 0]],
  '#bdbdbd',
  [
    'step',
    ['to-number', ['get', 'BFR_GOSA']],
    '#87ceeb',
    0.1, '#98fb98',
    0.3, '#fffacd',
    1, '#ffb6c1',
    10, '#9e9e9e',
  ],
];

var keiZureFillPaint = {
  'fill-color': zureDeviationFillColor,
  'fill-opacity': 0.55,
  'fill-outline-color': 'rgba(0,0,0,0.15)',
};

/** クリック選択ポリゴン（ずれデータ）の上乗せ。凡例色と区別できるオレンジ系 */
var zureSelectedFillPaint = {
  'fill-color': '#ff6f00',
  'fill-opacity': 0.42,
  'fill-outline-color': '#bf360c',
};

var allKeiFillLayerIds = [];
/** 各系の選択ハイライトレイヤ id（クリア時にまとめて無効化） */
var zureHighlightLayerIds = [];
/** 地図空白クリックで選択解除するときのヒットテスト対象（fill 本体） */
var zureHitTestFillLayerIds = [];
var zureMapClickClearInstalled = false;
var zurePolygonGeomFilter = ['in', ['geometry-type'], ['literal', ['Polygon', 'MultiPolygon']]];

function zureHighlightNeverMatchFilter() {
  return ['all', zurePolygonGeomFilter, ['==', ['literal', 1], 0]];
}

function buildZurePropertyFilter(props) {
  if (!props) return ['==', ['literal', 1], 0];
  var parts = [];
  function addEqNum(key) {
    if (props[key] == null || props[key] === '') return;
    var n = Number(props[key]);
    if (Number.isNaN(n)) return;
    parts.push(['==', ['to-number', ['get', key]], n]);
  }
  function addEqStr(key) {
    if (props[key] == null || props[key] === '') return;
    parts.push(['==', ['get', key], String(props[key])]);
  }
  addEqNum('PREFCODE');
  addEqNum('CITYCODE');
  addEqNum('ooaza');
  addEqNum('koaza');
  addEqNum('jyotai');
  addEqStr('chiban');
  addEqStr('zumen');
  if (props.id != null && props.id !== '') {
    var idn = Number(props.id);
    if (!Number.isNaN(idn)) parts.push(['==', ['to-number', ['get', 'id']], idn]);
  }
  if (parts.length === 0) return ['==', ['literal', 1], 0];
  if (parts.length === 1) return parts[0];
  return ['all'].concat(parts);
}

function buildZureHighlightFilter(props) {
  return ['all', zurePolygonGeomFilter, buildZurePropertyFilter(props)];
}

function clearZureSelectionHighlight() {
  var never = zureHighlightNeverMatchFilter();
  zureHighlightLayerIds.forEach(function (id) {
    if (map.getLayer(id)) map.setFilter(id, never);
  });
}

function setZureSelectionHighlight(highlightLayerId, props) {
  clearZureSelectionHighlight();
  if (!map.getLayer(highlightLayerId)) return;
  map.setFilter(highlightLayerId, buildZureHighlightFilter(props));
}

function installZureSelectionClearOnMapClick() {
  if (zureMapClickClearInstalled) return;
  zureMapClickClearInstalled = true;
  map.on('click', function (e) {
    if (!zureHitTestFillLayerIds.length) return;
    var hit = map.queryRenderedFeatures(e.point, { layers: zureHitTestFillLayerIds });
    if (!hit.length) clearZureSelectionHighlight();
  });
}

function installZureHoverCursor(layerIds) {
  layerIds.forEach(function (lid) {
    map.on('mouseenter', lid, function () {
      map.getCanvas().style.cursor = 'pointer';
    });
    map.on('mouseleave', lid, function () {
      map.getCanvas().style.cursor = '';
    });
  });
}

map.on('load', () => {
  if (isAllKeiPmtilesMode) {
    zureHighlightLayerIds = [];
    ALL_KEI_PMTILES_STEMS.forEach(function (stem) {
      var sid = 'pmtiles_kei_' + stem;
      var lid = sid + '_fill';
      var hlid = sid + '_selected';
      var url = DATA + '/05-pmtiles/' + stem + '.pmtiles';
      map.addSource(sid, {
        type: 'vector',
        url: 'pmtiles://' + url,
      });
      map.addLayer({
        id: lid,
        type: 'fill',
        source: sid,
        'source-layer': 'kozu_merged',
        filter: ['in', ['geometry-type'], ['literal', ['Polygon', 'MultiPolygon']]],
        paint: keiZureFillPaint,
      });
      map.addLayer({
        id: hlid,
        type: 'fill',
        source: sid,
        'source-layer': 'kozu_merged',
        filter: zureHighlightNeverMatchFilter(),
        paint: zureSelectedFillPaint,
      });
      allKeiFillLayerIds.push(lid);
      zureHighlightLayerIds.push(hlid);
    });
    zureHitTestFillLayerIds = allKeiFillLayerIds.slice();
    installZureSelectionClearOnMapClick();
    installZureHoverCursor(allKeiFillLayerIds);
    return;
  }

  if (isZ12KeiMode) {
    var z12KeiUrl = DATA + '/' + z12KeiPmtilesRel.replace(/^\//, '');
    map.addSource('pmtiles_09kei_z12', {
      type: 'vector',
      url: 'pmtiles://' + z12KeiUrl,
    });
    map.addLayer({
      id: 'pmtiles_09kei_z12_fill',
      type: 'fill',
      source: 'pmtiles_09kei_z12',
      'source-layer': 'kozu_merged',
      filter: ['in', ['geometry-type'], ['literal', ['Polygon', 'MultiPolygon']]],
      paint: Object.assign({}, keiZureFillPaint, { 'fill-opacity': 0.6 }),
    });
    map.addLayer({
      id: 'pmtiles_09kei_z12_selected',
      type: 'fill',
      source: 'pmtiles_09kei_z12',
      'source-layer': 'kozu_merged',
      filter: zureHighlightNeverMatchFilter(),
      paint: Object.assign({}, zureSelectedFillPaint, { 'fill-opacity': 0.48 }),
    });
    zureHighlightLayerIds = ['pmtiles_09kei_z12_selected'];
    zureHitTestFillLayerIds = ['pmtiles_09kei_z12_fill'];
    installZureSelectionClearOnMapClick();
    installZureHoverCursor(['pmtiles_09kei_z12_fill']);
    return;
  }

  // 既存: GeoJSON（工業用地）
  map.addSource('industrial_area', {
    type: 'geojson',
    data: DATA + '/06-analysis-result/polygon.geojson',
  });
  map.addLayer({
    id: 'industrial_area',
    type: 'fill',
    source: 'industrial_area',
    layout: {},
    paint: {
      'fill-color': '#FD7E00',
      'fill-opacity': 0.8,
    },
  });

  // PMTiles（庭園路ポリゴン）。絶対 URL で Range リクエストを有効にする
  var pmtilesBaseUrl = DATA + '/05-pmtiles/庭園路ポリゴン.pmtiles';
  if (typeof console !== 'undefined' && console.debug) console.debug('PMTiles URL:', pmtilesBaseUrl, 'source-layer: 庭園路ポリゴン');
  map.addSource('pmtiles_tunnel', {
    type: 'vector',
    url: 'pmtiles://' + pmtilesBaseUrl,
  });
  // source-layer: GDAL 出力 PMTiles のレイヤ名（ogrinfo -al -so xxx.pmtiles で確認）
  // ポリゴン・マルチポリゴンのみ表示（ベクタタイルのジオメトリ種別を明示）
  map.addLayer({
    id: 'pmtiles_tunnel_fill',
    type: 'fill',
    source: 'pmtiles_tunnel',
    'source-layer': '庭園路ポリゴン',
    filter: ['in', ['geometry-type'], ['literal', ['Polygon', 'MultiPolygon']]],
    paint: {
      'fill-color': '#3388ff',
      'fill-opacity': 0.7,
      'fill-outline-color': '#0066cc',
    },
  });

  // PMTiles（管理三角点・点）。bounds: 129.07,32.80 - 129.92,32.83（長崎付近）。地図を西へパンすると見える。
  var takakutenPmtilesUrl = DATA + '/05-pmtiles/kanri_takakuten_pt.pmtiles';
  map.addSource('pmtiles_takakuten', {
    type: 'vector',
    url: 'pmtiles://' + takakutenPmtilesUrl,
  });
  map.addLayer({
    id: 'pmtiles_takakuten_circle',
    type: 'circle',
    source: 'pmtiles_takakuten',
    'source-layer': 'kanri_takakuten_pt',
    paint: {
      'circle-radius': 6,
      'circle-color': '#e74c3c',
      'circle-stroke-width': 1,
      'circle-stroke-color': '#c0392b',
    },
  });

  // PMTiles（14条地図・ポリゴン）。bounds: 127.66,26.19 - 145.61,44.37（全国）、約7906件
  var jyuchizuPmtilesUrl = DATA + '/05-pmtiles/14条地図.pmtiles';
  map.addSource('pmtiles_jyuchizu', {
    type: 'vector',
    url: 'pmtiles://' + jyuchizuPmtilesUrl,
  });
  map.addLayer({
    id: 'pmtiles_jyuchizu_fill',
    type: 'fill',
    source: 'pmtiles_jyuchizu',
    'source-layer': '14条地図',
    filter: ['in', ['geometry-type'], ['literal', ['Polygon', 'MultiPolygon']]],
    paint: {
      'fill-color': '#27ae60',
      'fill-opacity': 0.5,
      'fill-outline-color': '#1e8449',
    },
  });

  // PMTiles（公図と現況のずれデータ・マージ済み）。塗り分けは BFR_GOSA（m）。ランクは BFR_RANK（1〜5）
  var zurePmtilesUrl = DATA + '/04-merge-geopackage/公図と現況のずれデータ_merged.pmtiles';
  map.addSource('pmtiles_zure', {
    type: 'vector',
    url: 'pmtiles://' + zurePmtilesUrl,
  });
  // ずれ量（m）5段階 + 属性欠落: docs/legend-zure-deviation.md
  map.addLayer({
    id: 'pmtiles_zure_fill',
    type: 'fill',
    source: 'pmtiles_zure',
    'source-layer': 'kozu_merged',
    filter: ['in', ['geometry-type'], ['literal', ['Polygon', 'MultiPolygon']]],
    paint: {
      'fill-color': zureDeviationFillColor,
      'fill-opacity': 0.6,
      'fill-outline-color': 'rgba(0,0,0,0.2)',
    },
  });
  map.addLayer({
    id: 'pmtiles_zure_selected',
    type: 'fill',
    source: 'pmtiles_zure',
    'source-layer': 'kozu_merged',
    filter: zureHighlightNeverMatchFilter(),
    paint: zureSelectedFillPaint,
  });
  zureHighlightLayerIds = ['pmtiles_zure_selected'];
  zureHitTestFillLayerIds = ['pmtiles_zure_fill'];
  installZureSelectionClearOnMapClick();
  installZureHoverCursor(['pmtiles_zure_fill']);

  // PMTiles（土地活用推進調査・マージ済み）。bounds: 約114.5,32.2 - 142.2,44.1（全国）
  var tochiPmtilesUrl = DATA + '/04-merge-geopackage/土地活用推進調査_merged.pmtiles';
  map.addSource('pmtiles_tochi', {
    type: 'vector',
    url: 'pmtiles://' + tochiPmtilesUrl,
  });
  map.addLayer({
    id: 'pmtiles_tochi_fill',
    type: 'fill',
    source: 'pmtiles_tochi',
    'source-layer': 'tochi_merged',
    filter: ['in', ['geometry-type'], ['literal', ['Polygon', 'MultiPolygon']]],
    paint: {
      'fill-color': '#9b59b6',
      'fill-opacity': 0.5,
      'fill-outline-color': '#6c3483',
    },
  });
  map.addLayer({
    id: 'pmtiles_tochi_circle',
    type: 'circle',
    source: 'pmtiles_tochi',
    'source-layer': 'tochi_merged',
    filter: ['in', ['geometry-type'], ['literal', ['Point', 'MultiPoint']]],
    paint: {
      'circle-radius': 4,
      'circle-color': '#9b59b6',
      'circle-stroke-width': 1,
      'circle-stroke-color': '#6c3483',
    },
  });

  // 1件だけの CSV から作った PMTiles（single_csv_to_pmtiles.sh で生成した TH_23521.pmtiles など）
  var tochiSingleBase = 'TH_23521.pmtiles';
  var tochiSingleUrl = DATA + '/04-merge-geopackage/' + tochiSingleBase;
  map.addSource('pmtiles_tochi_single', {
    type: 'vector',
    url: 'pmtiles://' + tochiSingleUrl,
  });
  map.addLayer({
    id: 'pmtiles_tochi_single_circle',
    type: 'circle',
    source: 'pmtiles_tochi_single',
    'source-layer': 'tochi_merged',
    paint: {
      'circle-radius': 6,
      'circle-color': '#e67e22',
      'circle-stroke-width': 2,
      'circle-stroke-color': '#d35400',
    },
  });

  // PMTiles（街区基準点等データ・全件マージ）。merge_gaiku_geopackage.sh + gpkg_to_pmtiles.sh で生成
  var gaikuPmtilesUrl = DATA + '/04-merge-geopackage/街区基準点等_merged.pmtiles';
  map.addSource('pmtiles_gaiku', {
    type: 'vector',
    url: 'pmtiles://' + gaikuPmtilesUrl,
  });
  map.addLayer({
    id: 'pmtiles_gaiku_circle',
    type: 'circle',
    source: 'pmtiles_gaiku',
    'source-layer': 'gaiku_merged',
    paint: {
      'circle-radius': 5,
      'circle-color': '#3498db',
      'circle-stroke-width': 1,
      'circle-stroke-color': '#2980b9',
    },
  });

  // PMTiles（都市部官民基準点等・TKS_04206 白石市）。bounds: 約140.63,38.00（宮城県白石市付近）
  var tks04206PmtilesUrl = DATA + '/04-merge-geopackage/TKS_04206.pmtiles';
  map.addSource('pmtiles_tks04206', {
    type: 'vector',
    url: 'pmtiles://' + tks04206PmtilesUrl,
  });
  map.addLayer({
    id: 'pmtiles_tks04206_circle',
    type: 'circle',
    source: 'pmtiles_tks04206',
    'source-layer': 'merged',
    paint: {
      'circle-radius': 6,
      'circle-color': '#16a085',
      'circle-stroke-width': 1,
      'circle-stroke-color': '#0e6655',
    },
  });

  // PMTiles（都市部官民基準点等・全件マージ）。merge_toshi_geopackage.sh + gpkg_to_pmtiles.sh で生成
  var toshiMergedPmtilesUrl = DATA + '/04-merge-geopackage/都市部官民基準点等_merged.pmtiles';
  map.addSource('pmtiles_toshi_merged', {
    type: 'vector',
    url: 'pmtiles://' + toshiMergedPmtilesUrl,
  });
  map.addLayer({
    id: 'pmtiles_toshi_merged_circle',
    type: 'circle',
    source: 'pmtiles_toshi_merged',
    'source-layer': 'toshi_merged',
    paint: {
      'circle-radius': 5,
      'circle-color': '#ff00ff',
      'circle-stroke-width': 1,
      'circle-stroke-color': '#c71585',
    },
  });

  // デバッグ: ソースのロード成否をコンソールで確認
  map.on('sourcedata', (e) => {
    if (e.sourceId === 'pmtiles_tunnel' && e.sourceDataType === 'metadata') {
      console.log('PMTiles source metadata loaded');
    }
    if (e.sourceId === 'pmtiles_tunnel' && e.isSourceLoaded) {
      console.log('PMTiles source fully loaded');
    }
  });
});

// 工業用地クリック時: 全属性をドラッグ可能パネルで表示
map.on('click', 'industrial_area', (e) => {
  var lng = e.lngLat.lng.toFixed(6);
  var lat = e.lngLat.lat.toFixed(6);
  var p = e.features[0].properties;
  showAttributePanel('工業用地', lng, lat, p, { L05_002: '名称' }, '工業用地_属性');
});

// 管理三角点クリック時: 全属性をドラッグ可能パネルで表示
var takakutenLabel = {
  meisyo: '名称', syozaiti: '所在地', kijyunten_cd: '基準点コード', sokuryo_nengappi: '測量年月日',
  x: '座標系X', y: '座標系Y', b: '緯度b', l: '経度l', jibandaka: '楕円体高', antenna_daka: 'アンテナ高',
  id: 'ID', haiten: '配点', sikutyo_cd: '測地系コード', sikutyo: '測地系', syubetu_cd: '種別コード',
  zahyokei_cd: '座標系コード', sokutikei_cd: '測地系コード2', hosei_x: '補正X', hosei_y: '補正Y',
  hyoko: '標高', hosei_hyoko: '補正標高', geoid: 'ジオイド', syukusyaku_keisu: '縮尺係数', n: 'n',
  zaisitu_cd: '在処コード', sokutei_housiki_cd: '測定方式コード', genkyo_timoku_cd: '現況科目コード',
  antenna_iti_cd: 'アンテナ位置コード', setti_cd: '設置コード', yobi: '予備',
};
map.on('click', 'pmtiles_takakuten_circle', (e) => {
  var lng = e.lngLat.lng.toFixed(6);
  var lat = e.lngLat.lat.toFixed(6);
  var p = e.features[0].properties;
  showAttributePanel('管理三角点', lng, lat, p, takakutenLabel, '管理三角点_属性');
});

// 14条地図ポリゴンクリック時: 全属性をドラッグ可能パネルで表示
map.on('click', 'pmtiles_jyuchizu_fill', (e) => {
  var lng = e.lngLat.lng.toFixed(6);
  var lat = e.lngLat.lat.toFixed(6);
  var p = e.features[0].properties;
  showAttributePanel('14条完了エリア', lng, lat, p, { ID: 'ID', AREA: 'AREA' }, '14条地図_属性');
});

// 全レイヤ共通: ドラッグ可能な属性パネル（全属性表示・CSVダウンロード）
var tochiLabel = {
  col0: 'col0', col1: '市町村コード', col2: '市区町村名', col3: 'col3', col4: 'col4', col5: '座標系',
  col6: 'col6', x: 'X', y: 'Y', col9: 'col9', col10: 'col10', col11: '住所等', col12: 'col12',
  col13: '調査日等', col14: 'col14', col15: 'col15', col16: 'col16',
};
var attrDownloadData = {};
function csvEscape(v) {
  var s = String(v);
  if (/[,\n"]/.test(s)) return '"' + s.replace(/"/g, '""') + '"';
  return s;
}
var attrPanel = null;
var attrPanelDrag = { active: false, startX: 0, startY: 0, startLeft: 0, startTop: 0 };

function ensureAttrPanel() {
  if (attrPanel) return attrPanel;
  var panel = document.createElement('div');
  panel.className = 'tochi-panel';
  panel.style.left = '20px';
  panel.style.top = '20px';
  panel.innerHTML =
    '<div class="tochi-panel-header">' +
    '<span class="tochi-panel-title">属性情報</span>' +
    '<button type="button" class="tochi-download-btn">CSVでダウンロード</button>' +
    '<button type="button" class="tochi-panel-close" aria-label="閉じる">×</button>' +
    '</div>' +
    '<div class="tochi-panel-body"></div>';
  document.body.appendChild(panel);
  var header = panel.querySelector('.tochi-panel-header');
  header.addEventListener('mousedown', function (ev) {
    if (ev.target.closest('button')) return;
    attrPanelDrag.active = true;
    attrPanelDrag.startX = ev.clientX;
    attrPanelDrag.startY = ev.clientY;
    attrPanelDrag.startLeft = parseInt(panel.style.left, 10) || 0;
    attrPanelDrag.startTop = parseInt(panel.style.top, 10) || 0;
  });
  panel.querySelector('.tochi-panel-close').addEventListener('click', function () {
    panel.classList.remove('is-visible');
  });
  document.addEventListener('mousemove', function (ev) {
    if (!attrPanelDrag.active) return;
    panel.style.left = (attrPanelDrag.startLeft + ev.clientX - attrPanelDrag.startX) + 'px';
    panel.style.top = (attrPanelDrag.startTop + ev.clientY - attrPanelDrag.startY) + 'px';
  });
  document.addEventListener('mouseup', function () {
    attrPanelDrag.active = false;
  });
  document.body.addEventListener('click', function (ev) {
    var btn = ev.target && ev.target.closest && ev.target.closest('.tochi-download-btn');
    if (!btn || !btn.closest('.tochi-panel') || !btn.dataset.downloadId) return;
    var data = attrDownloadData[btn.dataset.downloadId];
    if (!data || !data.csv) return;
    var a = document.createElement('a');
    a.href = URL.createObjectURL(new Blob([data.csv], { type: 'text/csv;charset=utf-8' }));
    a.download = (data.filename || '属性') + '_' + (new Date().toISOString().slice(0, 19).replace(/[:-]/g, '')) + '.csv';
    a.click();
    URL.revokeObjectURL(a.href);
    delete attrDownloadData[btn.dataset.downloadId];
  });
  attrPanel = panel;
  return panel;
}

function showAttributePanel(title, lng, lat, properties, labelMap, downloadFilename) {
  var fmt = (v) => (v != null && v !== '') ? String(v) : '—';
  var rows = [['経度', lng], ['緯度', lat]];
  Object.keys(properties).forEach(function (k) {
    if (k === 'mvt_id') return;
    rows.push([(labelMap && labelMap[k]) || k, fmt(properties[k])]);
  });
  var csvLines = [['項目', '値']].concat(rows).map(function (r) { return csvEscape(r[0]) + ',' + csvEscape(r[1]); });
  var csvString = '\uFEFF' + csvLines.join('\n');
  var downloadId = 'attr-' + Date.now() + '-' + Math.random().toString(36).slice(2);
  attrDownloadData[downloadId] = { csv: csvString, filename: downloadFilename || '属性' };

  var tableRows = rows.map(function (r) { return '<tr><th>' + r[0] + '</th><td>' + r[1] + '</td></tr>'; });
  var bodyHtml = '<p><strong>座標</strong> 経度 ' + lng + ' / 緯度 ' + lat + '</p><table><tbody>' + tableRows.join('') + '</tbody></table>';

  var panel = ensureAttrPanel();
  panel.querySelector('.tochi-panel-title').textContent = title;
  panel.querySelector('.tochi-panel-body').innerHTML = bodyHtml;
  panel.querySelector('.tochi-download-btn').dataset.downloadId = downloadId;
  panel.style.left = '20px';
  panel.style.top = '20px';
  panel.classList.add('is-visible');
}

function showTochiPopup(e) {
  var lng = e.lngLat.lng.toFixed(6);
  var lat = e.lngLat.lat.toFixed(6);
  var p = e.features[0].properties;
  showAttributePanel('土地活用推進調査', lng, lat, p, tochiLabel, '土地活用推進調査_属性');
}

map.on('click', 'pmtiles_tochi_circle', showTochiPopup);
map.on('click', 'pmtiles_tochi_fill', showTochiPopup);
map.on('click', 'pmtiles_tochi_single_circle', showTochiPopup);

// 都市部官民基準点等（TKS_04206）クリック時: 全属性をドラッグ可能パネルで表示
var tks04206Label = { 市区町名: '市区町名', 所在地: '所在地', 基準点等名称: '基準点等名称', 基準点コード: '基準点コード', 座標系: '座標系', 標高: '標高', 測量年月日: '測量年月日', 基準点等の種別: '基準点等の種別' };
map.on('click', 'pmtiles_tks04206_circle', (e) => {
  var lng = e.lngLat.lng.toFixed(6);
  var lat = e.lngLat.lat.toFixed(6);
  var p = e.features[0].properties;
  showAttributePanel('都市部官民基準点', lng, lat, p, tks04206Label, '都市部官民基準点_属性');
});

// 都市部官民基準点等（マージ）クリック時: 全属性をドラッグ可能パネルで表示
map.on('click', 'pmtiles_toshi_merged_circle', (e) => {
  var lng = e.lngLat.lng.toFixed(6);
  var lat = e.lngLat.lat.toFixed(6);
  var p = e.features[0].properties;
  showAttributePanel('都市部官民基準点（マージ）', lng, lat, p, tks04206Label, '都市部官民基準点_マージ_属性');
});

// 公図と現況のずれデータ・ポリゴンクリック時: 全属性（地図の色は ずれ(前) BFR_GOSA m に連動）
var zureLabel = { id: 'ID', ooaza: '大字', koaza: '小字', chiban: '地番', jyotai: '状態', zumen: '図面', PREFCODE: '都道府県コード', CITYCODE: '市区町村コード', BFR_GOSA: 'ずれ(前)', BFR_RANK: 'ランク(前)', AFT_GOSA: 'ずれ(後)', AFT_RANK: 'ランク(後)' };
map.on('click', 'pmtiles_zure_fill', (e) => {
  var lng = e.lngLat.lng.toFixed(6);
  var lat = e.lngLat.lat.toFixed(6);
  var p = e.features[0].properties;
  setZureSelectionHighlight('pmtiles_zure_selected', p);
  showAttributePanel('公図と現況のずれ', lng, lat, p, zureLabel, '公図と現況のずれ_属性');
});

// 街区基準点等クリック時: 全属性をドラッグ可能パネルで表示
var gaikuLabel = { 所在地: '所在地', 基準点コード: '基準点コード', 座標系: '座標系', 市区町名: '市区町名', 街区点・補助点名称: '街区点・補助点名称', 標高: '標高', 測量年月日: '測量年月日' };
map.on('click', 'pmtiles_gaiku_circle', (e) => {
  var lng = e.lngLat.lng.toFixed(6);
  var lat = e.lngLat.lat.toFixed(6);
  var p = e.features[0].properties;
  showAttributePanel('街区基準点', lng, lat, p, gaikuLabel, '街区基準点_属性');
});

if (isZ12KeiMode) {
  map.on('click', 'pmtiles_09kei_z12_fill', (e) => {
    var lng = e.lngLat.lng.toFixed(6);
    var lat = e.lngLat.lat.toFixed(6);
    var p = e.features[0].properties;
    setZureSelectionHighlight('pmtiles_09kei_z12_selected', p);
    showAttributePanel('公図と現況のずれ（z0–11 検図）', lng, lat, p, zureLabel, '公図と現況のずれ_z12_属性');
  });
}

if (isAllKeiPmtilesMode) {
  map.on('click', (e) => {
    var feats = map.queryRenderedFeatures(e.point, { layers: allKeiFillLayerIds });
    if (!feats.length) return;
    var top = feats[0];
    var lid = top.layer.id;
    var stem = lid.replace(/^pmtiles_kei_/, '').replace(/_fill$/, '');
    var lng = e.lngLat.lng.toFixed(6);
    var lat = e.lngLat.lat.toFixed(6);
    var p = top.properties;
    setZureSelectionHighlight('pmtiles_kei_' + stem + '_selected', p);
    showAttributePanel('公図と現況のずれ（系' + stem + '・重畳）', lng, lat, p, zureLabel, '公図と現況のずれ_全系_' + stem);
  });
}
