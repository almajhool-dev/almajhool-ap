package com.skymonitor.iraq.ui

import android.graphics.RectF
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.skymonitor.iraq.CameraMove
import com.skymonitor.iraq.Viewport
import com.skymonitor.iraq.data.Aircraft
import com.skymonitor.iraq.data.Category
import com.skymonitor.iraq.data.Regions
import kotlinx.coroutines.delay
import org.maplibre.android.camera.CameraPosition
import org.maplibre.android.camera.CameraUpdateFactory
import org.maplibre.android.geometry.LatLng
import org.maplibre.android.geometry.LatLngBounds
import org.maplibre.android.maps.MapLibreMap
import org.maplibre.android.maps.MapView
import org.maplibre.android.maps.Style
import org.maplibre.android.style.expressions.Expression
import org.maplibre.android.style.layers.LineLayer
import org.maplibre.android.style.layers.Property
import org.maplibre.android.style.layers.PropertyFactory
import org.maplibre.android.style.layers.SymbolLayer
import org.maplibre.android.style.sources.GeoJsonSource
import org.maplibre.geojson.Feature
import org.maplibre.geojson.FeatureCollection
import org.maplibre.geojson.LineString
import org.maplibre.geojson.Point
import kotlin.math.asin
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.sin

private const val SRC_PLANES = "planes"
private const val SRC_TRAILS = "trails"
private const val SRC_SEL_TRACK = "sel-track"
private const val SRC_SEL_AHEAD = "sel-ahead"

fun iconFor(a: Aircraft): String = when {
    a.watched != null -> PlaneIcons.WATCHED
    a.category == Category.OTHER -> PlaneIcons.OTHER
    a.category == Category.UNCLASSIFIED -> PlaneIcons.UNCLASSIFIED
    else -> PlaneIcons.CIVIL
}

fun colorFor(a: Aircraft): Int = when {
    a.watched != null -> PlaneIcons.COLOR_WATCHED
    a.category == Category.OTHER -> PlaneIcons.COLOR_OTHER
    a.category == Category.UNCLASSIFIED -> PlaneIcons.COLOR_UNCLASSIFIED
    else -> PlaneIcons.COLOR_CIVIL
}

private fun hex(color: Int) = String.format("#%06X", color and 0xFFFFFF)

/** Point reached after travelling [km] from (lat, lon) on bearing [deg] (great circle). */
private fun project(lat: Double, lon: Double, deg: Double, km: Double): DoubleArray {
    val r = 6371.0
    val d = km / r
    val b = Math.toRadians(deg)
    val p1 = Math.toRadians(lat)
    val l1 = Math.toRadians(lon)
    val p2 = asin(sin(p1) * cos(d) + cos(p1) * sin(d) * cos(b))
    val l2 = l1 + atan2(sin(b) * sin(d) * cos(p1), cos(d) - sin(p1) * sin(p2))
    return doubleArrayOf(Math.toDegrees(p2), ((Math.toDegrees(l2) + 540) % 360) - 180)
}

/** Where the aircraft is now, estimated from its last public report, speed and heading (max 2 min ahead). */
fun livePosition(a: Aircraft, now: Long = System.currentTimeMillis()): DoubleArray {
    val kt = a.speedKt ?: return doubleArrayOf(a.lat, a.lon)
    val trk = a.trackDeg ?: return doubleArrayOf(a.lat, a.lon)
    if (a.onGround || kt < 30) return doubleArrayOf(a.lat, a.lon)
    val hours = ((now - a.positionTimeMs).coerceIn(0, 120_000)) / 3_600_000.0
    return project(a.lat, a.lon, trk, kt * 1.852 * hours)
}

private fun Style.setLine(id: String, coords: List<DoubleArray>?) {
    val src = getSourceAs<GeoJsonSource>(id) ?: return
    if (coords == null || coords.size < 2) { src.setGeoJson(FeatureCollection.fromFeatures(emptyArray())); return }
    src.setGeoJson(Feature.fromGeometry(LineString.fromLngLats(coords.map { Point.fromLngLat(it[1], it[0]) })))
}

