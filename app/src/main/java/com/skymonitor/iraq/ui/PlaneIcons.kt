package com.skymonitor.iraq.ui

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RadialGradient
import android.graphics.RectF
import android.graphics.Shader

/**
 * Top-down aircraft glyphs drawn in code (nose pointing north), shaded to look like real airframes.
 * A soft coloured halo under each glyph shows the category.
 */
object PlaneIcons {
    const val CIVIL = "ic-civil"
    const val OTHER = "ic-other"
    const val UNCLASSIFIED = "ic-unclassified"
    const val WATCHED = "ic-watched"
    const val SELECTED = "ic-selected"

    const val COLOR_CIVIL = 0xFF35F0A2.toInt()
    const val COLOR_OTHER = 0xFFFFB547.toInt()
    const val COLOR_UNCLASSIFIED = 0xFF7FB8D6.toInt()
    const val COLOR_WATCHED = 0xFFFF4D5E.toInt()
    const val COLOR_SELECTED = 0xFFFFFFFF.toInt()

    fun all(density: Float): Map<String, Bitmap> = mapOf(
        CIVIL to airliner(density, COLOR_CIVIL),
        OTHER to airliner(density, COLOR_OTHER),
        UNCLASSIFIED to airliner(density, COLOR_UNCLASSIFIED),
        WATCHED to drone(density, COLOR_WATCHED),
        SELECTED to airliner(density, COLOR_SELECTED, selected = true),
    )

    private fun canvas(density: Float): Triple<Bitmap, Canvas, Float> {
        val size = (56 * density).toInt()
        val bmp = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val c = Canvas(bmp)
        val s = size / 100f
        c.scale(s, s)
        return Triple(bmp, c, s)
    }

