package com.skymonitor.iraq.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.skymonitor.iraq.MainViewModel
import com.skymonitor.iraq.SourceStatus
import com.skymonitor.iraq.UiState
import com.skymonitor.iraq.data.DataSource

@Composable
fun SourcesScreen(state: UiState, onBack: () -> Unit) {
    Column(Modifier.fillMaxSize().background(Radar.Bg).statusBarsPadding().navigationBarsPadding()) {
        Row(Modifier.fillMaxWidth().padding(8.dp), verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowForward, "رجوع", tint = Radar.Text) }
            Text("مصدر البيانات", color = Radar.Text, fontSize = 20.sp, fontWeight = FontWeight.Bold)
        }
        Column(
            Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp, vertical = 4.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Card {
                Row(verticalAlignment = Alignment.Top) {
                    Icon(Icons.Filled.Warning, null, tint = Radar.Amber, modifier = Modifier.size(22.dp))
                    Spacer(Modifier.width(10.dp))
                    Text(DISCLAIMER, color = Radar.Text, fontSize = 14.sp, lineHeight = 21.sp)
                }
            }

            Text("حالة المصادر", color = Radar.Green, fontWeight = FontWeight.Bold)
            Text(
                "آخر تحديث عام: ${clockText(state.lastRefreshMs)} (${agoText(state.lastRefreshMs)}) · يتم التحديث تلقائياً كل ${MainViewModel.REFRESH_MS / 1000} ثانية.",
                color = Radar.Muted, fontSize = 13.sp,
            )
            state.statuses.forEach { SourceCard(it) }

            Text("كيف يعمل التطبيق", color = Radar.Green, fontWeight = FontWeight.Bold)
            Card {
                Bullet("يعرض التطبيق فقط الطائرات التي تبث إشارات ADS-B أو يُحدَّد موقعها بـ MLAT وتلتقطها شبكات هواة تطوعية، ثم تُنشر علناً عبر واجهات برمجية مجانية.")
                Bullet("كثير من الطائرات العسكرية لا تبث إشاراتها، أو تُطفئها، أو تُحجب بياناتها. لذلك عدم ظهور طائرة على الخريطة لا يعني عدم وجودها.")
                Bullet("لا يستطيع التطبيق كشف الطائرات الشبحية أو أي طائرة لا تبث بيانات عامة، ولا يعترض أي اتصالات، ولا يصل إلى أي بيانات عسكرية غير منشورة.")
                Bullet("الفئة «مصنّفة علناً كعسكرية/حكومية» مأخوذة كما هي من قاعدة البيانات العامة للمصدر، والتطبيق لا يستنتجها بنفسه.")
                Bullet("ظهور طرازات MQ-9 أو MQ-1 أو RQ-4 نادر ومرهون بما ينشره المصدر؛ يُطابَق الطراز عبر رمز ICAO المنشور (Q9 · Q1 · Q4) أو وصف الطراز.")
                Bullet("تغطية الشبكات التطوعية فوق العراق محدودة، لذا قد تكون بعض المناطق فارغة حتى مع وجود حركة جوية.")
            }

            Text("الخريطة", color = Radar.Green, fontWeight = FontWeight.Bold)
            Card {
                Text("الخريطة: صور الأقمار الصناعية من Esri World Imagery (Maxar، Earthstar Geographics)، والطرق والمباني ثلاثية الأبعاد من OpenFreeMap و OpenMapTiles ببيانات © OpenStreetMap، والتضاريس من AWS Terrain Tiles. أسماء الدول والمحافظات والمدن معروضة بالعربية.", color = Radar.Text, fontSize = 13.sp)
            }
            Text("تطوير: $DEVELOPER", color = Radar.Muted, fontSize = 13.sp, modifier = Modifier.fillMaxWidth().padding(top = 8.dp))
            Spacer(Modifier.size(24.dp))
        }
    }
}

@Composable
private fun Card(content: @Composable () -> Unit) {
    Column(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(Radar.PanelSolid)
            .border(1.dp, Radar.Line, RoundedCornerShape(16.dp)).padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) { content() }
}

@Composable
private fun Bullet(text: String) {
    Row {
        Box(Modifier.padding(top = 8.dp).size(6.dp).clip(CircleShape).background(Radar.Green))
        Spacer(Modifier.width(10.dp))
        Text(text, color = Radar.Text, fontSize = 13.5.sp, lineHeight = 20.sp)
    }
}

@Composable
private fun SourceCard(s: SourceStatus) {
    val uri = LocalUriHandler.current
    val ok = s.error == null && s.lastSuccessMs != null
    val dot = when {
        s.lastAttemptMs == null && s.lastSuccessMs == null -> Radar.Muted
        ok -> Radar.Green
        else -> Radar.Red
    }
    Card {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(10.dp).clip(CircleShape).background(dot))
            Spacer(Modifier.width(8.dp))
            Text(s.source.label, color = Radar.Text, fontWeight = FontWeight.Bold, fontSize = 16.sp, modifier = Modifier.weight(1f))
        }
        Line("الواجهة (API)", when (s.source) {
            DataSource.ADSB_FI -> "opendata.adsb.fi" + s.endpoints.substringBefore(" ·")
            DataSource.ADSB_LOL -> "api.adsb.lol" + s.endpoints.substringBefore(" ·")
            DataSource.OPENSKY -> "opensky-network.org" + s.endpoints
        })
        Line("شروط الاستخدام", when (s.source) {
            DataSource.ADSB_FI -> "مجاني للاستخدام غير التجاري مع ذكر المصدر · حد أقصى طلب واحد في الثانية"
            DataSource.ADSB_LOL -> "بيانات مفتوحة برخصة ODbL · مجانية بدون مفتاح مع ذكر المصدر"
            DataSource.OPENSKY -> "مجاني للاستخدام غير التجاري/البحثي مع ذكر المصدر · حصة يومية محدودة للمستخدم المجهول (يُستعلم كل 5 دقائق)"
        })
        Line("آخر تحديث ناجح", if (s.lastSuccessMs != null) "${clockText(s.lastSuccessMs)} (${agoText(s.lastSuccessMs)})" else "لم ينجح بعد")
        Line("تأخر البيانات", s.medianDelaySec?.let { "متوسط عمر آخر موقع ≈ $it ثانية" + if (s.source == DataSource.OPENSKY) " (دقة 10 ثوانٍ للمستخدم المجهول)" else "" } ?: "—")
        Line("عدد السجلات في آخر طلب", s.count.toString())
        s.note?.let { Line("ملاحظة", it) }
        s.error?.let { Text("⚠ $it", color = Radar.Red, fontSize = 13.sp) }
        androidx.compose.material3.TextButton(onClick = { runCatching { uri.openUri(s.source.site) } }) {
            Text("فتح موقع المصدر ↗", color = Radar.Sky, fontSize = 13.sp, textDecoration = TextDecoration.Underline)
        }
    }
}

@Composable
private fun Line(label: String, value: String) {
    Row(Modifier.fillMaxWidth()) {
        Text(label, color = Radar.Muted, fontSize = 13.sp, modifier = Modifier.width(140.dp))
        Text(value, color = Color(0xFFDDEBE6), fontSize = 13.sp, modifier = Modifier.weight(1f))
    }
}
