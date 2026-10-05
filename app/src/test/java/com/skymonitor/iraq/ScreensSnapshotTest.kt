package com.skymonitor.iraq

import app.cash.paparazzi.DeviceConfig
import app.cash.paparazzi.Paparazzi
import com.skymonitor.iraq.data.Aircraft
import com.skymonitor.iraq.data.Category
import com.skymonitor.iraq.data.DataSource
import com.skymonitor.iraq.ui.MapActions
import com.skymonitor.iraq.ui.MapScreen
import com.skymonitor.iraq.ui.SkyTheme
import com.skymonitor.iraq.ui.SourcesScreen
import org.junit.Rule
import org.junit.Test

class ScreensSnapshotTest {
    @get:Rule val paparazzi = Paparazzi(deviceConfig = DeviceConfig.PIXEL_5)

    private val now = System.currentTimeMillis()
    private val reaper = Aircraft("ae5f3c", "TOXIN21", "16-4120", "Q9", "General Atomics MQ-9 Reaper", 33.4, 44.1, 24000, false, 170.0, 312.0, now - 9000, Category.OTHER, DataSource.ADSB_FI)
    private val noop = MapActions({}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {})
    private val base = UiState(
        visible = listOf(reaper), lastRefreshMs = now - 4000,
        statuses = UiState().statuses.mapIndexed { i, s -> if (i == 0) s.copy(lastSuccessMs = now - 4000, lastAttemptMs = now - 4000, medianDelaySec = 3, count = 71) else s.copy(lastAttemptMs = now - 9000, error = "تم تجاوز حد الطلبات المسموح به لدى المصدر، سيُعاد المحاولة لاحقاً") },
    )

    @Test fun mapWithSelection() = paparazzi.snapshot { SkyTheme { MapScreen(base.copy(selected = reaper), noop, showMap = false) } }
    @Test fun mapEmpty() = paparazzi.snapshot { SkyTheme { MapScreen(base.copy(visible = emptyList(), filters = Filters(watchedOnly = true)), noop, showMap = false) } }
    @Test fun sources() = paparazzi.snapshot { SkyTheme { SourcesScreen(base) {} } }
}