/** Session trails for every aircraft and the full path for the selected one, each ending at the live position. */
private fun updateTrails(st: Style, aircraft: List<Aircraft>, trails: Map<String, List<DoubleArray>>, selected: Aircraft?, track: List<DoubleArray>?, now: Long) {
    val byHex = aircraft.associateBy { it.hex }
    val lines = trails.mapNotNull { (h, pts) ->
        val a = byHex[h] ?: return@mapNotNull null
        if (h == selected?.hex) return@mapNotNull null
        val coords = (pts.takeLast(40) + listOf(livePosition(a, now))).map { Point.fromLngLat(it[1], it[0]) }
        Feature.fromGeometry(LineString.fromLngLats(coords)).apply { addStringProperty("color", hex(colorFor(a))) }
    }
    st.getSourceAs<GeoJsonSource>(SRC_TRAILS)?.setGeoJson(FeatureCollection.fromFeatures(lines))
    val sel = selected?.let { byHex[it.hex] ?: it }
    val path = when {
        sel == null -> null
        track != null -> track + listOf(livePosition(sel, now))
        else -> trails[sel.hex]?.plus(listOf(livePosition(sel, now)))
    }
    st.setLine(SRC_SEL_TRACK, path)
}

private fun installOverlays(st: Style, density: Float) {
    PlaneIcons.all(density).forEach { (name, bmp) -> st.addImage(name, bmp) }
    st.addSource(GeoJsonSource(SRC_TRAILS))
    st.addSource(GeoJsonSource(SRC_SEL_TRACK))
    st.addSource(GeoJsonSource(SRC_SEL_AHEAD))
    st.addSource(GeoJsonSource(SRC_PLANES))
    st.addLayer(LineLayer("trails", SRC_TRAILS).withProperties(
        PropertyFactory.lineColor(Expression.toColor(Expression.get("color"))),
        PropertyFactory.lineWidth(1.6f), PropertyFactory.lineOpacity(0.55f),
        PropertyFactory.lineCap(Property.LINE_CAP_ROUND), PropertyFactory.lineJoin(Property.LINE_JOIN_ROUND),
    ))
    st.addLayer(LineLayer("sel-track", SRC_SEL_TRACK).withProperties(
        PropertyFactory.lineColor("#FFFFFF"), PropertyFactory.lineWidth(3.2f), PropertyFactory.lineOpacity(0.9f),
        PropertyFactory.lineCap(Property.LINE_CAP_ROUND), PropertyFactory.lineJoin(Property.LINE_JOIN_ROUND),
    ))
    st.addLayer(LineLayer("sel-ahead", SRC_SEL_AHEAD).withProperties(
        PropertyFactory.lineColor("#FFD27A"), PropertyFactory.lineWidth(2.4f),
        PropertyFactory.lineDasharray(arrayOf(2f, 2f)), PropertyFactory.lineOpacity(0.9f),
    ))
    st.addLayer(SymbolLayer("planes", SRC_PLANES).withProperties(
        PropertyFactory.iconImage(Expression.get("icon")),
        PropertyFactory.iconRotate(Expression.get("track")),
        PropertyFactory.iconRotationAlignment(Property.ICON_ROTATION_ALIGNMENT_MAP),
        PropertyFactory.iconPitchAlignment(Property.ICON_PITCH_ALIGNMENT_MAP),
        PropertyFactory.iconAllowOverlap(true), PropertyFactory.iconIgnorePlacement(true),
        PropertyFactory.iconSize(Expression.interpolate(Expression.linear(), Expression.zoom(),
            Expression.stop(2, 0.42f), Expression.stop(6, 0.62f), Expression.stop(10, 0.85f), Expression.stop(14, 1.1f))),
        PropertyFactory.symbolSortKey(Expression.get("z")),
    ))
    st.addLayer(SymbolLayer("plane-labels", SRC_PLANES).withProperties(
        PropertyFactory.textField(Expression.get("label")),
        PropertyFactory.textFont(arrayOf("Noto Sans Bold")),
        PropertyFactory.textSize(11f), PropertyFactory.textOffset(arrayOf(0f, 1.9f)),
        PropertyFactory.textAnchor(Property.TEXT_ANCHOR_TOP), PropertyFactory.textOptional(true),
        PropertyFactory.textColor("#E6F3EE"), PropertyFactory.textHaloColor("#0B1318"), PropertyFactory.textHaloWidth(1.4f),
    ).apply { minZoom = 6.5f })

}

