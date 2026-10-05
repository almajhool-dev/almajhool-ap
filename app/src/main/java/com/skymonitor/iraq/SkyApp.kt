package com.skymonitor.iraq

import android.app.Application
import com.skymonitor.iraq.map.TileCache

class SkyApp : Application() {
    override fun onCreate() {
        super.onCreate()
        // Warm the tile store so the first map frame can be served from disk.
        TileCache.get(this)
    }
}
