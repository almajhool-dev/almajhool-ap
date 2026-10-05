package com.skymonitor.iraq.ui

import android.annotation.SuppressLint
import android.graphics.Color
import android.os.Handler
import android.os.Looper
import android.webkit.JavascriptInterface
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
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
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.skymonitor.iraq.CameraMove
import com.skymonitor.iraq.Viewport
import com.skymonitor.iraq.data.Aircraft
import com.skymonitor.iraq.data.Category
import com.skymonitor.iraq.data.FlightRoute
import com.skymonitor.iraq.map.TileCache
import org.json.JSONArray
import org.json.JSONObject
import java.util.Locale

private const val ASSET_HOST = "appassets.androidplatform.net"

/** 0 civil · 1 publicly flagged military/government · 2 unclassified · 3 watched drone type. */
fun kindOf(a: Aircraft): Int = when {
    a.watched != null -> 3
    a.category == Category.OTHER -> 1
    a.category == Category.UNCLASSIFIED -> 2
    else -> 0
}

internal fun planesJson(list: List<Aircraft>): String {
    val arr = JSONArray()
    for (a in list) arr.put(JSONArray().apply {
        put(a.hex); put(a.lat); put(a.lon)
        put(a.trackDeg ?: JSONObject.NULL); put(a.speedKt ?: JSONObject.NULL)
        put(a.positionTimeMs); put(if (a.onGround) 1 else 0); put(kindOf(a)); put(a.displayName)
    })
    return arr.toString()
}

internal fun trailsJson(trails: Map<String, List<DoubleArray>>): String {
    val o = JSONObject()
    trails.forEach { (h, pts) -> o.put(h, JSONArray().apply { pts.takeLast(40).forEach { put(JSONArray().put(it[0]).put(it[1])) } }) }
    return o.toString()
}

private fun pathJson(path: List<DoubleArray>?): String =
    if (path == null || path.size < 2) "null" else JSONArray().apply { path.forEach { put(JSONArray().put(it[0]).put(it[1])) } }.toString()

/** Airport label as two short lines (country in Arabic, then city + code) so mixed scripts read cleanly. */
private fun airportJson(ap: com.skymonitor.iraq.data.Airport): JSONObject {
    val country = ap.countryIso?.let { Locale("", it).getDisplayCountry(Locale("ar")) }?.takeIf { it.isNotBlank() } ?: ""
    val code = ap.iata ?: ap.icao ?: ""
    return JSONObject().put("lat", ap.lat).put("lon", ap.lon)
        .put("label", (if (country.isNotEmpty()) "$country\n" else "") + listOf(ap.city ?: ap.name, code).filter { it.isNotBlank() }.joinToString(" · "))
}

private fun routeJson(r: FlightRoute?): String =
    if (r == null) "null" else JSONObject().put("o", airportJson(r.origin)).put("d", airportJson(r.destination)).toString()

