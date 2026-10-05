package com.skymonitor.iraq.data

/** Where a record came from. Both are public, community-fed ADS-B/MLAT networks. */
enum class DataSource(val label: String, val site: String) {
    ADSB_FI("adsb.fi Open Data", "https://adsb.fi"),
    ADSB_LOL("adsb.lol", "https://adsb.lol"),
    OPENSKY("OpenSky Network", "https://opensky-network.org"),
}

/**
 * Category as published by the source. "OTHER" means the source's own public database flags the
 * airframe as military/government; we never infer it ourselves.
 */
enum class Category { CIVIL, OTHER, UNCLASSIFIED }

/** Aircraft types the app highlights when — and only when — they appear in public data. */
enum class WatchedType(val label: String, val typeCodes: Set<String>, val keywords: List<String>) {
    MQ9("MQ-9 Reaper", setOf("Q9"), listOf("MQ-9", "MQ9", "REAPER")),
    MQ1("MQ-1 Predator", setOf("Q1"), listOf("MQ-1", "MQ1", "PREDATOR", "GRAY EAGLE")),
    RQ4("RQ-4 Global Hawk", setOf("Q4"), listOf("RQ-4", "RQ4", "GLOBAL HAWK"));

    fun matches(a: Aircraft): Boolean {
        val t = a.typeCode?.uppercase()
        if (t != null && t in typeCodes) return true
        val d = a.description?.uppercase() ?: return false
        return keywords.any { d.contains(it) }
    }

    companion object {
        /** Maps what a user may type (Latin or Arabic) to a watched type. */
        fun fromQuery(q: String): WatchedType? {
            val s = q.trim().uppercase().replace(" ", "")
            return when {
                s in setOf("MQ-9", "MQ9", "Q9", "REAPER", "ريبر", "ريپر") -> MQ9
                s in setOf("MQ-1", "MQ1", "Q1", "PREDATOR", "بريداتور", "المفترسة") -> MQ1
                s in setOf("RQ-4", "RQ4", "Q4", "GLOBALHAWK", "غلوبالهوك", "جلوبالهوك") -> RQ4
                else -> null
            }
        }
    }
}

data class Aircraft(
    val hex: String,
    val callsign: String?,
    val registration: String?,
    val typeCode: String?,
    val description: String?,
    val lat: Double,
    val lon: Double,
    /** Barometric/geometric altitude in feet; null when not broadcast. */
    val altitudeFt: Int?,
    val onGround: Boolean,
    /** Ground speed in knots. */
    val speedKt: Double?,
    /** Track over ground in degrees (0 = north). */
    val trackDeg: Double?,
    /** Epoch millis of the last position report, as given by the source. */
    val positionTimeMs: Long,
    val category: Category,
    val source: DataSource,
    val country: String? = null,
) {
    val watched: WatchedType? get() = WatchedType.entries.firstOrNull { it.matches(this) }

    val displayName: String
        get() = callsign?.takeIf { it.isNotBlank() } ?: registration?.takeIf { it.isNotBlank() } ?: hex.uppercase()

    fun matchesQuery(q: String): Boolean {
        val s = q.trim().uppercase()
        if (s.isEmpty()) return true
        WatchedType.fromQuery(s)?.let { return it.matches(this) }
        return listOfNotNull(callsign, registration, typeCode, description, hex)
            .any { it.uppercase().contains(s) }
    }
}

object Regions {
    // Iraq bounding box with a small margin around the borders.
    const val IRAQ_MIN_LAT = 28.9
    const val IRAQ_MAX_LAT = 37.5
    const val IRAQ_MIN_LON = 38.6
    const val IRAQ_MAX_LON = 48.9
    const val IRAQ_CENTER_LAT = 33.25
    const val IRAQ_CENTER_LON = 43.70

    fun inIraq(lat: Double, lon: Double) =
        lat in IRAQ_MIN_LAT..IRAQ_MAX_LAT && lon in IRAQ_MIN_LON..IRAQ_MAX_LON
}