    private fun halo(c: Canvas, color: Int, selected: Boolean) {
        val p = Paint(Paint.ANTI_ALIAS_FLAG)
        p.shader = RadialGradient(50f, 50f, 46f,
            intArrayOf(Color.argb(if (selected) 140 else 95, Color.red(color), Color.green(color), Color.blue(color)), Color.TRANSPARENT),
            floatArrayOf(0.25f, 1f), Shader.TileMode.CLAMP)
        c.drawCircle(50f, 50f, 46f, p)
        if (selected) {
            val ring = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE; strokeWidth = 2.4f; this.color = color }
            c.drawCircle(50f, 50f, 44f, ring)
        }
    }

    private fun bodyPaint(top: Float, bottom: Float) = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        shader = LinearGradient(36f, top, 64f, bottom, intArrayOf(0xFFFFFFFF.toInt(), 0xFFDDE4E8.toInt(), 0xFFAEB9BF.toInt()), floatArrayOf(0f, 0.5f, 1f), Shader.TileMode.CLAMP)
    }
    private val outline = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE; strokeWidth = 1.1f; color = 0xCC1A2328.toInt() }

    /** Twin-engine airliner, swept wings. */
    private fun airliner(density: Float, color: Int, selected: Boolean = false): Bitmap {
        val (bmp, c) = canvas(density)
        halo(c, color, selected)

        val wings = Path().apply {
            moveTo(46f, 40f); lineTo(6f, 60f); lineTo(6f, 65f); lineTo(46f, 55f)
            lineTo(54f, 55f); lineTo(94f, 65f); lineTo(94f, 60f); lineTo(54f, 40f); close()
        }
        val wingPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            shader = LinearGradient(0f, 40f, 0f, 65f, 0xFFF2F5F7.toInt(), 0xFFAFBAC0.toInt(), Shader.TileMode.CLAMP)
        }
        c.drawPath(wings, wingPaint); c.drawPath(wings, outline)

        val tail = Path().apply {
            moveTo(47f, 80f); lineTo(32f, 89f); lineTo(32f, 92f); lineTo(47f, 88f)
            lineTo(53f, 88f); lineTo(68f, 92f); lineTo(68f, 89f); lineTo(53f, 80f); close()
        }
        c.drawPath(tail, wingPaint); c.drawPath(tail, outline)

        // Engines under the wings.
        val eng = Paint(Paint.ANTI_ALIAS_FLAG).apply { this.color = 0xFF8D99A0.toInt() }
        for (x in floatArrayOf(28f, 66f)) {
            val r = RectF(x, 46f, x + 6f, 58f)
            c.drawRoundRect(r, 3f, 3f, eng); c.drawRoundRect(r, 3f, 3f, outline)
        }

        // Fuselage with rounded nose and tapered tail.
        val body = Path().apply {
            moveTo(50f, 4f)
            cubicTo(55f, 6f, 56f, 14f, 56f, 20f)
            lineTo(56f, 78f); cubicTo(56f, 86f, 53f, 94f, 50f, 97f)
            cubicTo(47f, 94f, 44f, 86f, 44f, 78f)
            lineTo(44f, 20f); cubicTo(44f, 14f, 45f, 6f, 50f, 4f); close()
        }
        c.drawPath(body, bodyPaint(4f, 97f)); c.drawPath(body, outline)

        // Cockpit windows and a thin accent stripe in the category colour.
        val glass = Paint(Paint.ANTI_ALIAS_FLAG).apply { this.color = 0xFF22313A.toInt() }
        c.drawPath(Path().apply { moveTo(47f, 11f); quadTo(50f, 8f, 53f, 11f); lineTo(52.5f, 14f); quadTo(50f, 12.5f, 47.5f, 14f); close() }, glass)
        val stripe = Paint(Paint.ANTI_ALIAS_FLAG).apply { this.color = color; alpha = 230 }
        c.drawRect(49.2f, 20f, 50.8f, 76f, stripe)
        return bmp
    }

    /** Long-wing remotely piloted aircraft (MQ-9 / MQ-1 / RQ-4 class silhouette). */
    private fun drone(density: Float, color: Int): Bitmap {
        val (bmp, c) = canvas(density)
        halo(c, color, false)
        val wingPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            shader = LinearGradient(0f, 38f, 0f, 48f, 0xFFE9EDEF.toInt(), 0xFF9AA6AC.toInt(), Shader.TileMode.CLAMP)
        }
        val wings = Path().apply {
            moveTo(47f, 38f); lineTo(3f, 42f); lineTo(3f, 46f); lineTo(47f, 46f)
            lineTo(53f, 46f); lineTo(97f, 46f); lineTo(97f, 42f); lineTo(53f, 38f); close()
        }
        c.drawPath(wings, wingPaint); c.drawPath(wings, outline)
        // V-tail.
        val tail = Path().apply {
            moveTo(48f, 80f); lineTo(34f, 92f); lineTo(36f, 94f); lineTo(49f, 86f)
            lineTo(51f, 86f); lineTo(64f, 94f); lineTo(66f, 92f); lineTo(52f, 80f); close()
        }
        c.drawPath(tail, wingPaint); c.drawPath(tail, outline)
        // Bulbous sensor nose and slim body.
        val body = Path().apply {
            moveTo(50f, 8f)
            cubicTo(56f, 9f, 57f, 18f, 55.5f, 26f)
            lineTo(54f, 84f); lineTo(46f, 84f); lineTo(44.5f, 26f)
            cubicTo(43f, 18f, 44f, 9f, 50f, 8f); close()
        }
        c.drawPath(body, bodyPaint(8f, 84f)); c.drawPath(body, outline)
        // Pusher propeller.
        val prop = Paint(Paint.ANTI_ALIAS_FLAG).apply { this.color = 0xFF55626A.toInt(); strokeWidth = 2f }
        c.drawLine(42f, 88f, 58f, 88f, prop)
        val dot = Paint(Paint.ANTI_ALIAS_FLAG).apply { this.color = color }
        c.drawCircle(50f, 16f, 2.6f, dot)
        return bmp
    }
}