@SuppressLint("SetJavaScriptEnabled", "JavascriptInterface")
@Composable
fun SkyMap(
    aircraft: List<Aircraft>,
    trails: Map<String, List<DoubleArray>>,
    selected: Aircraft?,
    selectedTrack: List<DoubleArray>?,
    selectedRoute: FlightRoute?,
    camera: CameraMove?,
    tilted: Boolean,
    mode: MapMode,
    showRouteRequest: Long,
    onSelect: (Aircraft?) -> Unit,
    onViewport: (Viewport) -> Unit,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    var ready by remember { mutableStateOf(false) }
    val latestAircraft by rememberUpdatedState(aircraft)
    val latestSelect by rememberUpdatedState(onSelect)
    val latestViewport by rememberUpdatedState(onViewport)
    val main = remember { Handler(Looper.getMainLooper()) }
    val cache = remember { TileCache.get(context) }

    val web = remember {
        WebView(context).apply {
            setBackgroundColor(Color.rgb(2, 6, 11))
            settings.javaScriptEnabled = true
            settings.domStorageEnabled = true
            settings.cacheMode = WebSettings.LOAD_DEFAULT
            settings.mediaPlaybackRequiresUserGesture = true
            settings.allowFileAccess = false
            settings.setSupportZoom(false)
            isVerticalScrollBarEnabled = false
            isHorizontalScrollBarEnabled = false
            overScrollMode = WebView.OVER_SCROLL_NEVER
            addJavascriptInterface(object {
                @JavascriptInterface fun onReady() = main.post { ready = true }.let { }
                @JavascriptInterface fun onSelect(hex: String) = main.post {
                    latestSelect(if (hex.isEmpty()) null else latestAircraft.firstOrNull { it.hex == hex })
                }.let { }
                @JavascriptInterface fun onViewport(lat: Double, lon: Double, n: Double, s: Double, e: Double, w: Double, zoom: Double) = main.post {
                    latestViewport(Viewport(lat, lon, n, s, e, w, zoom))
                }.let { }
            }, "Android")
            webViewClient = object : WebViewClient() {
                override fun shouldInterceptRequest(view: WebView, request: WebResourceRequest): WebResourceResponse? {
                    val url = request.url
                    val host = url.host ?: return null
                    if (host == ASSET_HOST) {
                        val path = url.path?.trimStart('/') ?: return null
                        val mime = when {
                            path.endsWith(".js") -> "application/javascript"
                            path.endsWith(".css") -> "text/css"
                            path.endsWith(".html") -> "text/html"
                            else -> "application/octet-stream"
                        }
                        return runCatching { WebResourceResponse(mime, "utf-8", view.context.assets.open(path)) }.getOrNull()
                    }
                    if (request.method == "GET" && host in TileCache.HOSTS) return cache.respond(url.toString())
                    return null
                }
            }
            loadUrl("https://$ASSET_HOST/map/index.html")
        }
    }

    fun js(code: String) = web.evaluateJavascript(code, null)

    DisposableEffect(lifecycle) {
        val observer = LifecycleEventObserver { _, e ->
            when (e) {
                Lifecycle.Event.ON_RESUME -> web.onResume()
                Lifecycle.Event.ON_PAUSE -> web.onPause()
                else -> Unit
            }
        }
        lifecycle.addObserver(observer)
        onDispose { lifecycle.removeObserver(observer) }
    }
    DisposableEffect(Unit) { onDispose { web.destroy() } }

    LaunchedEffect(ready, mode) { if (ready) js("sky.setStyle(${MapStyle.forMode(mode)}, '${mode.name}')") }
    LaunchedEffect(ready, aircraft) { if (ready) js("sky.setPlanes(${planesJson(aircraft)})") }
    LaunchedEffect(ready, trails) { if (ready) js("sky.setTrails(${trailsJson(trails)})") }
    LaunchedEffect(ready, selected?.hex, selectedTrack, selectedRoute) {
        if (ready) js("sky.setSelection(${selected?.hex?.let { JSONObject.quote(it) } ?: "null"}, ${pathJson(selectedTrack)}, ${routeJson(selectedRoute)})")
    }
    LaunchedEffect(ready, tilted) { if (ready) js("sky.setTilt($tilted)") }
    LaunchedEffect(ready, camera?.id) {
        val c = camera ?: return@LaunchedEffect
        if (ready) js("sky.camera(${c.lat}, ${c.lon}, ${c.zoom}, ${c.fitIraq})")
    }
    LaunchedEffect(ready, showRouteRequest) { if (ready && showRouteRequest > 0) js("sky.showRoute()") }

    AndroidView(factory = { web }, modifier = modifier)
}

fun colorFor(a: Aircraft): Int = when (kindOf(a)) {
    3 -> PlaneIcons.COLOR_WATCHED
    1 -> PlaneIcons.COLOR_OTHER
    2 -> PlaneIcons.COLOR_UNCLASSIFIED
    else -> PlaneIcons.COLOR_CIVIL
}
