package com.skymonitor.iraq

import android.content.Context
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.text.font.FontWeight
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.skymonitor.iraq.ui.DISCLAIMER
import com.skymonitor.iraq.ui.MapActions
import com.skymonitor.iraq.ui.MapScreen
import com.skymonitor.iraq.ui.Radar
import com.skymonitor.iraq.ui.SkyTheme
import com.skymonitor.iraq.ui.SourcesScreen

class MainActivity : ComponentActivity() {
    private val vm: MainViewModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        val prefs = getSharedPreferences("sky", Context.MODE_PRIVATE)
        setContent {
            SkyTheme {
                val state by vm.state.collectAsStateWithLifecycle()
                var showSources by rememberSaveable { mutableStateOf(false) }
                var showIntro by remember { mutableStateOf(!prefs.getBoolean("intro_ack", false)) }

                if (showSources) {
                    BackHandler { showSources = false }
                    SourcesScreen(state) { showSources = false }
                } else {
                    BackHandler(enabled = state.selected != null || state.searchResults != null) {
                        if (state.searchResults != null) vm.closeSearch() else vm.select(null)
                    }
                    MapScreen(
                        state,
                        MapActions(
                            onSelect = vm::select,
                            onViewport = vm::onViewportChanged,
                            onRegion = vm::setRegion,
                            onToggleCivil = vm::toggleCivil,
                            onToggleOther = vm::toggleOther,
                            onToggleWatched = vm::toggleWatched,
                            onQuery = vm::setQuery,
                            onSubmitSearch = vm::submitSearch,
                            onCloseSearch = vm::closeSearch,
                            onFocus = vm::focus,
                            onRefresh = vm::refreshNow,
                            onOpenSources = { showSources = true },
                            onDismissBanner = vm::dismissBanner,
                        ),
                    )
                }

                if (showIntro) {
                    AlertDialog(
                        onDismissRequest = {},
                        containerColor = Radar.PanelSolid,
                        title = { Text("تنبيه مهم", color = Radar.Amber, fontWeight = FontWeight.Bold) },
                        text = {
                            Text(
                                "$DISCLAIMER\n\nيعرض التطبيق فقط ما تنشره شبكات تتبّع الطيران العامة (adsb.fi و adsb.lol و OpenSky). " +
                                    "لا يكشف الطائرات التي لا تبث بيانات، ولا يعترض أي اتصالات.\n\nتطوير: المبرمج المجهول",
                                color = Radar.Text,
                            )
                        },
                        confirmButton = {
                            TextButton(onClick = { prefs.edit().putBoolean("intro_ack", true).apply(); showIntro = false }) {
                                Text("فهمت", color = Radar.Green, fontWeight = FontWeight.Bold)
                            }
                        },
                    )
                }
            }
        }
    }

    override fun onResume() { super.onResume(); vm.setActive(true) }
    override fun onPause() { super.onPause(); vm.setActive(false) }
}
