package com.skymonitor.iraq.ui

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Public
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.WifiOff
import androidx.compose.material.icons.filled.Storage
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.skymonitor.iraq.Region
import com.skymonitor.iraq.UiState
import com.skymonitor.iraq.Viewport
import com.skymonitor.iraq.data.Aircraft
import com.skymonitor.iraq.data.Category
import com.skymonitor.iraq.data.WatchedType

const val DISCLAIMER = "المعلومات المعروضة تعتمد على مصادر طيران عامة، وقد تكون بعض الطائرات العسكرية غير ظاهرة أو بياناتها متأخرة أو محجوبة."

class MapActions(
    val onSelect: (Aircraft?) -> Unit,
    val onViewport: (Viewport) -> Unit,
    val onRegion: (Region) -> Unit,
    val onToggleCivil: () -> Unit,
    val onToggleOther: () -> Unit,
    val onToggleWatched: () -> Unit,
    val onQuery: (String) -> Unit,
    val onSubmitSearch: () -> Unit,
    val onCloseSearch: () -> Unit,
    val onFocus: (Aircraft) -> Unit,
    val onRefresh: () -> Unit,
    val onOpenSources: () -> Unit,
    val onDismissBanner: () -> Unit,
)

@Composable
fun MapScreen(state: UiState, a: MapActions, showMap: Boolean = true) {
    Box(Modifier.fillMaxSize().background(Radar.Bg)) {
        if (showMap) RadarMap(
            aircraft = state.visible,
            selectedHex = state.selected?.hex,
            camera = state.camera,
            onSelect = a.onSelect,
            onViewport = a.onViewport,
            modifier = Modifier.fillMaxSize(),
        )

        Column(Modifier.fillMaxWidth().statusBarsPadding().padding(horizontal = 12.dp, vertical = 8.dp)) {
            TopBar(state, a)
            Spacer(Modifier.size(8.dp))
            SearchField(state, a)
            Spacer(Modifier.size(8.dp))
            FilterRow(state, a)
            state.banner?.let { Spacer(Modifier.size(8.dp)); Banner(it, Icons.Filled.WifiOff, a.onDismissBanner) }
            AnimatedVisibility(state.searchResults != null || state.searching) {
                SearchResults(state, a)
            }
        }

        Column(
            Modifier.align(Alignment.BottomCenter).fillMaxWidth().navigationBarsPadding().padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            if (state.selected == null) {
                EmptyHint(state)
                Legend()
            }
            AnimatedVisibility(
                visible = state.selected != null,
                enter = slideInVertically { it } + fadeIn(),
                exit = slideOutVertically { it } + fadeOut(),
            ) {
                state.selected?.let { DetailPanel(it) { a.onSelect(null) } }
            }
            DisclaimerStrip(a.onOpenSources)
        }
    }
}

@Composable
private fun TopBar(state: UiState, a: MapActions) {
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(Radar.Panel)
            .border(1.dp, Radar.Line, RoundedCornerShape(16.dp)).padding(horizontal = 12.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(Modifier.size(10.dp).clip(CircleShape).background(if (state.offline) Radar.Red else Radar.Green))
        Spacer(Modifier.width(10.dp))
        Column(Modifier.weight(1f)) {
            Text("Sky Monitor Iraq", color = Radar.Text, fontWeight = FontWeight.Bold, fontSize = 16.sp)
            Text(
                if (state.offline) "غير متصل — آخر تحديث ${agoText(state.lastRefreshMs)}"
                else "${state.visible.size} ظاهرة · آخر تحديث ${agoText(state.lastRefreshMs)}",
                color = Radar.Muted, fontSize = 12.sp,
            )
        }
        if (state.refreshing) CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp, color = Radar.Green)
        else IconButton(onClick = a.onRefresh) { Icon(Icons.Filled.Refresh, "تحديث", tint = Radar.Green) }
        IconButton(onClick = a.onOpenSources) { Icon(Icons.Filled.Storage, "مصدر البيانات", tint = Radar.Text) }
    }
}

