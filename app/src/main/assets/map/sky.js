/*
 * Sky Monitor Iraq — 3D globe map (MapLibre GL JS 5).
 * Kotlin drives this page through window.sky.*; the page reports back through window.Android.*.
 * Aircraft move smoothly here between public reports (dead reckoning from speed + heading).
 */
(function () {
  'use strict';

  var KIND_COLORS = ['#35F0A2', '#FFB547', '#7FB8D6', '#FF4D5E']; // civil, publicly-flagged other, unclassified, watched type
  var bridge = window.Android || { onReady: function () {}, onSelect: function () {}, onViewport: function () {} };

  try { maplibregl.setRTLTextPlugin('rtl.js', false); } catch (e) { /* already set */ }

  // ---------- state pushed from Kotlin ----------
  var planes = [];      // [hex, lat, lon, track, knots, posTimeMs, onGround(0/1), kind(0..3), name]
  var trails = {};      // hex -> [[lat, lon], ...]
  var selected = null;  // hex
  var track = null;     // [[lat, lon], ...] full path since take-off when published
  var route = null;     // {o:{lat,lon,label}, d:{lat,lon,label}}
  var tilted = true;
  var mode = 'SATELLITE';
  var ready = false;

  // ---------- geometry ----------
  var R = 6371.0, D2R = Math.PI / 180;
  function project(lat, lon, deg, km) {
    var d = km / R, b = deg * D2R, p1 = lat * D2R, l1 = lon * D2R;
    var p2 = Math.asin(Math.sin(p1) * Math.cos(d) + Math.cos(p1) * Math.sin(d) * Math.cos(b));
    var l2 = l1 + Math.atan2(Math.sin(b) * Math.sin(d) * Math.cos(p1), Math.cos(d) - Math.sin(p1) * Math.sin(p2));
    return [p2 / D2R, ((l2 / D2R + 540) % 360) - 180];
  }
  function live(p, now) {
    var trk = p[3], kt = p[4];
    if (trk == null || kt == null || p[6] || kt < 30) return [p[1], p[2]];
    var hrs = Math.min(Math.max(now - p[5], 0), 120000) / 3600000;
    return project(p[1], p[2], trk, kt * 1.852 * hrs);
  }
  /** Great-circle path a→b ([lat,lon]) as GeoJSON [lon,lat] list with longitudes kept continuous. */
  function greatCircle(a, b, n) {
    var la1 = a[0] * D2R, lo1 = a[1] * D2R, la2 = b[0] * D2R, lo2 = b[1] * D2R;
    var x1 = Math.cos(la1) * Math.cos(lo1), y1 = Math.cos(la1) * Math.sin(lo1), z1 = Math.sin(la1);
    var x2 = Math.cos(la2) * Math.cos(lo2), y2 = Math.cos(la2) * Math.sin(lo2), z2 = Math.sin(la2);
    var w = Math.acos(Math.max(-1, Math.min(1, x1 * x2 + y1 * y2 + z1 * z2)));
    if (w < 1e-6) return [[a[1], a[0]], [b[1], b[0]]];
    var out = [], prev = null;
    for (var i = 0; i <= n; i++) {
      var t = i / n, s1 = Math.sin((1 - t) * w) / Math.sin(w), s2 = Math.sin(t * w) / Math.sin(w);
      var x = s1 * x1 + s2 * x2, y = s1 * y1 + s2 * y2, z = s1 * z1 + s2 * z2;
      var lat = Math.atan2(z, Math.sqrt(x * x + y * y)) / D2R, lon = Math.atan2(y, x) / D2R;
      if (prev != null) { while (lon - prev > 180) lon -= 360; while (lon - prev < -180) lon += 360; }
      out.push([lon, lat]); prev = lon;
    }
    return out;
  }
  function distKm(a, b) {
    var dLat = (b[0] - a[0]) * D2R, dLon = (b[1] - a[1]) * D2R;
    var h = Math.sin(dLat / 2) * Math.sin(dLat / 2) + Math.cos(a[0] * D2R) * Math.cos(b[0] * D2R) * Math.sin(dLon / 2) * Math.sin(dLon / 2);
    return 2 * R * Math.asin(Math.sqrt(h));
  }
  function ll(p) { return [p[1], p[0]]; }
  function fc(features) { return { type: 'FeatureCollection', features: features }; }
  function line(coords, props) { return { type: 'Feature', properties: props || {}, geometry: { type: 'LineString', coordinates: coords } }; }
  function point(lonlat, props) { return { type: 'Feature', properties: props || {}, geometry: { type: 'Point', coordinates: lonlat } }; }

  // ---------- realistic aircraft glyphs (nose north) ----------
  var DPR = Math.max(1, Math.min(3, window.devicePixelRatio || 1));
  function glyph(color, kind) {
    var size = Math.round(56 * DPR), c = document.createElement('canvas');
    c.width = c.height = size;
    var g = c.getContext('2d'); g.scale(size / 100, size / 100);
    var selectedRing = kind === 'selected';
    var halo = g.createRadialGradient(50, 50, 0, 50, 50, 46);
    halo.addColorStop(0.25, hexA(color, selectedRing ? 0.55 : 0.38)); halo.addColorStop(1, hexA(color, 0));
    g.fillStyle = halo; g.beginPath(); g.arc(50, 50, 46, 0, Math.PI * 2); g.fill();
    if (selectedRing) { g.strokeStyle = color; g.lineWidth = 2.4; g.beginPath(); g.arc(50, 50, 44, 0, Math.PI * 2); g.stroke(); }
    g.strokeStyle = 'rgba(26,35,40,0.8)'; g.lineWidth = 1.1; g.lineJoin = 'round';
    var wingFill = g.createLinearGradient(0, 38, 0, 66); wingFill.addColorStop(0, '#F2F5F7'); wingFill.addColorStop(1, '#AFBAC0');
    var bodyFill = g.createLinearGradient(36, 4, 64, 97); bodyFill.addColorStop(0, '#FFFFFF'); bodyFill.addColorStop(0.5, '#DDE4E8'); bodyFill.addColorStop(1, '#AEB9BF');
    function shape(pts, fill) { g.beginPath(); g.moveTo(pts[0], pts[1]); for (var i = 2; i < pts.length; i += 2) g.lineTo(pts[i], pts[i + 1]); g.closePath(); g.fillStyle = fill; g.fill(); g.stroke(); }
    if (kind === 'drone') {
      shape([47, 38, 3, 42, 3, 46, 47, 46, 53, 46, 97, 46, 97, 42, 53, 38], wingFill);
      shape([48, 80, 34, 92, 36, 94, 49, 86, 51, 86, 64, 94, 66, 92, 52, 80], wingFill);
      g.beginPath(); g.moveTo(50, 8); g.bezierCurveTo(56, 9, 57, 18, 55.5, 26); g.lineTo(54, 84); g.lineTo(46, 84); g.lineTo(44.5, 26);
      g.bezierCurveTo(43, 18, 44, 9, 50, 8); g.closePath(); g.fillStyle = bodyFill; g.fill(); g.stroke();
      g.strokeStyle = '#55626A'; g.lineWidth = 2; g.beginPath(); g.moveTo(42, 88); g.lineTo(58, 88); g.stroke();
      g.fillStyle = color; g.beginPath(); g.arc(50, 16, 2.6, 0, Math.PI * 2); g.fill();
    } else {
      shape([46, 40, 6, 60, 6, 65, 46, 55, 54, 55, 94, 65, 94, 60, 54, 40], wingFill);
      shape([47, 80, 32, 89, 32, 92, 47, 88, 53, 88, 68, 92, 68, 89, 53, 80], wingFill);
      g.fillStyle = '#8D99A0';
      [28, 66].forEach(function (x) { g.beginPath(); g.roundRect ? g.roundRect(x, 46, 6, 12, 3) : g.rect(x, 46, 6, 12); g.fill(); g.stroke(); });
      g.beginPath(); g.moveTo(50, 4); g.bezierCurveTo(55, 6, 56, 14, 56, 20); g.lineTo(56, 78); g.bezierCurveTo(56, 86, 53, 94, 50, 97);
      g.bezierCurveTo(47, 94, 44, 86, 44, 78); g.lineTo(44, 20); g.bezierCurveTo(44, 14, 45, 6, 50, 4); g.closePath();
      g.fillStyle = bodyFill; g.fill(); g.stroke();
      g.fillStyle = '#22313A'; g.beginPath(); g.moveTo(47, 11); g.quadraticCurveTo(50, 8, 53, 11); g.lineTo(52.5, 14); g.quadraticCurveTo(50, 12.5, 47.5, 14); g.closePath(); g.fill();
      g.fillStyle = hexA(color, 0.9); g.fillRect(49.2, 20, 1.6, 56);
    }
    return g.getImageData(0, 0, size, size);
  }
  function hexA(hex, a) {
    var n = parseInt(hex.slice(1), 16);
    return 'rgba(' + (n >> 16 & 255) + ',' + (n >> 8 & 255) + ',' + (n & 255) + ',' + a + ')';
  }
  var ICONS = null;
  function icons() {
    if (!ICONS) ICONS = {
      'ic-0': glyph(KIND_COLORS[0], 'plane'), 'ic-1': glyph(KIND_COLORS[1], 'plane'),
      'ic-2': glyph(KIND_COLORS[2], 'plane'), 'ic-3': glyph(KIND_COLORS[3], 'drone'),
      'ic-sel': glyph('#FFFFFF', 'selected'), 'ic-sel-drone': glyph('#FFFFFF', 'drone'),
    };
    return ICONS;
  }

  // ---------- style ----------
  var TERRARIUM = ['https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png'];
  function decorate(style) {
    style.sources.dem3d = { type: 'raster-dem', encoding: 'terrarium', tileSize: 256, maxzoom: 12, tiles: TERRARIUM };
    style.projection = { type: 'globe' };
    var dark = mode === 'RADAR';
    style.sky = {
      'sky-color': '#071526', 'sky-horizon-blend': 0.5,
      'horizon-color': dark ? '#16384A' : '#6FA6DC', 'horizon-fog-blend': 0.6,
      'fog-color': dark ? '#0B1318' : '#B8D3EE', 'fog-ground-blend': 0.35,
      'atmosphere-blend': ['interpolate', ['linear'], ['zoom'], 0, 1, 5, 1, 8, 0],
    };
    return style;
  }
  function applyTerrain() {
    if (!ready) return;
    try { map.setTerrain(tilted ? { source: 'dem3d', exaggeration: mode === 'RADAR' ? 1.3 : 1.6 } : null); } catch (e) { }
  }

  var map = new maplibregl.Map({
    container: 'map',
    style: { version: 8, sources: {}, layers: [] },
    center: [43.7, 33.25], zoom: 4.6, pitch: 45, maxPitch: 78,
    minZoom: 0.6, maxZoom: 17.5,
    attributionControl: { compact: true },
    fadeDuration: 120,
    maxTileCacheSize: 800,
    renderWorldCopies: true,
    pixelRatio: DPR,
    canvasContextAttributes: { antialias: false, powerPreference: 'high-performance' },
  });
  map.addControl(new maplibregl.NavigationControl({ showZoom: false, visualizePitch: true }), 'top-right');
  map.touchZoomRotate.enableRotation();

  function install() {
    var ic = icons();
    Object.keys(ic).forEach(function (k) { if (!map.hasImage(k)) map.addImage(k, ic[k], { pixelRatio: DPR }); });
    ['trails', 'ahead', 'sel-from', 'sel-track', 'sel-to', 'airports', 'planes'].forEach(function (id) {
      if (!map.getSource(id)) map.addSource(id, { type: 'geojson', data: fc([]), tolerance: 0.2, buffer: 32 });
    });
    function add(l) { if (!map.getLayer(l.id)) map.addLayer(l); }
    add({ id: 'trails', type: 'line', source: 'trails', layout: { 'line-cap': 'round', 'line-join': 'round' },
      paint: { 'line-color': ['get', 'color'], 'line-width': ['interpolate', ['linear'], ['zoom'], 2, 1.2, 8, 2, 12, 3], 'line-opacity': 0.7 } });
    add({ id: 'ahead', type: 'line', source: 'ahead', minzoom: 4,
      paint: { 'line-color': ['get', 'color'], 'line-width': 1.8, 'line-opacity': 0.8, 'line-dasharray': [2, 2] } });
    add({ id: 'sel-from-casing', type: 'line', source: 'sel-from',
      paint: { 'line-color': '#000000', 'line-width': 4, 'line-opacity': 0.4 } });
    add({ id: 'sel-from', type: 'line', source: 'sel-from',
      paint: { 'line-color': '#FFFFFF', 'line-width': 1.6, 'line-opacity': 0.6, 'line-dasharray': [1.5, 2] } });
    add({ id: 'sel-track-glow', type: 'line', source: 'sel-track', layout: { 'line-cap': 'round', 'line-join': 'round' },
      paint: { 'line-color': '#7FD8FF', 'line-width': 8, 'line-opacity': 0.25, 'line-blur': 3 } });
    add({ id: 'sel-track', type: 'line', source: 'sel-track', layout: { 'line-cap': 'round', 'line-join': 'round' },
      paint: { 'line-color': '#FFFFFF', 'line-width': 3.2, 'line-opacity': 0.95 } });
    add({ id: 'sel-to-casing', type: 'line', source: 'sel-to', layout: { 'line-cap': 'round' },
      paint: { 'line-color': '#000000', 'line-width': 5.5, 'line-opacity': 0.55 } });
    add({ id: 'sel-to', type: 'line', source: 'sel-to', layout: { 'line-cap': 'round' },
      paint: { 'line-color': '#FFD54F', 'line-width': 3, 'line-opacity': 0.95, 'line-dasharray': [2, 1.6] } });
    add({ id: 'airports-dot', type: 'circle', source: 'airports',
      paint: { 'circle-radius': 6, 'circle-color': ['get', 'color'], 'circle-stroke-color': '#0B1318', 'circle-stroke-width': 2 } });
    add({ id: 'airports-label', type: 'symbol', source: 'airports',
      layout: { 'text-field': ['get', 'label'], 'text-font': ['Noto Sans Bold'], 'text-size': 13, 'text-offset': [0, 1.1], 'text-anchor': 'top',
        'text-allow-overlap': true, 'text-max-width': 14 },
      paint: { 'text-color': ['get', 'color'], 'text-halo-color': '#000000', 'text-halo-width': 1.8 } });
    add({ id: 'planes', type: 'symbol', source: 'planes',
      layout: { 'icon-image': ['get', 'icon'], 'icon-rotate': ['get', 'trk'], 'icon-rotation-alignment': 'map', 'icon-pitch-alignment': 'map',
        'icon-allow-overlap': true, 'icon-ignore-placement': true, 'symbol-sort-key': ['get', 'z'],
        'icon-size': ['interpolate', ['linear'], ['zoom'], 1, 0.36, 4, 0.5, 7, 0.68, 10, 0.9, 14, 1.15] } });
    add({ id: 'plane-labels', type: 'symbol', source: 'planes', minzoom: 6.5,
      layout: { 'text-field': ['get', 'label'], 'text-font': ['Noto Sans Bold'], 'text-size': 11, 'text-offset': [0, 1.9], 'text-anchor': 'top', 'text-optional': true },
      paint: { 'text-color': '#E6F3EE', 'text-halo-color': '#0B1318', 'text-halo-width': 1.4 } });
    ready = true;
    applyTerrain();
    renderTrails(Date.now());
    renderAirports();
    tick(true);
  }
  map.on('style.load', install);

  // ---------- rendering ----------
  function src(id) { return ready ? map.getSource(id) : null; }

  function renderPlanes(now) {
    var s = src('planes'); if (!s) return;
    var feats = [], ahead = [];
    var showAhead = map.getZoom() >= 4;
    for (var i = 0; i < planes.length; i++) {
      var p = planes[i], pos = live(p, now), isSel = p[0] === selected;
      feats.push(point(ll(pos), {
        hex: p[0], trk: p[3] || 0, label: p[8],
        icon: isSel ? (p[7] === 3 ? 'ic-sel-drone' : 'ic-sel') : 'ic-' + p[7],
        z: isSel ? 3 : (p[7] === 3 ? 2 : 0),
      }));
      // Short dashed line showing where every moving aircraft is heading (next ~8 minutes).
      if (showAhead && !isSel && p[3] != null && p[4] != null && p[4] >= 30 && !p[6]) {
        var km = Math.min(p[4] * 1.852 * (8 / 60), 150);
        ahead.push(line([ll(pos), ll(project(pos[0], pos[1], p[3], km))], { color: KIND_COLORS[p[7]] }));
      }
    }
    s.setData(fc(feats));
    var a = src('ahead'); if (a) a.setData(fc(ahead));
    renderSelectedAhead(now);
  }

  function selectedPlane() {
    if (!selected) return null;
    for (var i = 0; i < planes.length; i++) if (planes[i][0] === selected) return planes[i];
    return null;
  }

  /** From the moving aircraft to its destination airport (or 20 minutes along its heading). */
  function renderSelectedAhead(now) {
    var s = src('sel-to'); if (!s) return;
    var p = selectedPlane();
    if (!p) { s.setData(fc([])); return; }
    var pos = live(p, now);
    if (route && route.d) {
      var n = Math.max(8, Math.min(160, Math.round(distKm(pos, [route.d.lat, route.d.lon]) / 40)));
      s.setData(fc([line(greatCircle(pos, [route.d.lat, route.d.lon], n))]));
    } else if (p[3] != null && p[4] != null && p[4] >= 30 && !p[6]) {
      var km = Math.min(p[4] * 1.852 * (20 / 60), 400);
      s.setData(fc([line(greatCircle(pos, project(pos[0], pos[1], p[3], km), 16))]));
    } else s.setData(fc([]));
  }

  /** Lines behind each aircraft end exactly at its moving position, so they never jump while zooming. */
  function renderTrails(now) {
    var t = src('trails'); if (!t) return;
    var byHex = {};
    planes.forEach(function (p) { byHex[p[0]] = p; });
    var feats = [];
    Object.keys(trails).forEach(function (h) {
      var p = byHex[h]; if (!p || h === selected) return;
      var pts = trails[h].slice(-40).map(ll); pts.push(ll(live(p, now)));
      if (pts.length >= 2) feats.push(line(pts, { color: KIND_COLORS[p[7]] }));
    });
    t.setData(fc(feats));

    var sp = selectedPlane(), st = src('sel-track'), sf = src('sel-from');
    if (!st || !sf) return;
    if (!sp) { st.setData(fc([])); sf.setData(fc([])); return; }
    var path = (track && track.length >= 2 ? track : (trails[sp[0]] || [])).map(ll);
    path.push(ll(live(sp, now)));
    st.setData(fc(path.length >= 2 ? [line(path)] : []));
    // Where it came from: origin airport → first known point of the path.
    if (route && route.o) {
      var first = path.length ? [path[0][1], path[0][0]] : live(sp, now);
      var n = Math.max(8, Math.min(160, Math.round(distKm([route.o.lat, route.o.lon], first) / 40)));
      sf.setData(fc([line(greatCircle([route.o.lat, route.o.lon], first, n))]));
    } else sf.setData(fc([]));
  }

  function renderAirports() {
    var s = src('airports'); if (!s) return;
    var f = [];
    if (route && selected) {
      if (route.o) f.push(point([route.o.lon, route.o.lat], { label: 'من: ' + route.o.label, color: '#FFFFFF' }));
      if (route.d) f.push(point([route.d.lon, route.d.lat], { label: 'إلى: ' + route.d.label, color: '#FFD27A' }));
    }
    s.setData(fc(f));
  }

  var lastFrame = 0, lastTrails = 0;
  function tick(force) {
    var now = Date.now();
    if (force === true || now - lastFrame >= 100) { lastFrame = now; renderPlanes(now); }
    if (force === true || now - lastTrails >= 1000) { lastTrails = now; renderTrails(now); }
  }
  (function loop() {
    if (!document.hidden && ready) tick(false);
    requestAnimationFrame(loop);
  })();

  // ---------- interaction ----------
  map.on('click', function (e) {
    var r = 26, f = ready ? map.queryRenderedFeatures([[e.point.x - r, e.point.y - r], [e.point.x + r, e.point.y + r]], { layers: ['planes'] }) : [];
    bridge.onSelect(f.length ? String(f[0].properties.hex) : '');
  });
  function clamp(v, a, b) { return Math.max(a, Math.min(b, v)); }
  map.on('moveend', function () {
    var b = map.getBounds(), c = map.getCenter();
    var w = b.getWest(), e = b.getEast();
    if (e - w >= 360) { w = -180; e = 180; }
    bridge.onViewport(c.lat, ((c.lng + 540) % 360) - 180, clamp(b.getNorth(), -85, 85), clamp(b.getSouth(), -85, 85),
      ((e + 540) % 360) - 180, ((w + 540) % 360) - 180, map.getZoom());
  });

  // ---------- API for Kotlin ----------
  window.sky = {
    setStyle: function (styleJson, newMode) {
      mode = newMode || 'SATELLITE';
      ready = false;
      map.once('idle', collapseAttribution);
      map.setStyle(decorate(typeof styleJson === 'string' ? JSON.parse(styleJson) : styleJson), { diff: false });
    },
    setPlanes: function (list) { planes = list || []; tick(true); },
    setTrails: function (t) { trails = t || {}; renderTrails(Date.now()); },
    setSelection: function (hex, path, r) {
      selected = hex || null; track = path || null; route = r || null;
      renderAirports(); tick(true);
    },
    camera: function (lat, lon, zoom, fitIraq) {
      var pitch = tilted ? 45 : 0;
      if (fitIraq) {
        map.fitBounds([[38.8, 29.1], [48.7, 37.3]], { padding: { top: 190, bottom: 110, left: 24, right: 24 }, pitch: tilted ? 30 : 0, bearing: 0, duration: 1400 });
      } else map.flyTo({ center: [lon, lat], zoom: zoom, pitch: zoom < 3 ? 0 : pitch, duration: 1600, essential: true });
    },
    setTilt: function (on) {
      tilted = !!on; applyTerrain();
      map.easeTo({ pitch: tilted ? 55 : 0, duration: 700 });
    },
    showRoute: function () {
      if (!route || !route.o || !route.d) return;
      var b = new maplibregl.LngLatBounds([route.o.lon, route.o.lat], [route.o.lon, route.o.lat]).extend([route.d.lon, route.d.lat]);
      var p = selectedPlane(); if (p) b.extend(ll(live(p, Date.now())));
      map.fitBounds(b, { padding: { top: 220, bottom: 300, left: 40, right: 40 }, pitch: 0, duration: 1600, maxZoom: 9 });
    },
  };
  function collapseAttribution() { var a = document.querySelector('.maplibregl-ctrl-attrib'); if (a) a.classList.remove('maplibregl-compact-show'); }
  bridge.onReady();
})();
