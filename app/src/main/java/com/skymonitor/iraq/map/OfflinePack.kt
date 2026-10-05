package com.skymonitor.iraq.map

import android.content.Context
import com.skymonitor.iraq.data.Regions
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import org.json.JSONObject
import kotlin.math.PI
import kotlin.math.floor
import kotlin.math.ln
import kotlin.math.tan

data class OfflineState(val running: Boolean = false, val done: Int = 0, val total: Int = 0, val failed: Int = 0,
                        val finishedAtMs: Long? = null, val error: String? = null)

/**
 * Saves a map for use without internet: the whole world at overview zoom, Iraq down to city/street level,
 * terrain for Iraq and the Arabic fonts. Satellite imagery is not bulk-downloaded (Esri's terms do not allow it);
 * satellite areas you view are still kept by [TileCache].
 */
object OfflinePack {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var job: Job? = null
    private val _state = MutableStateFlow(OfflineState())
    val state: StateFlow<OfflineState> = _state.asStateFlow()

    private const val TILEJSON = "https://tiles.openfreemap.org/planet"
    private const val DEM = "https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png"
    private const val FONTS = "https://tiles.openfreemap.org/fonts/{fontstack}/{range}.pbf"
    private val FONT_STACKS = listOf("Noto%20Sans%20Regular", "Noto%20Sans%20Bold")
    private val GLYPH_RANGES = listOf(0, 256, 512, 768, 1536, 1792, 8192, 64256, 64512, 64768, 65024, 65280)

    fun lonToX(lon: Double, z: Int) = floor((lon + 180) / 360 * (1 shl z)).toInt().coerceIn(0, (1 shl z) - 1)
    fun latToY(lat: Double, z: Int): Int {
        val r = Math.toRadians(lat)
        return floor((1 - ln(tan(r) + 1 / kotlin.math.cos(r)) / PI) / 2 * (1 shl z)).toInt().coerceIn(0, (1 shl z) - 1)
    }

    /** Tile coordinates covering a lat/lon box for zooms [minZ]..[maxZ]. */
    fun tiles(minLat: Double, minLon: Double, maxLat: Double, maxLon: Double, minZ: Int, maxZ: Int): List<Triple<Int, Int, Int>> {
        val out = ArrayList<Triple<Int, Int, Int>>()
        for (z in minZ..maxZ) for (x in lonToX(minLon, z)..lonToX(maxLon, z)) for (y in latToY(maxLat, z)..latToY(minLat, z)) out += Triple(z, x, y)
        return out
    }

    fun plannedUrls(vectorTemplate: String): List<String> {
        fun t(tpl: String, c: Triple<Int, Int, Int>) = tpl.replace("{z}", "${c.first}").replace("{x}", "${c.second}").replace("{y}", "${c.third}")
        val world = tiles(-85.0, -180.0, 85.0, 180.0, 0, 5)
        val iraq = tiles(Regions.IRAQ_MIN_LAT, Regions.IRAQ_MIN_LON, Regions.IRAQ_MAX_LAT, Regions.IRAQ_MAX_LON, 6, 11)
        val dem = tiles(-85.0, -180.0, 85.0, 180.0, 0, 3) +
            tiles(Regions.IRAQ_MIN_LAT, Regions.IRAQ_MIN_LON, Regions.IRAQ_MAX_LAT, Regions.IRAQ_MAX_LON, 4, 9)
        val glyphs = FONT_STACKS.flatMap { fs -> GLYPH_RANGES.map { r -> FONTS.replace("{fontstack}", fs).replace("{range}", "$r-${r + 255}") } }
        return (world + iraq).map { t(vectorTemplate, it) } + dem.map { t(DEM, it) } + glyphs
    }

    fun start(context: Context) {
        if (job?.isActive == true) return
        val cache = TileCache.get(context)
        job = scope.launch {
            _state.value = OfflineState(running = true)
            val tj = cache.fetch(TILEJSON, networkFirst = true)
            val template = tj?.let { runCatching { JSONObject(String(it)).getJSONArray("tiles").getString(0) }.getOrNull() }
            if (template == null) {
                _state.value = OfflineState(error = "تعذّر الاتصال بخادم الخرائط — تحقّق من الإنترنت"); return@launch
            }
            val urls = plannedUrls(template)
            _state.update { it.copy(total = urls.size) }
            val gate = Semaphore(6)
            urls.chunked(200).forEach { chunk ->
                if (!isActive) return@launch
                chunk.map { u ->
                    async {
                        gate.withPermit {
                            val ok = cache.has(u) || cache.fetch(u) != null
                            _state.update { s -> s.copy(done = s.done + 1, failed = s.failed + if (ok) 0 else 1) }
                        }
                    }
                }.awaitAll()
            }
            _state.update { it.copy(running = false, finishedAtMs = System.currentTimeMillis()) }
        }
    }

    fun cancel() { job?.cancel(); _state.update { it.copy(running = false) } }

}
