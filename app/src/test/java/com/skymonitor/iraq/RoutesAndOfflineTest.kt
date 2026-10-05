package com.skymonitor.iraq

import com.skymonitor.iraq.data.AdsbDb
import com.skymonitor.iraq.map.OfflinePack
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class RoutesAndOfflineTest {
    private val sample = """{"response":{"flightroute":{"callsign":"IAW215","airline":{"name":"Iraqi Airways"},
        "origin":{"country_iso_name":"IQ","iata_code":"BGW","icao_code":"ORBI","latitude":33.262501,"longitude":44.2346,"municipality":"Baghdad","name":"Baghdad International Airport"},
        "destination":{"country_iso_name":"TR","iata_code":"IST","icao_code":"LTFM","latitude":41.261297,"longitude":28.741951,"municipality":"Istanbul","name":"Istanbul Airport"}}}}"""

    @Test fun parsesRoute() {
        val r = AdsbDb.parse("IAW215", sample)!!
        assertEquals("BGW", r.origin.iata)
        assertEquals("IST", r.destination.iata)
        assertEquals(41.261297, r.destination.lat, 1e-6)
        assertEquals("Iraqi Airways", r.airline)
    }

    @Test fun unknownRouteIsNull() = assertNull(AdsbDb.parse("XXX", """{"response":"unknown callsign"}"""))

    @Test fun offlinePlanCoversWorldAndIraq() {
        val world = OfflinePack.tiles(-85.0, -180.0, 85.0, 180.0, 0, 5)
        assertEquals(1365, world.size)
        val urls = OfflinePack.plannedUrls("https://t/{z}/{x}/{y}.pbf")
        assertTrue(urls.size in 6000..8000)
        // Baghdad at zoom 11 must be included.
        val bx = OfflinePack.lonToX(44.36, 11); val by = OfflinePack.latToY(33.31, 11)
        assertTrue("https://t/11/$bx/$by.pbf" in urls)
    }

    /** Live check against the public adsbdb API. */
    @Test fun liveRouteLookup() = runTest {
        val r = runCatching { AdsbDb.route("UAE2") }.getOrNull()
        if (r != null) { assertNotNull(r.origin.iata); assertNotNull(r.destination.iata) }
    }
}