@Composable
private fun SearchField(state: UiState, a: MapActions) {
    val focus = LocalFocusManager.current
    OutlinedTextField(
        value = state.query,
        onValueChange = a.onQuery,
        modifier = Modifier.fillMaxWidth(),
        singleLine = true,
        placeholder = { Text("ابحث بالنداء، التسجيل، أو الطراز (مثل MQ-9 أو RQ-4)", fontSize = 13.sp, maxLines = 1, overflow = TextOverflow.Ellipsis) },
        leadingIcon = { Icon(Icons.Filled.Search, null, tint = Radar.Muted) },
        trailingIcon = {
            if (state.query.isNotEmpty()) IconButton(onClick = { a.onQuery(""); a.onCloseSearch() }) { Icon(Icons.Filled.Close, "مسح", tint = Radar.Muted) }
        },
        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
        keyboardActions = KeyboardActions(onSearch = { focus.clearFocus(); a.onSubmitSearch() }),
        shape = RoundedCornerShape(14.dp),
        colors = OutlinedTextFieldDefaults.colors(
            focusedContainerColor = Radar.Panel, unfocusedContainerColor = Radar.Panel,
            focusedBorderColor = Radar.Green, unfocusedBorderColor = Radar.Line,
            cursorColor = Radar.Green, focusedTextColor = Radar.Text, unfocusedTextColor = Radar.Text,
        ),
    )
}

@Composable
private fun Chip(label: String, selected: Boolean, color: Color = Radar.Green, onClick: () -> Unit) {
    Box(
        Modifier.clip(RoundedCornerShape(50)).background(if (selected) color.copy(alpha = 0.18f) else Radar.Panel)
            .border(1.dp, if (selected) color else Radar.Line, RoundedCornerShape(50))
            .clickable(onClick = onClick).padding(horizontal = 14.dp, vertical = 7.dp),
    ) { Text(label, color = if (selected) color else Radar.Muted, fontSize = 13.sp, fontWeight = if (selected) FontWeight.Bold else FontWeight.Normal) }
}

@Composable
private fun FilterRow(state: UiState, a: MapActions) {
    val f = state.filters
    Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Chip("العراق فقط", f.region == Region.IRAQ) { a.onRegion(Region.IRAQ) }
        Chip("العالم", f.region == Region.WORLD) { a.onRegion(Region.WORLD) }
        Chip("الطائرات المدنية", f.civil, Radar.Green, a.onToggleCivil)
        Chip("فئات أخرى (مصنّفة علناً)", f.other, Radar.Amber, a.onToggleOther)
        Chip("MQ-9 · MQ-1 · RQ-4", f.watchedOnly, Radar.Red, a.onToggleWatched)
    }
}

@Composable
private fun Banner(text: String, icon: androidx.compose.ui.graphics.vector.ImageVector, onClose: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(Color(0xF0301318))
            .border(1.dp, Radar.Red.copy(alpha = .6f), RoundedCornerShape(12.dp)).padding(10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(icon, null, tint = Radar.Red, modifier = Modifier.size(20.dp))
        Spacer(Modifier.width(8.dp))
        Text(text, color = Radar.Text, fontSize = 13.sp, modifier = Modifier.weight(1f))
        IconButton(onClick = onClose, modifier = Modifier.size(28.dp)) { Icon(Icons.Filled.Close, "إغلاق", tint = Radar.Muted) }
    }
}

@Composable
private fun SearchResults(state: UiState, a: MapActions) {
    Column(
        Modifier.padding(top = 8.dp).fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(Radar.Panel)
            .border(1.dp, Radar.Line, RoundedCornerShape(14.dp)).padding(10.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                if (state.searching) "جارٍ البحث في المصادر العامة…" else "نتائج البحث (${state.searchResults?.size ?: 0})",
                color = Radar.Text, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f),
            )
            if (state.searching) CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp, color = Radar.Green)
            else IconButton(onClick = a.onCloseSearch, modifier = Modifier.size(28.dp)) { Icon(Icons.Filled.Close, "إغلاق", tint = Radar.Muted) }
        }
        state.searchMessage?.let { Text(it, color = Radar.Muted, fontSize = 13.sp, modifier = Modifier.padding(vertical = 6.dp)) }
        val results = state.searchResults.orEmpty()
        if (results.isNotEmpty()) {
            LazyColumn(Modifier.heightIn(max = 260.dp)) {
                items(results, key = { it.hex + it.source }) { r ->
                    Row(
                        Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp)).clickable { a.onFocus(r) }.padding(vertical = 8.dp, horizontal = 6.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Box(Modifier.size(10.dp).clip(CircleShape).background(Color(colorFor(r))))
                        Spacer(Modifier.width(10.dp))
                        Column(Modifier.weight(1f)) {
                            Text(r.displayName, color = Radar.Text, fontWeight = FontWeight.Bold)
                            Text(
                                listOfNotNull(r.watched?.label ?: r.description ?: r.typeCode, altitudeText(r.altitudeFt, r.onGround)).joinToString(" · "),
                                color = Radar.Muted, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis,
                            )
                        }
                        Text(agoText(r.positionTimeMs), color = Radar.Muted, fontSize = 11.sp)
                    }
                }
            }
        }
    }
}

