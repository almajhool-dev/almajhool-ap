package com.skymonitor.iraq

import android.app.Application
import org.maplibre.android.MapLibre

class SkyApp : Application() {
    override fun onCreate() {
        super.onCreate()
        MapLibre.getInstance(this)
    }
}
