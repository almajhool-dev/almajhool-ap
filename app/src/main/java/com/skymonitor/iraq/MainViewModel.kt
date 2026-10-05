package com.skymonitor.iraq

import android.app.Application
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.skymonitor.iraq.data.AdsbFi
import com.skymonitor.iraq.data.AdsbLol
import com.skymonitor.iraq.data.Aircraft
import com.skymonitor.iraq.data.Category
import com.skymonitor.iraq.data.DataSource
import com.skymonitor.iraq.data.FetchResult
import com.skymonitor.iraq.data.OpenSky
import com.skymonitor.iraq.data.Regions
import com.skymonitor.iraq.data.SourceException
import com.skymonitor.iraq.data.WatchedType
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlin.math.abs

enum class Region { IRAQ, WORLD }

data class Viewport(val centerLat: Double, val centerLon: Double, val north: Double, val south: Double, val east: Double, val west: Double, val zoom: Double)

data class SourceStatus(
    val source: DataSource,
    val endpoints: String,
    val lastSuccessMs: Long? = null,
    val lastAttemptMs: Long? = null,
    /** Median age (seconds) of position reports in the last successful response. */
    val medianDelaySec: Long? = null,
    val count: Int = 0,
    val error: String? = null,
    val note: String? = null,
)

data class Filters(
    val region: Region = Region.IRAQ,
    val civil: Boolean = true,
    val other: Boolean = true,
    val watchedOnly: Boolean = false,
)

data class CameraMove(val lat: Double, val lon: Double, val zoom: Double, val id: Long = System.nanoTime())

data class UiState(
    val visible: List<Aircraft> = emptyList(),
    val totalLoaded: Int = 0,
    val filters: Filters = Filters(),
    val query: String = "",
    val selected: Aircraft? = null,
    val refreshing: Boolean = false,
    val offline: Boolean = false,
    val lastRefreshMs: Long? = null,
    val statuses: List<SourceStatus> = listOf(
        SourceStatus(DataSource.ADSB_FI, "/api/v3/lat/{lat}/lon/{lon}/dist/{nm} · /api/v2/mil · /api/v2/callsign · /api/v2/registration"),
        SourceStatus(DataSource.ADSB_LOL, "/v2/point/{lat}/{lon}/{nm} · /v2/mil · /v2/callsign"),
        SourceStatus(DataSource.OPENSKY, "/api/states/all?lamin&lomin&lamax&lomax"),
    ),
    val searchResults: List<Aircraft>? = null,
    val searching: Boolean = false,
    val searchMessage: String? = null,
    val camera: CameraMove? = null,
    val banner: String? = null,
)

class MainViewModel(app: Application) : AndroidViewModel(app) {

    private val _state = MutableStateFlow(UiState(camera = CameraMove(Regions.IRAQ_CENTER_LAT, Regions.IRAQ_CENTER_LON, 6.2)))
    val state: StateFlow<UiState> = _state.asStateFlow()

    /** Latest record per aircraft (ICAO hex). */
    private val byHex = LinkedHashMap<String, Aircraft>()
    /** Last worldwide list of publicly flagged aircraft (used for World view and type search). */
    private var flaggedWorldwide: List<Aircraft> = emptyList()
    private var flaggedFi: List<Aircraft> = emptyList()
    private var flaggedLol: List<Aircraft> = emptyList()
    private fun combineFlagged() { flaggedWorldwide = (flaggedFi + flaggedLol).distinctBy { it.hex } }
    private var viewport: Viewport? = null
    private var lastOpenSkyMs = 0L
    private val adsbLock = Mutex()
    private var loop: Job? = null
    private var active = true

    init { startLoop() }

    fun setActive(isActive: Boolean) {
        active = isActive
        if (isActive && loop?.isActive != true) startLoop()
    }

    private fun startLoop() {
        loop = viewModelScope.launch {
            while (isActive) {
                if (active) refresh()
                delay(REFRESH_MS)
            }
        }
    }

    fun refreshNow() { viewModelScope.launch { refresh(forceOpenSky = false) } }

    fun onViewportChanged(v: Viewport) {
        val old = viewport
        viewport = v
        // In World mode, a big pan should load the new area without waiting for the next cycle.
        if (_state.value.filters.region == Region.WORLD && old != null &&
            (abs(old.centerLat - v.centerLat) > 3 || abs(old.centerLon - v.centerLon) > 3)
        ) refreshNow()
    }

    fun setRegion(r: Region) {
        _state.update {
            it.copy(
                filters = it.filters.copy(region = r),
                camera = if (r == Region.IRAQ) CameraMove(Regions.IRAQ_CENTER_LAT, Regions.IRAQ_CENTER_LON, 6.2)
                else CameraMove(25.0, 30.0, 2.6),
            )
        }
        publish()
        refreshNow()
    }

    fun toggleCivil() { _state.update { it.copy(filters = it.filters.copy(civil = !it.filters.civil)) }; publish() }
    fun toggleOther() { _state.update { it.copy(filters = it.filters.copy(other = !it.filters.other)) }; publish() }
    fun toggleWatched() { _state.update { it.copy(filters = it.filters.copy(watchedOnly = !it.filters.watchedOnly)) }; publish() }

