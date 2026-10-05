package com.skymonitor.iraq

import android.app.Application
import org.osmdroid.config.Configuration
import java.io.File

class SkyApp : Application() {
    override fun onCreate() {
        super.onCreate()
        // osmdroid: identify the app to tile servers and keep the tile cache in private storage (no permissions needed).
        Configuration.getInstance().apply {
            userAgentValue = "SkyMonitorIraq/${BuildConfig.VERSION_NAME} (Android)"
            osmdroidBasePath = File(cacheDir, "osmdroid")
            osmdroidTileCache = File(cacheDir, "osmdroid/tiles")
            tileFileSystemCacheMaxBytes = 120L * 1024 * 1024
            tileFileSystemCacheTrimBytes = 90L * 1024 * 1024
        }
    }
}
