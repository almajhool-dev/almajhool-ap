package com.almajhool.almajhool_app

import com.cloudwebrtc.webrtc.FlutterWebRTCPlugin
import com.cloudwebrtc.webrtc.video.LocalVideoTrack
import org.webrtc.JavaI420Buffer
import org.webrtc.VideoFrame
import java.nio.ByteBuffer
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow

/**
 * فلاتر البث المباشر: تعدّل كل إطار من الكاميرا قبل إرساله (يراها كل المشاهدين).
 * تعمل على مستوى YUV بجداول جاهزة (سريعة وخفيفة).
 */
object FilterManager {
    private val processors = HashMap<String, FilterProcessor>()

    @Synchronized
    fun set(trackId: String, name: String): Boolean {
        val track = FlutterWebRTCPlugin.sharedSingleton?.getLocalTrack(trackId) as? LocalVideoTrack ?: return false
        val p = processors.getOrPut(trackId) {
            FilterProcessor().also { track.addProcessor(it) }
        }
        p.configure(name)
        return true
    }
}

class FilterProcessor : LocalVideoTrack.ExternalVideoFrameProcessing {
    @Volatile private var active = false
    @Volatile private var yLut = ByteArray(256)
    @Volatile private var uLut = ByteArray(256)
    @Volatile private var vLut = ByteArray(256)
    @Volatile private var smooth = 0 // قوة تنعيم البشرة 0..100
    private var lastOut: VideoFrame? = null
    private var row = ByteArray(0)

    // مخازن تنعيم البشرة (تُعاد استخدامها لتقليل استهلاك الذاكرة)
    private var yBuf = ByteArray(0)
    private var uBuf = ByteArray(0)
    private var vBuf = ByteArray(0)
    private var small = IntArray(0)
    private var tmp = IntArray(0)

    /** gamma<1 يفتّح، contrast حول 128، sat تشبع الألوان، u/v إزاحة لونية */
    fun configure(name: String) {
        var gamma = 1.0; var contrast = 1.0; var bright = 0.0; var sat = 1.0; var uS = 0.0; var vS = 0.0
        var fixedU = -1; var fixedV = -1; var sm = 0
        when (name) {
            "beauty" -> { gamma = 0.85; contrast = 0.94; bright = 5.0; sat = 1.05; uS = -2.0; vS = 4.0; sm = 70 }
            "smooth" -> { gamma = 0.95; sm = 85 }
            "warm" -> { uS = -12.0; vS = 12.0; sat = 1.1 }
            "cool" -> { uS = 12.0; vS = -9.0 }
            "bw" -> { fixedU = 128; fixedV = 128; contrast = 1.15 }
            "sepia" -> { fixedU = 112; fixedV = 146; contrast = 1.05 }
            "bright" -> { gamma = 0.78; contrast = 1.06; bright = 4.0; sat = 1.1; sm = 40 }
            "cinema" -> { contrast = 1.25; sat = 0.7; uS = 6.0; vS = -2.0; bright = -6.0 }
            "pink" -> { uS = 4.0; vS = 12.0; gamma = 0.9; sat = 1.1; sm = 50 }
            "vivid" -> { sat = 1.45; contrast = 1.12 }
            "vintage" -> { contrast = 0.85; sat = 0.75; uS = -8.0; vS = 6.0; bright = 8.0 }
            else -> { active = false; return }
        }
        val y = ByteArray(256); val u = ByteArray(256); val v = ByteArray(256)
        for (i in 0 until 256) {
            var f = (i / 255.0).pow(gamma) * 255.0
            f = (f - 128.0) * contrast + 128.0 + bright
            y[i] = clamp(f).toByte()
            u[i] = (if (fixedU >= 0) fixedU else clamp((i - 128.0) * sat + 128.0 + uS)).toByte()
            v[i] = (if (fixedV >= 0) fixedV else clamp((i - 128.0) * sat + 128.0 + vS)).toByte()
        }
        yLut = y; uLut = u; vLut = v
        smooth = sm
        active = true
    }

    private fun clamp(d: Double): Int = max(0, min(255, d.toInt()))

    override fun onFrame(frame: VideoFrame): VideoFrame {
        // إطار الناتج السابق صار عند المستقبل، نحرّره الآن
        lastOut?.release()
        lastOut = null
        if (!active) return frame
        return try {
            val src = frame.buffer.toI420() ?: return frame
            val w = src.width
            val h = src.height
            val out = JavaI420Buffer.allocate(w, h)
            val cw = (w + 1) / 2
            val ch = (h + 1) / 2
            if (smooth > 0) {
                skinSmooth(src, out, w, h, cw, ch)
            } else {
                plane(src.dataY, src.strideY, out.dataY, out.strideY, w, h, yLut)
            }
            plane(src.dataU, src.strideU, out.dataU, out.strideU, cw, ch, uLut)
            plane(src.dataV, src.strideV, out.dataV, out.strideV, cw, ch, vLut)
            src.release()
            val f = VideoFrame(out, frame.rotation, frame.timestampNs)
            lastOut = f
            f
        } catch (e: Throwable) {
            frame
        }
    }

