package com.skymonitor.iraq

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.unit.dp
import app.cash.paparazzi.Paparazzi
import com.skymonitor.iraq.ui.PlaneIcons
import com.skymonitor.iraq.ui.Radar
import org.junit.Rule
import org.junit.Test

class IconsSnapshotTest {
    @get:Rule val paparazzi = Paparazzi()

    @Test fun icons() = paparazzi.snapshot {
        val icons = PlaneIcons.all(3f)
        Row(Modifier.background(Radar.Bg).padding(12.dp)) {
            icons.values.forEachIndexed { i, b ->
                Image(b.asImageBitmap(), null, Modifier.size(72.dp).rotate(i * 30f))
            }
        }
    }
}
