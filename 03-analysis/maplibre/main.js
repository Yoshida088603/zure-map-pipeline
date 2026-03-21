// PMTiles プロトコルを登録（Range リクエスト用）。metadata: true でソースの minzoom/maxzoom を取得
let protocol = new pmtiles.Protocol({ metadata: true });
maplibregl.addProtocol('pmtiles', protocol.tile);
// serve.py がリポジトリルートをドキュメントルートにする場合のデータ URL 基底
var DATA = location.origin + '/data';

// 公図と現況のずれデータは東京付近など全国に分布。初期視点はずれデータの例の座標。
// 庭園路ポリゴンは神戸・大阪付近、工業用地は東京付近。
var map = new maplibregl.Map({
  container: 'map',
  style: 'https://tile.openstreetmap.jp/styles/osm-bright-ja/style.json', // 地図のスタイル
  center: [139.619109, 35.768183], // 公図と現況のずれの例（経度・緯度）
  zoom: 12, // minzoom=0, maxzoom=15 の範囲内
});

// 背景スタイル（osm-bright-ja）で参照される POI アイコンが不足している場合の警告を抑える
map.on('styleimagemissing', (e) => {
  var id = e.id;
  if (!map.hasImage(id)) {
    map.addImage(id, { width: 1, height: 1, data: new Uint8Array([0, 0, 0, 0]) });
  }
});

// ポリゴンデータを表示する
map.on('load', () => {
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

  // PMTiles（公図と現況のずれデータ・マージ済み）。ずれ量 = ランク(前) - ずれ(前) = BFR_RANK - BFR_GOSA で色分け
  var zuzaPmtilesUrl = DATA + '/04-merge-geopackage/公図と現況のずれデータ_merged.pmtiles';
  map.addSource('pmtiles_zuza', {
    type: 'vector',
    url: 'pmtiles://' + zuzaPmtilesUrl,
  });
  // ずれ量（m）で5段階: 10cm未満 / 10cm〜30cm / 30cm〜1m / 1m〜10m / 10m以上 → 表の色
  map.addLayer({
    id: 'pmtiles_zuza_fill',
    type: 'fill',
    source: 'pmtiles_zuza',
    'source-layer': 'kozu_merged',
    filter: ['in', ['geometry-type'], ['literal', ['Polygon', 'MultiPolygon']]],
    paint: {
      'fill-color': [
        'step',
        ['coalesce', ['-', ['get', 'BFR_RANK'], ['get', 'BFR_GOSA']], -1],
        '#cccccc',
        0.1, '#87ceeb',   // 精度の高い地域（10cm未満）
        0.3, '#98fb98',   // 小さなずれ（10cm以上30cm未満）
        1, '#fffacd',     // ずれのある地域（30cm以上1m未満）
        10, '#ffb6c1',    // 大きなずれ（1m以上10m未満）
        '#d3d3d3'         // きわめて大きなずれ（10m以上）
      ],
      'fill-opacity': 0.6,
      'fill-outline-color': 'rgba(0,0,0,0.2)',
    },
  });

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
  map.on('error', (e) => console.error('MapLibre error:', e));
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

// 公図と現況のずれデータ・ポリゴンクリック時: 全属性＋ずれ量（ランク前−ずれ前）を表示
var zuzaLabel = { id: 'ID', ooaza: '大字', koaza: '小字', chiban: '地番', jyotai: '状態', zumen: '図面', PREFCODE: '都道府県コード', CITYCODE: '市区町村コード', BFR_GOSA: 'ずれ(前)', BFR_RANK: 'ランク(前)', AFT_GOSA: 'ずれ(後)', AFT_RANK: 'ランク(後)' };
map.on('click', 'pmtiles_zuza_fill', (e) => {
  var lng = e.lngLat.lng.toFixed(6);
  var lat = e.lngLat.lat.toFixed(6);
  var p = e.features[0].properties;
  var bfrR = p.BFR_RANK != null ? Number(p.BFR_RANK) : null;
  var bfrG = p.BFR_GOSA != null ? Number(p.BFR_GOSA) : null;
  var zuzaRy = (bfrR != null && bfrG != null) ? (bfrR - bfrG).toFixed(3) : '—';
  var p2 = Object.assign({}, p, { zura_ryo: zuzaRy });
  var lab = Object.assign({}, zuzaLabel, { zura_ryo: 'ずれ量（ランク前−ずれ前）' });
  showAttributePanel('公図と現況のずれ', lng, lat, p2, lab, '公図と現況のずれ_属性');
});

// 街区基準点等クリック時: 全属性をドラッグ可能パネルで表示
var gaikuLabel = { 所在地: '所在地', 基準点コード: '基準点コード', 座標系: '座標系', 市区町名: '市区町名', 街区点・補助点名称: '街区点・補助点名称', 標高: '標高', 測量年月日: '測量年月日' };
map.on('click', 'pmtiles_gaiku_circle', (e) => {
  var lng = e.lngLat.lng.toFixed(6);
  var lat = e.lngLat.lat.toFixed(6);
  var p = e.features[0].properties;
  showAttributePanel('街区基準点', lng, lat, p, gaikuLabel, '街区基準点_属性');
});
