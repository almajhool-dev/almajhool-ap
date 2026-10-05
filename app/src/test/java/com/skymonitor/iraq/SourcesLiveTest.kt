package com.skymonitor.iraq

import com.skymonitor.iraq.data.AdsbFi
import com.skymonitor.iraq.data.Aircraft
import com.skymonitor.iraq.data.Category
import com.skymonitor.iraq.data.DataSource
import com.skymonitor.iraq.data.OpenSky
import com.skymonitor.iraq.data.Regions
import com.skymonitor.iraq.data.WatchedType
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

class SourcesLiveTest {
    private fun ac(t: String?, d: String?) = Aircraft("abc", "TEST1", null, t, d, 33.0, 44.0, 20000, false, 300.0, 90.0, 0, Category.OTHER, DataSource.ADSB_FI)

    @Test fun watchedTypeMatching() {
        assertEquals(WatchedType.MQ9, ac("Q9", null).watched)
        assertEquals(WatchedType.RQ4, ac(null, "Northrop Grumman RQ-4 Global Hawk").watched)
        assertEquals(WatchedType.MQ1, ac(null, "General Atomics MQ-1C Gray Eagle").watched)
        assertEquals(null, ac("C30J", "Lockheed Martin KC-130J Hercules").watched)
        assertEquals(WatchedType.MQ9, WatchedType.fromQuery("mq-9"))
        assertEquals(WatchedType.RQ4, WatchedType.fromQuery("RQ4"))
        assertTrue(ac("Q9", null).matchesQuery("MQ-9"))
    }

    @Test fun parsesAdsbFiSample() {
        val body = """{"ac":[{"hex":"ae1480","flight":"BERT10  ","r":"166763","t":"C30J","dbFlags":1,"desc":"Lockheed Martin KC-130J Hercules","alt_baro":8050,"gs":278.6,"track":251.37,"lat":37.7,"lon":-121.1,"seen_pos":2.0},
            {"hex":"7061f5","flight":"KAF3202 ","t":"C30J","dbFlags":0,"alt_baro":"ground","gs":16.5,"lat":29.2,"lon":47.9},
            {"hex":"nopos","flight":"X"}],"now":1791167506001}"""
        val r = AdsbFi.parse(body)
        assertEquals(2, r.aircraft.size)
        val a = r.aircraft[0]
        assertEquals("BERT10", a.callsign); assertEquals(Category.OTHER, a.category); assertEquals(8050, a.altitudeFt)
        assertEquals(1791167504001L, a.positionTimeMs)
        assertTrue(r.aircraft[1].onGround); assertEquals(Category.CIVIL, r.aircraft[1].category)
    }

    @Test fun liveAdsbFiAndOpenSky() = runBlocking {
        val mil = AdsbFi.publiclyFlagged()
        println("adsb.fi /v2/mil: ${mil.aircraft.size} aircraft; sample=${mil.aircraft.firstOrNull()}")
        assertTrue(mil.aircraft.all { it.category == Category.OTHER })
        Thread.sleep(1200)
        val iraq = AdsbFi.around(31.2, 45.9, 250)
        println("adsb.fi south Iraq: ${iraq.aircraft.size}")
        val os = OpenSky.box(Regions.IRAQ_MIN_LAT, Regions.IRAQ_MIN_LON, Regions.IRAQ_MAX_LAT, Regions.IRAQ_MAX_LON)
        println("OpenSky Iraq box: ${os.aircraft.size}; sample=${os.aircraft.firstOrNull()}")
        assertNotNull(os)
    }
}
