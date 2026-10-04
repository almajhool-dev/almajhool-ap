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
    private var lastOut: VideoFrame? = null
    private var row = ByteArray(0)

    /** gamma<1 يفتّح، contrast حول 128، sat تشبع الألوان، u/v إزاحة لونية */
    fun configure(name: String) {
        var gamma = 1.0; var contrast = 1.0; var bright = 0.0; var sat = 1.0; var uS = 0.0; var vS = 0.0
        var fixedU = -1; var fixedV = -1
        when (name) {
            "beauty" -> { gamma = 0.82; contrast = 0.9; bright = 6.0; sat = 1.05; uS = -3.0; vS = 5.0 }
            "warm" -> { uS = -12.0; vS = 12.0; sat = 1.1 }
            "cool" -> { uS = 12.0; vS = -9.0 }
            "bw" -> { fixedU = 128; fixedV = 128; contrast = 1.15 }
            "sepia" -> { fixedU = 112; fixedV = 146; contrast = 1.05 }
            "bright" -> { gamma = 0.75; contrast = 1.08; bright = 4.0; sat = 1.1 }
            "cinema" -> { contrast = 1.25; sat = 0.7; uS = 6.0; vS = -2.0; bright = -6.0 }
            "pink" -> { uS = 4.0; vS = 14.0; gamma = 0.9; sat = 1.1 }
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
            plane(src.dataY, src.strideY, out.dataY, out.strideY, w, h, yLut)
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
