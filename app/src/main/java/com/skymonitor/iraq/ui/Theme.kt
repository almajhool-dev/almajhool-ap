package com.skymonitor.iraq.ui

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.unit.LayoutDirection

object Radar {
    val Bg = Color(0xFF070D12)
    val Panel = Color(0xF00C161D)
    val PanelSolid = Color(0xFF0C161D)
    val Line = Color(0xFF1C3340)
    val Green = Color(0xFF35F0A2)
    val GreenDim = Color(0xFF1E7F5A)
    val Amber = Color(0xFFFFB547)
    val Red = Color(0xFFFF4D5E)
    val Sky = Color(0xFF7FB8D6)
    val Text = Color(0xFFDDEBE6)
    val Muted = Color(0xFF7D948F)
}

private val Scheme = darkColorScheme(
    primary = Radar.Green,
    onPrimary = Color(0xFF00281A),
    secondary = Radar.Amber,
    background = Radar.Bg,
    surface = Radar.PanelSolid,
    onSurface = Radar.Text,
    onBackground = Radar.Text,
    surfaceVariant = Color(0xFF13222B),
    onSurfaceVariant = Radar.Muted,
    outline = Radar.Line,
    error = Radar.Red,
)

@Composable
fun SkyTheme(content: @Composable () -> Unit) {
    // The interface is Arabic, so it is always laid out right-to-left.
    CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Rtl) {
        MaterialTheme(colorScheme = Scheme, content = content)
    }
}
