package com.skymonitor.iraq

import android.app.Application
import org.maplibre.android.MapLibre
import org.maplibre.android.offline.OfflineManager

class SkyApp : Application() {
    override fun onCreate() {
        super.onCreate()
        MapLibre.getInstance(this)
        // Larger on-disk tile cache so revisited areas (and the app's start view) open instantly.
        runCatching {
            OfflineManager.getInstance(this).setMaximumAmbientCacheSize(300L * 1024 * 1024, null)
        }
    }
}
