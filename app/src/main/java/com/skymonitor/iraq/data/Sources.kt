package com.skymonitor.iraq.data

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.io.IOException
import java.net.HttpURLConnection
import java.net.SocketTimeoutException
import java.net.URL
import java.net.UnknownHostException

/** A failure we can explain to the user in plain Arabic. */
class SourceException(val userMessage: String, cause: Throwable? = null) : Exception(userMessage, cause)

/** Result of one request: aircraft plus the source's own clock, used to measure data delay. */
data class FetchResult(val aircraft: List<Aircraft>, val sourceTimeMs: Long)

private const val USER_AGENT = "SkyMonitorIraq/1.0 (Android; public ADS-B viewer)"

internal suspend fun httpGetJson(url: String): String = withContext(Dispatchers.IO) {
    val conn = (URL(url).openConnection() as HttpURLConnection).apply {
        connectTimeout = 12_000
        readTimeout = 20_000
        requestMethod = "GET"
        setRequestProperty("Accept", "application/json")
        setRequestProperty("User-Agent", USER_AGENT)
    }
    try {
        val code = conn.responseCode
        when {
            code == 429 -> throw SourceException("تم تجاوز حد الطلبات المسموح به لدى المصدر، سيُعاد المحاولة لاحقاً")
            code in 500..599 -> throw SourceException("خادم المصدر لا يستجيب حالياً (رمز $code)")
            code !in 200..299 -> throw SourceException("رفض المصدر الطلب (رمز $code)")
        }
        conn.inputStream.bufferedReader().use { it.readText() }
    } catch (e: SourceException) {
        throw e
    } catch (e: UnknownHostException) {
        throw SourceException("تعذّر الوصول إلى المصدر — تحقّق من اتصال الإنترنت", e)
    } catch (e: SocketTimeoutException) {
        throw SourceException("انتهت مهلة الاتصال بالمصدر", e)
    } catch (e: IOException) {
        throw SourceException("خطأ في الاتصال بالمصدر", e)
    } finally {
        conn.disconnect()
    }
}

/**
 * adsb.fi Open Data API — free public API for non-commercial use with attribution.
 * Docs: https://github.com/adsbfi/opendata  (rate limit: 1 request / second)
 */
object AdsbFi {
    private const val BASE = "https://opendata.adsb.fi/api"

    suspend fun around(lat: Double, lon: Double, radiusNm: Int): FetchResult =
        parse(httpGetJson("$BASE/v3/lat/${"%.4f".format(java.util.Locale.US, lat)}/lon/${"%.4f".format(java.util.Locale.US, lon)}/dist/${radiusNm.coerceIn(1, 250)}"))

    /** Aircraft flagged as military/government in the source's public database, worldwide. */
    suspend fun publiclyFlagged(): FetchResult = parse(httpGetJson("$BASE/v2/mil"))

    suspend fun byCallsign(cs: String): FetchResult =
        parse(httpGetJson("$BASE/v2/callsign/${java.net.URLEncoder.encode(cs.trim().uppercase(), "UTF-8")}"))

    suspend fun byRegistration(reg: String): FetchResult =
        parse(httpGetJson("$BASE/v2/registration/${java.net.URLEncoder.encode(reg.trim().uppercase(), "UTF-8")}"))

    internal fun parse(body: String): FetchResult {
        val root = try { JSONObject(body) } catch (e: Exception) { throw SourceException("استجابة غير صالحة من المصدر", e) }
        val now = root.optLong("now", System.currentTimeMillis()).let { if (it < 10_000_000_000L) it * 1000 else it }
        val arr: JSONArray = root.optJSONArray("ac") ?: root.optJSONArray("aircraft") ?: JSONArray()
        val list = ArrayList<Aircraft>(arr.length())
        for (i in 0 until arr.length()) {
            val o = arr.optJSONObject(i) ?: continue
            if (!o.has("lat") || !o.has("lon")) continue // no public position → nothing to place on the map
            val altRaw = o.opt("alt_baro")
            val onGround = altRaw is String && altRaw.equals("ground", true)
            val alt = when {
                onGround -> 0
                altRaw is Number -> altRaw.toInt()
                o.has("alt_geom") -> o.optInt("alt_geom")
                else -> null
            }
            val seenPos = o.optDouble("seen_pos", o.optDouble("seen", 0.0)).let { if (it.isNaN()) 0.0 else it }
            val flags = o.optInt("dbFlags", 0)
            list += Aircraft(
                hex = o.optString("hex").removePrefix("~"),
                callsign = o.optString("flight").trim().ifEmpty { null },
                registration = o.optString("r").trim().ifEmpty { null },
                typeCode = o.optString("t").trim().ifEmpty { null },
                description = o.optString("desc").trim().ifEmpty { null },
                lat = o.optDouble("lat"),
                lon = o.optDouble("lon"),
                altitudeFt = alt,
                onGround = onGround,
                speedKt = o.optDouble("gs").takeUnless { it.isNaN() },
                trackDeg = (o.optDouble("track").takeUnless { it.isNaN() } ?: o.optDouble("true_heading").takeUnless { it.isNaN() }),
                positionTimeMs = now - (seenPos * 1000).toLong(),
                category = if (flags and 1 == 1) Category.OTHER else Category.CIVIL,
                source = DataSource.ADSB_FI,
            )
        }
        return FetchResult(list, now)
    }
}

/**
 * OpenSky Network REST API — anonymous access, non-commercial use, attribution required.
 * Docs: https://openskynetwork.github.io/opensky-api/rest.html  (anonymous: limited daily credits, 10 s resolution)
 */
object OpenSky {
    suspend fun box(minLat: Double, minLon: Double, maxLat: Double, maxLon: Double): FetchResult {
        val f = { v: Double -> "%.3f".format(java.util.Locale.US, v) }
        val body = httpGetJson("https://opensky-network.org/api/states/all?lamin=${f(minLat)}&lomin=${f(minLon)}&lamax=${f(maxLat)}&lomax=${f(maxLon)}")
        val root = try { JSONObject(body) } catch (e: Exception) { throw SourceException("استجابة غير صالحة من OpenSky", e) }
        val time = root.optLong("time", System.currentTimeMillis() / 1000) * 1000
        val states = root.optJSONArray("states") ?: JSONArray()
        val list = ArrayList<Aircraft>(states.length())
        for (i in 0 until states.length()) {
            val s = states.optJSONArray(i) ?: continue
            if (s.isNull(5) || s.isNull(6)) continue
            val altM = if (!s.isNull(7)) s.optDouble(7) else if (!s.isNull(13)) s.optDouble(13) else Double.NaN
            val posTime = if (!s.isNull(3)) s.optLong(3) * 1000 else time
            list += Aircraft(
                hex = s.optString(0),
                callsign = s.optString(1).trim().ifEmpty { null },
                registration = null,
                typeCode = null,
                description = null,
                lat = s.optDouble(6),
                lon = s.optDouble(5),
                altitudeFt = altM.takeUnless { it.isNaN() }?.let { (it * 3.28084).toInt() },
                onGround = s.optBoolean(8, false),
                speedKt = if (!s.isNull(9)) s.optDouble(9) * 1.943844 else null,
                trackDeg = if (!s.isNull(10)) s.optDouble(10) else null,
                positionTimeMs = posTime,
                category = Category.UNCLASSIFIED,
                source = DataSource.OPENSKY,
                country = s.optString(2).ifEmpty { null },
            )
        }
        return FetchResult(list, time)
    }
}