@Composable
fun RadarMap(
    aircraft: List<Aircraft>,
    trails: Map<String, List<DoubleArray>>,
    selected: Aircraft?,
    selectedTrack: List<DoubleArray>?,
    camera: CameraMove?,
    tilted: Boolean,
    mode: MapMode,
    onSelect: (Aircraft?) -> Unit,
    onViewport: (Viewport) -> Unit,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val density = LocalDensity.current.density
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    val mapView = remember { MapView(context).apply { onCreate(null) } }
    var map by remember { mutableStateOf<MapLibreMap?>(null) }
    var style by remember { mutableStateOf<Style?>(null) }

    val latestAircraft by rememberUpdatedState(aircraft)
    val latestSelect by rememberUpdatedState(onSelect)
    val latestViewport by rememberUpdatedState(onViewport)
    val latestSelected by rememberUpdatedState(selected)
    val latestTrails by rememberUpdatedState(trails)
    val latestTrack by rememberUpdatedState(selectedTrack)

    DisposableEffect(lifecycle) {
        val observer = LifecycleEventObserver { _, e ->
            when (e) {
                Lifecycle.Event.ON_START -> mapView.onStart()
                Lifecycle.Event.ON_RESUME -> mapView.onResume()
                Lifecycle.Event.ON_PAUSE -> mapView.onPause()
                Lifecycle.Event.ON_STOP -> mapView.onStop()
                else -> Unit
            }
        }
        lifecycle.addObserver(observer)
        onDispose { lifecycle.removeObserver(observer) }
    }
    DisposableEffect(Unit) { onDispose { mapView.onDestroy() } }

    LaunchedEffect(Unit) {
        mapView.getMapAsync { m ->
            m.uiSettings.apply {
                isLogoEnabled = false
                isAttributionEnabled = true
                isCompassEnabled = true
                setCompassMargins(0, (230 * density).toInt(), (14 * density).toInt(), 0)
                isRotateGesturesEnabled = true
                isTiltGesturesEnabled = true
            }
            m.setMinZoomPreference(1.0)
            m.setMaxZoomPreference(16.5)
            m.cameraPosition = CameraPosition.Builder().target(LatLng(Regions.IRAQ_CENTER_LAT, Regions.IRAQ_CENTER_LON)).zoom(5.2).tilt(45.0).build()
            m.setPrefetchZoomDelta(3)
            m.addOnMapClickListener { latLng ->
                val p = m.projection.toScreenLocation(latLng)
                val r = 26 * density
                val hit = m.queryRenderedFeatures(RectF(p.x - r, p.y - r, p.x + r, p.y + r), "planes").firstOrNull()
                val hexId = hit?.getStringProperty("hex")
                latestSelect(hexId?.let { h -> latestAircraft.firstOrNull { it.hex == h } })
                true
            }
            m.addOnCameraIdleListener {
                val b = m.projection.visibleRegion.latLngBounds
                val c = m.cameraPosition.target ?: return@addOnCameraIdleListener
                latestViewport(Viewport(c.latitude, c.longitude, b.latitudeNorth, b.latitudeSouth, b.longitudeEast, b.longitudeWest, m.cameraPosition.zoom))
            }
            map = m
        }
    }

    LaunchedEffect(map, mode) {
        val m = map ?: return@LaunchedEffect
        style = null
        m.setStyle(Style.Builder().fromJson(MapStyle.forMode(mode))) { st ->
            installOverlays(st, density)
            style = st
        }
    }

    // Planes move smoothly between public reports (dead reckoning, refreshed every second).
    LaunchedEffect(style) {
        val st = style ?: return@LaunchedEffect
        var tick = 0
        while (true) {
            tick++
            val src = st.getSourceAs<GeoJsonSource>(SRC_PLANES)
            val sel = latestSelected?.hex
            val now = System.currentTimeMillis()
            val features = latestAircraft.map { a ->
                val pos = livePosition(a, now)
                Feature.fromGeometry(Point.fromLngLat(pos[1], pos[0])).apply {
                    addStringProperty("hex", a.hex)
                    addStringProperty("icon", if (a.hex == sel) PlaneIcons.SELECTED else iconFor(a))
                    addNumberProperty("track", a.trackDeg ?: 0.0)
                    addStringProperty("label", a.displayName)
                    addNumberProperty("z", if (a.hex == sel) 2 else if (a.watched != null) 1 else 0)
                }
            }
            src?.setGeoJson(FeatureCollection.fromFeatures(features))
            // Keep the "heading ahead" line attached to the moving selected aircraft.
            val s = latestSelected
            if (s != null && s.trackDeg != null && (s.speedKt ?: 0.0) > 30 && !s.onGround) {
                val now2 = livePosition(s, now)
                val ahead = project(now2[0], now2[1], s.trackDeg, (s.speedKt!! * 1.852 * (20.0 / 60.0)).coerceAtMost(400.0))
                st.setLine(SRC_SEL_AHEAD, listOf(now2, ahead))
            } else st.setLine(SRC_SEL_AHEAD, null)
            // Path lines end exactly at the moving aircraft, so they never jump when zooming.
            if (tick % 6 == 1) updateTrails(st, latestAircraft, latestTrails, latestSelected, latestTrack, now)
            delay(160)
        }
    }

    LaunchedEffect(style, trails, selected?.hex, selectedTrack) {
        val st = style ?: return@LaunchedEffect
        updateTrails(st, aircraft, trails, selected, selectedTrack, System.currentTimeMillis())
    }

    LaunchedEffect(map, camera?.id) {
        val m = map ?: return@LaunchedEffect
        val cam = camera ?: return@LaunchedEffect
        val target = if (cam.fitIraq) {
            val bounds = LatLngBounds.Builder()
                .include(LatLng(Regions.IRAQ_MAX_LAT - 0.1, Regions.IRAQ_MIN_LON + 0.1))
                .include(LatLng(Regions.IRAQ_MIN_LAT + 0.1, Regions.IRAQ_MAX_LON - 0.1)).build()
            val pad = (24 * density).toInt()
            val fit = m.getCameraForLatLngBounds(bounds, intArrayOf(pad, (190 * density).toInt(), pad, (110 * density).toInt()))
            CameraPosition.Builder().target(fit?.target ?: LatLng(cam.lat, cam.lon)).zoom(fit?.zoom ?: cam.zoom)
                .tilt(if (tilted) 45.0 else 0.0).bearing(0.0).build()
        } else {
            CameraPosition.Builder().target(LatLng(cam.lat, cam.lon)).zoom(cam.zoom).tilt(if (tilted) 45.0 else 0.0).build()
        }
        m.animateCamera(CameraUpdateFactory.newCameraPosition(target), 1400)
    }

    LaunchedEffect(map, tilted) {
        val m = map ?: return@LaunchedEffect
        m.animateCamera(CameraUpdateFactory.tiltTo(if (tilted) 55.0 else 0.0), 700)
    }

    AndroidView(factory = { mapView }, modifier = modifier)
}