    private fun readPlane(src: ByteBuffer, stride: Int, w: Int, h: Int, dst: ByteArray) {
        val s = src.duplicate()
        for (r in 0 until h) {
            s.position(r * stride)
            s.get(dst, r * w, w)
        }
    }

    /**
     * تنعيم البشرة فقط: نكتشف لون البشرة من مكوّنات اللون (Cb/Cr)،
     * ونمزج الإضاءة مع نسخة ناعمة مع الحفاظ على الحواف (العيون والشعر تبقى حادة).
     */
    private fun skinSmooth(src: VideoFrame.I420Buffer, out: JavaI420Buffer, w: Int, h: Int, cw: Int, ch: Int) {
        if (yBuf.size < w * h) yBuf = ByteArray(w * h)
        if (uBuf.size < cw * ch) { uBuf = ByteArray(cw * ch); vBuf = ByteArray(cw * ch) }
        readPlane(src.dataY, src.strideY, w, h, yBuf)
        readPlane(src.dataU, src.strideU, cw, ch, uBuf)
        readPlane(src.dataV, src.strideV, cw, ch, vBuf)

        // نسخة مصغّرة ×4 ثم تنعيم (سريع جدًا)
        val sw = max(1, w / 4)
        val sh = max(1, h / 4)
        if (small.size < sw * sh) { small = IntArray(sw * sh); tmp = IntArray(sw * sh) }
        for (sy in 0 until sh) {
            for (sx in 0 until sw) {
                var sum = 0
                val by = sy * 4
                val bx = sx * 4
                for (dy in 0 until 4) {
                    val rowOff = min(by + dy, h - 1) * w
                    for (dx in 0 until 4) sum += yBuf[rowOff + min(bx + dx, w - 1)].toInt() and 0xFF
                }
                small[sy * sw + sx] = sum shr 4
            }
        }
        boxBlur(small, tmp, sw, sh, 2)

        val strength = smooth
        val lut = yLut
        val d = out.dataY.duplicate()
        if (row.size < w) row = ByteArray(w)
        for (yy in 0 until h) {
            val cRow = (yy shr 1) * cw
            val sRow = min(yy shr 2, sh - 1) * sw
            val yRow = yy * w
            for (xx in 0 until w) {
                val y0 = yBuf[yRow + xx].toInt() and 0xFF
                val ci = cRow + (xx shr 1)
                val cb = uBuf[ci].toInt() and 0xFF
                val cr = vBuf[ci].toInt() and 0xFF
                var yv = y0
                if (cb in 77..135 && cr in 133..180) {
                    val b = small[sRow + min(xx shr 2, sw - 1)]
                    val diff = b - y0
                    // الحفاظ على الحواف: لا ننعّم الفروق الكبيرة (عيون، حواجب، شعر)
                    if (diff in -28..28) yv = y0 + diff * strength / 100
                }
                row[xx] = lut[yv]
            }
            d.position(yy * out.strideY)
            d.put(row, 0, w)
        }
    }

    private fun boxBlur(a: IntArray, t: IntArray, w: Int, h: Int, r: Int) {
        val div = 2 * r + 1
        for (y in 0 until h) {
            val off = y * w
            var acc = 0
            for (i in -r..r) acc += a[off + min(max(i, 0), w - 1)]
            for (x in 0 until w) {
                t[off + x] = acc / div
                acc += a[off + min(x + r + 1, w - 1)] - a[off + max(x - r, 0)]
            }
        }
        for (x in 0 until w) {
            var acc = 0
            for (i in -r..r) acc += t[min(max(i, 0), h - 1) * w + x]
            for (y in 0 until h) {
                a[y * w + x] = acc / div
                acc += t[min(y + r + 1, h - 1) * w + x] - t[max(y - r, 0) * w + x]
            }
        }
    }

    private fun plane(src: ByteBuffer, sStride: Int, dst: ByteBuffer, dStride: Int, w: Int, h: Int, lut: ByteArray) {
        if (row.size < w) row = ByteArray(w)
        val s = src.duplicate()
        val d = dst.duplicate()
        for (r in 0 until h) {
            s.position(r * sStride)
            s.get(row, 0, w)
            for (i in 0 until w) row[i] = lut[row[i].toInt() and 0xFF]
            d.position(r * dStride)
            d.put(row, 0, w)
        }
    }
}