    fun select(a: Aircraft?) = _state.update { it.copy(selected = a) }

    fun focus(a: Aircraft) {
        _state.update { it.copy(selected = a, searchResults = null, camera = CameraMove(a.lat, a.lon, 8.0)) }
    }

    fun dismissBanner() = _state.update { it.copy(banner = null) }

    fun setQuery(q: String) {
        _state.update { it.copy(query = q, searchResults = if (q.isBlank()) null else it.searchResults, searchMessage = null) }
        publish()
    }

    fun closeSearch() = _state.update { it.copy(searchResults = null, searchMessage = null) }

    /** Searches what is already loaded and, when useful, asks the public source directly. */
    fun submitSearch() {
        val q = _state.value.query.trim()
        if (q.isEmpty()) return
        viewModelScope.launch {
            _state.update { it.copy(searching = true, searchMessage = null) }
            val found = LinkedHashMap<String, Aircraft>()
            byHex.values.filter { it.matchesQuery(q) }.forEach { found[it.hex] = it }
            flaggedWorldwide.filter { it.matchesQuery(q) }.forEach { found.putIfAbsent(it.hex, it) }
            var error: String? = null
            if (isOnline()) {
                try {
                    adsbLock.withLock {
                        if (WatchedType.fromQuery(q) != null) {
                            // Watched types only ever appear in public data among flagged aircraft.
                            flaggedFi = AdsbFi.publiclyFlagged().aircraft
                            runCatching { flaggedLol = AdsbLol.publiclyFlagged().aircraft }
                            combineFlagged()
                            flaggedWorldwide.filter { it.matchesQuery(q) }.forEach { found.putIfAbsent(it.hex, it) }
                        } else if (q.length in 2..10 && q.none { it.isWhitespace() }) {
                            AdsbFi.byCallsign(q).aircraft.forEach { found.putIfAbsent(it.hex, it) }
                            delay(ADSB_GAP_MS)
                            AdsbFi.byRegistration(q).aircraft.forEach { found.putIfAbsent(it.hex, it) }
                            runCatching { AdsbLol.byCallsign(q).aircraft.forEach { found.putIfAbsent(it.hex, it) } }
                        }
                    }
                } catch (e: SourceException) {
                    error = e.userMessage
                } catch (e: Exception) {
                    error = "تعذّر إكمال البحث لدى المصدر"
                }
            } else error = "لا يوجد اتصال بالإنترنت — النتائج من البيانات المحمّلة سابقاً فقط"
            val results = found.values.toList()
            val msg = when {
                results.isEmpty() && error != null -> error
                results.isEmpty() -> "لا توجد نتائج تبث بيانات عامة الآن لهذا البحث. عدم ظهور الطائرة لا يعني عدم وجودها."
                error != null -> error
                else -> null
            }
            _state.update { it.copy(searching = false, searchResults = results, searchMessage = msg) }
        }
    }

    private fun isOnline(): Boolean {
        val cm = getApplication<Application>().getSystemService(ConnectivityManager::class.java) ?: return true
        val caps = cm.getNetworkCapabilities(cm.activeNetwork) ?: return false
        return caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
    }

