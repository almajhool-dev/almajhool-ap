package com.skymonitor.iraq.ui

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.DashPathEffect
import android.graphics.Paint
import android.graphics.Path
import android.graphics.drawable.BitmapDrawable
import android.view.MotionEvent
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.viewinterop.AndroidView
import com.skymonitor.iraq.CameraMove
import com.skymonitor.iraq.Viewport
import com.skymonitor.iraq.data.Aircraft
import com.skymonitor.iraq.data.Category
import com.skymonitor.iraq.data.Regions
import org.osmdroid.events.MapListener
import org.osmdroid.events.ScrollEvent
import org.osmdroid.events.ZoomEvent
import org.osmdroid.tileprovider.tilesource.XYTileSource
import org.osmdroid.util.GeoPoint
import org.osmdroid.views.CustomZoomButtonsController
import org.osmdroid.views.MapView
import org.osmdroid.views.Projection
import org.osmdroid.views.overlay.CopyrightOverlay
import org.osmdroid.views.overlay.FolderOverlay
import org.osmdroid.views.overlay.Marker
import org.osmdroid.views.overlay.Overlay
import kotlin.math.roundToInt

/** CARTO "Dark Matter" basemap (OpenStreetMap data), free with attribution. */
private val DarkTiles = XYTileSource(
    "CartoDarkMatter", 1, 18, 256, ".png",
    arrayOf(
        "https://a.basemaps.cartocdn.com/dark_all/",
        "https://b.basemaps.cartocdn.com/dark_all/",
        "https://c.basemaps.cartocdn.com/dark_all/",
    ),
    "© OpenStreetMap contributors © CARTO",
)

private const val COLOR_CIVIL = 0xFF35F0A2.toInt()
private const val COLOR_OTHER = 0xFFFFB547.toInt()
private const val COLOR_UNCLASSIFIED = 0xFF7FB8D6.toInt()
private const val COLOR_WATCHED = 0xFFFF4D5E.toInt()

fun colorFor(a: Aircraft): Int = when {
    a.watched != null -> COLOR_WATCHED
    a.category == Category.OTHER -> COLOR_OTHER
    a.category == Category.UNCLASSIFIED -> COLOR_UNCLASSIFIED
    else -> COLOR_CIVIL
}

/** Plane glyphs, pre-rendered per colour and 10° heading bucket. */
private class IconCache(private val context: Context) {
    private val cache = HashMap<Long, BitmapDrawable>()
    private val density = context.resources.displayMetrics.density

    fun get(color: Int, trackDeg: Double?, big: Boolean): BitmapDrawable {
        val bucket = ((trackDeg ?: 0.0) / 10.0).roundToInt().mod(36)
        val key = (color.toLong() shl 8) or (bucket.toLong() shl 1) or (if (big) 1L else 0L)
        return cache.getOrPut(key) { render(color, bucket * 10f, big) }
    }

    private fun render(color: Int, rotation: Float, big: Boolean): BitmapDrawable {
        val size = ((if (big) 34 else 24) * density).roundToInt()
        val bmp = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val c = Canvas(bmp)
        val s = size / 24f
        c.rotate(rotation, size / 2f, size / 2f)
        c.scale(s, s)
        val path = Path().apply {
            // Simple top-view aircraft pointing north on a 24×24 grid.
            moveTo(12f, 2f); lineTo(13.4f, 9f); lineTo(21.5f, 13.6f); lineTo(21.5f, 15.4f)
            lineTo(13.4f, 13f); lineTo(13f, 18.6f); lineTo(15.8f, 20.6f); lineTo(15.8f, 22f)
            lineTo(12f, 21f); lineTo(8.2f, 22f); lineTo(8.2f, 20.6f); lineTo(11f, 18.6f)
            lineTo(10.6f, 13f); lineTo(2.5f, 15.4f); lineTo(2.5f, 13.6f); lineTo(10.6f, 9f); close()
        }
        val glow = Paint(Paint.ANTI_ALIAS_FLAG).apply { this.color = color; alpha = 70; style = Paint.Style.STROKE; strokeWidth = 2.6f }
        val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply { this.color = color; style = Paint.Style.FILL }
        val edge = Paint(Paint.ANTI_ALIAS_FLAG).apply { this.color = Color.argb(200, 0, 0, 0); style = Paint.Style.STROKE; strokeWidth = 0.8f }
        c.drawPath(path, glow); c.drawPath(path, fill); c.drawPath(path, edge)
        return BitmapDrawable(context.resources, bmp)
    }
}

