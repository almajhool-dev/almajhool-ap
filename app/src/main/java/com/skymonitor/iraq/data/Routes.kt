package com.skymonitor.iraq.data

import org.json.JSONObject
import java.util.Locale

data class Airport(val iata: String?, val icao: String?, val name: String, val city: String?, val countryIso: String?, val lat: Double, val lon: Double) {
    /** "بغداد (BGW) · العراق" — country in Arabic from the system locale data. */
    val labelAr: String
        get() {
            val code = iata ?: icao
            val country = countryIso?.let { Locale("", it).getDisplayCountry(Locale("ar")) }?.takeIf { it.isNotBlank() }
            return listOfNotNull(city ?: name, code?.let { "($it)" }).joinToString(" ") + (country?.let { " · $it" } ?: "")
        }
}

data class FlightRoute(val callsign: String, val airline: String?, val origin: Airport, val destination: Airport)

/**
 * adsbdb.com — free, public, open-source database of published flight routes by callsign.
 * The route is the one registered for the callsign; it can differ from today's actual flight.
 */
object AdsbDb {
    private const val BASE = "https://api.adsbdb.com/v0"
    private val cache = HashMap<String, FlightRoute?>()

    suspend fun route(callsign: String): FlightRoute? {
        val cs = callsign.trim().uppercase()
        if (cs.length < 3 || !cs.matches(Regex("[A-Z0-9]+"))) return null
        synchronized(cache) { if (cache.containsKey(cs)) return cache[cs] }
        val r = try { parse(cs, httpGetJson("$BASE/callsign/$cs")) } catch (e: SourceException) {
            if (e.message?.contains("404") == true) null else throw e
        }
        synchronized(cache) { cache[cs] = r }
        return r
    }

    internal fun parse(cs: String, body: String): FlightRoute? {
        val fr = JSONObject(body).optJSONObject("response")?.optJSONObject("flightroute") ?: return null
        fun ap(o: JSONObject?): Airport? = o?.let {
            if (!it.has("latitude")) return null
            Airport(it.optString("iata_code").ifBlank { null }, it.optString("icao_code").ifBlank { null },
                it.optString("name"), it.optString("municipality").ifBlank { null }, it.optString("country_iso_name").ifBlank { null },
                it.getDouble("latitude"), it.getDouble("longitude"))
        }
        val o = ap(fr.optJSONObject("origin")) ?: return null
        val d = ap(fr.optJSONObject("destination")) ?: return null
        return FlightRoute(cs, fr.optJSONObject("airline")?.optString("name")?.ifBlank { null }, o, d)
    }
}