    private suspend fun refresh(forceOpenSky: Boolean = false) {
        if (_state.value.refreshing) return
        if (!isOnline()) {
            _state.update { it.copy(offline = true, banner = "لا يوجد اتصال بالإنترنت. البيانات المعروضة قديمة وستُحدَّث تلقائياً عند عودة الاتصال.") }
            return
        }
        _state.update { it.copy(refreshing = true, offline = false, banner = if (it.offline) null else it.banner) }
        val region = _state.value.filters.region
        val received = ArrayList<Aircraft>()

        // 1) adsb.fi — sequential calls, ≥1 s apart, to respect its rate limit.
        runSource(DataSource.ADSB_FI) {
            adsbLock.withLock {
                val results = ArrayList<FetchResult>()
                if (region == Region.IRAQ) {
                    results += AdsbFi.around(35.6, 43.3, 250); delay(ADSB_GAP_MS)
                    results += AdsbFi.around(31.2, 45.9, 250); delay(ADSB_GAP_MS)
                } else {
                    val v = viewport
                    results += AdsbFi.around(v?.centerLat ?: 25.0, v?.centerLon ?: 30.0, 250); delay(ADSB_GAP_MS)
                }
                val flagged = AdsbFi.publiclyFlagged()
                flaggedFi = flagged.aircraft
                combineFlagged()
                results += flagged
                val all = results.flatMap { it.aircraft }
                received += all
                Triple(all, results.maxOf { it.sourceTimeMs }, null as String?)
            }
        }

        // 1b) adsb.lol — a second independent receiver network; fills gaps in coverage.
        runSource(DataSource.ADSB_LOL) {
            val results = ArrayList<FetchResult>()
            if (region == Region.IRAQ) {
                results += AdsbLol.around(35.6, 43.3, 250)
                results += AdsbLol.around(31.2, 45.9, 250)
            } else {
                val v = viewport
                results += AdsbLol.around(v?.centerLat ?: 25.0, v?.centerLon ?: 30.0, 250)
            }
            val flagged = AdsbLol.publiclyFlagged()
            flaggedLol = flagged.aircraft
            combineFlagged()
            results += flagged
            val all = results.flatMap { it.aircraft }
            received += all
            Triple(all, results.maxOf { it.sourceTimeMs }, null as String?)
        }

        // 2) OpenSky — anonymous quota is small, so it is queried every few minutes for a bounded box.
        val now = System.currentTimeMillis()
        if (forceOpenSky || now - lastOpenSkyMs >= OPENSKY_INTERVAL_MS) {
            val box: DoubleArray? = if (region == Region.IRAQ) {
                doubleArrayOf(Regions.IRAQ_MIN_LAT, Regions.IRAQ_MIN_LON, Regions.IRAQ_MAX_LAT, Regions.IRAQ_MAX_LON)
            } else viewport?.let { v ->
                val area = (v.north - v.south) * (v.east - v.west)
                if (v.east > v.west && area in 0.0..400.0) doubleArrayOf(v.south, v.west, v.north, v.east) else null
            }
            if (box != null) {
                lastOpenSkyMs = now
                runSource(DataSource.OPENSKY) {
                    val r = OpenSky.box(box[0], box[1], box[2], box[3])
                    received += r.aircraft
                    Triple(r.aircraft, r.sourceTimeMs, null as String?)
                }
            } else {
                updateStatus(DataSource.OPENSKY) { it.copy(note = "قرّب الخريطة إلى منطقة أصغر لاستخدام OpenSky (حصة الاستخدام المجاني محدودة)") }
            }
        }

        merge(received)
        _state.update { it.copy(refreshing = false, lastRefreshMs = System.currentTimeMillis()) }
        publish()
    }

    private suspend fun runSource(src: DataSource, block: suspend () -> Triple<List<Aircraft>, Long, String?>) {
        val attempt = System.currentTimeMillis()
        try {
            val (list, srcTime, note) = block()
            val ages = list.map { (srcTime - it.positionTimeMs).coerceAtLeast(0) / 1000 }.sorted()
            updateStatus(src) {
                it.copy(
                    lastAttemptMs = attempt, lastSuccessMs = System.currentTimeMillis(), count = list.size,
                    medianDelaySec = ages.getOrNull(ages.size / 2) ?: 0, error = null, note = note,
                )
            }
        } catch (e: SourceException) {
            updateStatus(src) { it.copy(lastAttemptMs = attempt, error = e.userMessage) }
        } catch (e: Exception) {
            updateStatus(src) { it.copy(lastAttemptMs = attempt, error = "خطأ غير متوقع أثناء جلب البيانات") }
        }
    }

    private fun updateStatus(src: DataSource, f: (SourceStatus) -> SourceStatus) {
        _state.update { s -> s.copy(statuses = s.statuses.map { if (it.source == src) f(it) else it }) }
    }

    private fun merge(fresh: List<Aircraft>) {
        val now = System.currentTimeMillis()
        for (a in fresh) {
            val old = byHex[a.hex]
            // Prefer the newer report; on ties prefer adsb.fi, which also carries type information.
            if (old == null || a.positionTimeMs > old.positionTimeMs + 5_000 ||
                (a.source != DataSource.OPENSKY && old.source == DataSource.OPENSKY && a.positionTimeMs >= old.positionTimeMs - 15_000)
            ) {
                byHex[a.hex] = if (a.typeCode == null && old?.typeCode != null)
                    a.copy(typeCode = old.typeCode, description = old.description, registration = a.registration ?: old.registration, category = old.category)
                else a
            }
        }
        // Forget aircraft whose last public position is too old to be meaningful.
        byHex.values.removeAll { now - it.positionTimeMs > STALE_MS }
    }

    private fun publish() {
        val s = _state.value
        val f = s.filters
        val pool = if (f.region == Region.WORLD) (byHex.values + flaggedWorldwide.filter { it.hex !in byHex }) else byHex.values
        val visible = pool.filter { a ->
            (f.region == Region.WORLD || Regions.inIraq(a.lat, a.lon)) &&
                (if (a.category == Category.OTHER) f.other else f.civil) &&
                (!f.watchedOnly || a.watched != null) &&
                (s.query.isBlank() || a.matchesQuery(s.query))
        }
        val sel = s.selected?.let { cur -> visible.firstOrNull { it.hex == cur.hex } ?: cur }
        _state.update { it.copy(visible = visible, totalLoaded = pool.size, selected = sel) }
    }

    companion object {
        const val REFRESH_MS = 20_000L
        const val ADSB_GAP_MS = 1_100L
        const val OPENSKY_INTERVAL_MS = 5 * 60_000L
        const val STALE_MS = 5 * 60_000L
    }
}