/** Faint range rings around central Iraq for the radar look (decorative, no data meaning). */
private class RadarRingsOverlay : Overlay() {
    private val ring = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.argb(70, 53, 240, 162); style = Paint.Style.STROKE; strokeWidth = 2f
        pathEffect = DashPathEffect(floatArrayOf(10f, 10f), 0f)
    }
    private val cross = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.argb(45, 53, 240, 162); strokeWidth = 1.5f }

    override fun draw(c: Canvas, pj: Projection) {
        val center = pj.toPixels(GeoPoint(Regions.IRAQ_CENTER_LAT, Regions.IRAQ_CENTER_LON), null)
        val edge = pj.toPixels(GeoPoint(Regions.IRAQ_CENTER_LAT, Regions.IRAQ_CENTER_LON + 1.5), null)
        val step = (edge.x - center.x).toFloat()
        if (step < 6f) return
        for (i in 1..4) c.drawCircle(center.x.toFloat(), center.y.toFloat(), step * i, ring)
        val r = step * 4
        c.drawLine(center.x - r, center.y.toFloat(), center.x + r, center.y.toFloat(), cross)
        c.drawLine(center.x.toFloat(), center.y - r, center.x.toFloat(), center.y + r, cross)
    }
}

@Composable
fun RadarMap(
    aircraft: List<Aircraft>,
    selectedHex: String?,
    camera: CameraMove?,
    onSelect: (Aircraft?) -> Unit,
    onViewport: (Viewport) -> Unit,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val icons = remember { IconCache(context) }
    val planes = remember { FolderOverlay() }
    val map = remember {
        MapView(context).apply {
            setTileSource(DarkTiles)
            setMultiTouchControls(true)
            zoomController.setVisibility(CustomZoomButtonsController.Visibility.NEVER)
            minZoomLevel = 2.0
            maxZoomLevel = 16.0
            isTilesScaledToDpi = true
            isHorizontalMapRepetitionEnabled = true
            isVerticalMapRepetitionEnabled = false
            setScrollableAreaLimitLatitude(MapView.getTileSystem().maxLatitude, MapView.getTileSystem().minLatitude, 0)
            setBackgroundColor(Color.rgb(7, 13, 18))
            overlays.add(RadarRingsOverlay())
            overlays.add(planes)
            overlays.add(CopyrightOverlay(context).apply { setTextColor(Color.argb(160, 200, 220, 220)) })
            // Tap on empty map clears the selection.
            overlays.add(object : Overlay() {
                override fun onSingleTapConfirmed(e: MotionEvent?, mapView: MapView?): Boolean { onSelect(null); return false }
            })
            controller.setZoom(6.2)
            controller.setCenter(GeoPoint(Regions.IRAQ_CENTER_LAT, Regions.IRAQ_CENTER_LON))
        }
    }

    DisposableEffect(map) {
        val listener = object : MapListener {
            override fun onScroll(event: ScrollEvent?): Boolean { report(map, onViewport); return false }
            override fun onZoom(event: ZoomEvent?): Boolean { report(map, onViewport); return false }
        }
        map.addMapListener(listener)
        map.onResume()
        onDispose { map.removeMapListener(listener); map.onPause(); map.onDetach() }
    }

    LaunchedEffect(camera?.id) {
        camera ?: return@LaunchedEffect
        map.controller.animateTo(GeoPoint(camera.lat, camera.lon), camera.zoom, 900L)
    }

    AndroidView(factory = { map }, modifier = modifier, update = { mv ->
        planes.items.clear()
        // Draw the selected aircraft last so it sits on top.
        val ordered = aircraft.sortedBy { (if (it.hex == selectedHex) 2 else 0) + (if (it.watched != null) 1 else 0) }
        for (a in ordered) {
            val m = Marker(mv)
            m.position = GeoPoint(a.lat, a.lon)
            m.setAnchor(Marker.ANCHOR_CENTER, Marker.ANCHOR_CENTER)
            m.icon = icons.get(colorFor(a), a.trackDeg, big = a.hex == selectedHex || a.watched != null)
            m.setInfoWindow(null)
            m.title = a.displayName
            m.setOnMarkerClickListener { _, _ -> onSelect(a); true }
            planes.add(m)
        }
        mv.invalidate()
    })
}

private fun report(map: MapView, onViewport: (Viewport) -> Unit) {
    val bb = map.boundingBox
    val c = map.mapCenter
    onViewport(Viewport(c.latitude, c.longitude, bb.latNorth, bb.latSouth, bb.lonEast, bb.lonWest, map.zoomLevelDouble))
}
