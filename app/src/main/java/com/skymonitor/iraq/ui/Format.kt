package com.skymonitor.iraq.ui

import com.skymonitor.iraq.data.Category
import java.text.NumberFormat
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.math.roundToInt

const val NOT_AVAILABLE = "غير متاح من المصدر"

private val num = NumberFormat.getIntegerInstance(Locale.US)

fun altitudeText(ft: Int?, onGround: Boolean): String = when {
    onGround -> "على الأرض"
    ft == null -> NOT_AVAILABLE
    else -> "${num.format(ft)} قدم (${num.format((ft * 0.3048).roundToInt())} م)"
}

fun speedText(kt: Double?): String =
    if (kt == null) NOT_AVAILABLE else "${kt.roundToInt()} عقدة (${(kt * 1.852).roundToInt()} كم/س)"

fun trackText(deg: Double?): String {
    if (deg == null) return NOT_AVAILABLE
    val names = listOf("شمال", "شمال شرق", "شرق", "جنوب شرق", "جنوب", "جنوب غرب", "غرب", "شمال غرب")
    val i = (((deg % 360) + 360) % 360 / 45.0).roundToInt() % 8
    return "\u200E${deg.roundToInt()}°\u200F (${names[i]})"
}

fun agoText(ms: Long?, now: Long = System.currentTimeMillis()): String {
    if (ms == null) return "لم يتم بعد"
    val s = ((now - ms) / 1000).coerceAtLeast(0)
    return when {
        s < 5 -> "الآن"
        s < 60 -> "قبل $s ثانية"
        s < 3600 -> "قبل ${s / 60} دقيقة"
        else -> "قبل ${s / 3600} ساعة"
    }
}

fun clockText(ms: Long?): String =
    if (ms == null) "—" else SimpleDateFormat("HH:mm:ss", Locale.US).format(Date(ms))

fun categoryText(c: Category): String = when (c) {
    Category.CIVIL -> "مدنية"
    Category.OTHER -> "مصنّفة علناً كعسكرية/حكومية"
    Category.UNCLASSIFIED -> "غير مصنّفة لدى المصدر"
}
