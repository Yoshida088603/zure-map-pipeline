/**
 * 系9・公図ずれ PMTiles の maxzoom=13 までの見え方を確認する最小ビューア。
 * 既定: data/05-pmtiles/09kei-other-nokitakanto_0_13.pmtiles（東京・北関東4県+福島除外）
 *
 * クエリ: ?pmtiles=05-pmtiles/別名.pmtiles （/data からの相対。先頭スラッシュ不要）
 */
(function () {
  var params = new URLSearchParams(location.search);
  var pmtilesRel = params.get('pmtiles') || '05-pmtiles/09kei-other-nokitakanto_0_13.pmtiles';

  var protocol = new pmtiles.Protocol({ metadata: true });
  maplibregl.addProtocol('pmtiles', protocol.tile);

  var DATA = location.origin + '/data';
  var pmtilesUrl = DATA + '/' + pmtilesRel.replace(/^\//, '');

  var map = new maplibregl.Map({
    container: 'map',
    style: 'https://tile.openstreetmap.jp/styles/osm-bright-ja/style.json',
    center: [139.45, 35.68],
    zoom: 9,
    minZoom: 0,
    maxZoom: 16,
  });

  map.on('styleimagemissing', function (e) {
    var id = e.id;
    if (!map.hasImage(id)) {
      map.addImage(id, { width: 1, height: 1, data: new Uint8Array([0, 0, 0, 0]) });
    }
  });

  var hud = document.getElementById('z13-hud');
  function refreshHud() {
    var z = map.getZoom();
    hud.innerHTML =
      '<strong>現在 zoom</strong> ' +
      z.toFixed(2) +
      '　<strong>PMTiles</strong> min–max はメタ参照（通常 z0–z13）。<br/>' +
      '<code>' +
      pmtilesRel +
      '</code><br/>' +
      'z13 付近まで拡大し、ラベル・輪郭の破綻がないか確認してください。';
  }
  map.on('load', refreshHud);
  map.on('moveend', refreshHud);

  map.on('load', function () {
    map.addSource('pmtiles_09kei_z13', {
      type: 'vector',
      url: 'pmtiles://' + pmtilesUrl,
    });

    map.addLayer({
      id: 'pmtiles_09kei_z13_fill',
      type: 'fill',
      source: 'pmtiles_09kei_z13',
      'source-layer': 'kozu_merged',
      filter: ['in', ['geometry-type'], ['literal', ['Polygon', 'MultiPolygon']]],
      paint: {
        'fill-color': [
          'step',
          ['coalesce', ['-', ['get', 'BFR_RANK'], ['get', 'BFR_GOSA']], -1],
          '#cccccc',
          0.1,
          '#87ceeb',
          0.3,
          '#98fb98',
          1,
          '#fffacd',
          10,
          '#ffb6c1',
          '#d3d3d3',
        ],
        'fill-opacity': 0.55,
        'fill-outline-color': 'rgba(0,0,0,0.25)',
      },
    });
  });

  function escapeHtml(s) {
    return String(s)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;');
  }

  map.on('click', 'pmtiles_09kei_z13_fill', function (e) {
    var p = e.features[0].properties;
    var rows = [];
    Object.keys(p).forEach(function (k) {
      if (k === 'mvt_id') return;
      rows.push('<tr><th>' + escapeHtml(k) + '</th><td>' + escapeHtml(p[k] != null ? p[k] : '—') + '</td></tr>');
    });
    new maplibregl.Popup({ maxWidth: '360px' })
      .setLngLat(e.lngLat)
      .setHTML('<div class="z13-popup"><table>' + rows.join('') + '</table></div>')
      .addTo(map);
  });

  map.on('error', function (e) {
    console.error('MapLibre error:', e);
  });
})();