@Composable
private fun EmptyHint(state: UiState) {
    if (state.visible.isNotEmpty() || state.lastRefreshMs == null) return
    val f = state.filters
    val msg = when {
        f.watchedOnly -> "لا تبث أي طائرة من طرازات MQ-9 أو MQ-1 أو RQ-4 بيانات عامة ضمن هذا النطاق حالياً. عدم ظهورها لا يعني عدم وجودها."
        !f.civil && !f.other -> "كل الفئات مخفية — فعّل فلتراً واحداً على الأقل."
        else -> "لا توجد طائرات تبث بيانات عامة في هذا النطاق الآن. عدم ظهور طائرة لا يعني عدم وجودها."
    }
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(Radar.Panel)
            .border(1.dp, Radar.Line, RoundedCornerShape(12.dp)).padding(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(Icons.Filled.Info, null, tint = Radar.Sky, modifier = Modifier.size(20.dp))
        Spacer(Modifier.width(8.dp))
        Text(msg, color = Radar.Text, fontSize = 13.sp)
    }
}

@Composable
private fun Legend() {
    Row(
        Modifier.clip(RoundedCornerShape(50)).background(Radar.Panel).border(1.dp, Radar.Line, RoundedCornerShape(50))
            .padding(horizontal = 12.dp, vertical = 6.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically,
    ) {
        LegendDot(Radar.Green, "مدنية")
        LegendDot(Radar.Amber, "فئات أخرى")
        LegendDot(Radar.Sky, "غير مصنّفة")
        LegendDot(Radar.Red, "MQ-9/MQ-1/RQ-4")
    }
}

@Composable
private fun LegendDot(c: Color, label: String) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(8.dp).clip(CircleShape).background(c))
        Spacer(Modifier.width(5.dp))
        Text(label, color = Radar.Muted, fontSize = 11.sp)
    }
}

@Composable
private fun DetailPanel(a: Aircraft, onClose: () -> Unit) {
    val accent = Color(colorFor(a))
    Column(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(18.dp)).background(Radar.Panel)
            .border(1.dp, accent.copy(alpha = .7f), RoundedCornerShape(18.dp)).padding(14.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text(a.displayName, color = Radar.Text, fontWeight = FontWeight.Bold, fontSize = 20.sp)
                Text(a.watched?.label ?: a.description ?: a.typeCode ?: "النوع غير منشور لدى المصدر", color = accent, fontSize = 14.sp)
            }
            IconButton(onClick = onClose) { Icon(Icons.Filled.Close, "إغلاق", tint = Radar.Muted) }
        }
        Spacer(Modifier.size(8.dp))
        InfoRow("الطراز (رمز ICAO)", a.typeCode ?: NOT_AVAILABLE)
        InfoRow("التسجيل", a.registration ?: NOT_AVAILABLE)
        InfoRow("الارتفاع", altitudeText(a.altitudeFt, a.onGround))
        InfoRow("السرعة الأرضية", speedText(a.speedKt))
        InfoRow("اتجاه الحركة", trackText(a.trackDeg))
        InfoRow("آخر تحديث للموقع", "${agoText(a.positionTimeMs)} (${clockText(a.positionTimeMs)})")
        InfoRow("الفئة", categoryText(a.category))
        a.country?.let { InfoRow("بلد التسجيل", it) }
        InfoRow("رمز ICAO 24-bit", a.hex.uppercase())
        InfoRow("مصدر البيانات", a.source.label)
    }
}

@Composable
private fun InfoRow(label: String, value: String) {
    Row(Modifier.fillMaxWidth().padding(vertical = 3.dp)) {
        Text(label, color = Radar.Muted, fontSize = 13.sp, modifier = Modifier.width(130.dp))
        Text(value, color = Radar.Text, fontSize = 13.sp, modifier = Modifier.weight(1f))
    }
}

@Composable
private fun DisclaimerStrip(onOpenSources: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(Color(0xF0221A0C))
            .border(1.dp, Radar.Amber.copy(alpha = .5f), RoundedCornerShape(12.dp))
            .clickable(onClick = onOpenSources).padding(horizontal = 10.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(Icons.Filled.Public, null, tint = Radar.Amber, modifier = Modifier.size(18.dp))
        Spacer(Modifier.width(8.dp))
        Text(DISCLAIMER, color = Radar.Text, fontSize = 11.5.sp, lineHeight = 16.sp)
    }
}
