package com.skymonitor.iraq.map

import android.content.Context
import android.webkit.WebResourceResponse
import java.io.ByteArrayInputStream
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import java.util.concurrent.atomic.AtomicInteger

/**
 * Permanent on-device store for map tiles, terrain and fonts, so places you have seen (or downloaded)
 * open instantly and keep working without internet. Size is chosen by the user; "unlimited" keeps
 * filling until the phone has less than [KEEP_FREE_BYTES] free.
 */
class TileCache private constructor(context: Context) {
    private val dir = File(context.filesDir, "map-cache").apply { mkdirs() }
    private val prefs = context.getSharedPreferences("map-cache", Context.MODE_PRIVATE)
    private val writes = AtomicInteger(0)

    /** Limit in bytes; 0 = unlimited (only free-space guard). */
    var limitBytes: Long
        get() = prefs.getLong("limit", 0L)
        set(v) { prefs.edit().putLong("limit", v).apply(); trimAsync() }

    fun usedBytes(): Long = dir.walkTopDown().filter { it.isFile }.sumOf { it.length() }
    fun freeBytes(): Long = dir.usableSpace

    fun clear() { dir.listFiles()?.forEach { it.deleteRecursively() } }

    private fun key(url: String): File {
        val h = MessageDigest.getInstance("SHA-1").digest(url.toByteArray()).joinToString("") { "%02x".format(it) }
        return File(File(dir, h.substring(0, 2)), h.substring(2))
    }

    fun has(url: String) = key(url).exists()

    /** Cached bytes, or null. Touching the file keeps recently-used tiles from being evicted first. */
    fun get(url: String): ByteArray? {
        val f = key(url)
        if (!f.exists()) return null
        f.setLastModified(System.currentTimeMillis())
        return runCatching { f.readBytes() }.getOrNull()
    }

    fun put(url: String, bytes: ByteArray) {
        val f = key(url)
        f.parentFile?.mkdirs()
        val tmp = File(f.parentFile, f.name + ".tmp")
        runCatching { tmp.writeBytes(bytes); tmp.renameTo(f) }
        if (writes.incrementAndGet() % 300 == 0) trimAsync()
    }

    /** Downloads [url] (no caching decisions). Returns status and body. */
    fun download(url: String): Pair<Int, ByteArray?> {
        val conn = (URL(url).openConnection() as HttpURLConnection).apply {
            connectTimeout = 10_000; readTimeout = 20_000
            setRequestProperty("User-Agent", "SkyMonitorIraq/3.0 (Android)")
        }
        return try {
            val code = conn.responseCode
            if (code in 200..299) code to conn.inputStream.use { it.readBytes() } else code to null
        } finally { conn.disconnect() }
    }

    /** Fetches through the cache: [networkFirst] for small index files that can change, cache-first for tiles. */
    fun fetch(url: String, networkFirst: Boolean = false): ByteArray? {
        if (!networkFirst) get(url)?.let { return it }
        val net = runCatching { download(url) }.getOrNull()
        net?.second?.let { put(url, it); return it }
        return if (networkFirst) get(url) else null
    }

    private fun trimAsync() = Thread { trim() }.start()

    @Synchronized
    fun trim() {
        val files = dir.walkTopDown().filter { it.isFile }.toMutableList()
        var used = files.sumOf { it.length() }
        val limit = limitBytes
        fun over() = (limit > 0 && used > limit) || dir.usableSpace < KEEP_FREE_BYTES
        if (!over()) return
        files.sortBy { it.lastModified() }
        for (f in files) {
            if (!over()) break
            used -= f.length(); f.delete()
        }
    }

    /** WebView response for a map resource, served from the cache when possible. */
    fun respond(url: String): WebResourceResponse {
        val networkFirst = url.endsWith("/planet") || url.endsWith(".json")
        val bytes = fetch(url, networkFirst)
        val mime = when {
            url.endsWith(".pbf") -> "application/x-protobuf"
            url.endsWith(".png") || url.contains("/terrarium/") -> "image/png"
            url.contains("arcgisonline") -> "image/jpeg"
            else -> "application/json"
        }
        val headers = mapOf("Access-Control-Allow-Origin" to "*", "Cache-Control" to "max-age=86400")
        return if (bytes != null) WebResourceResponse(mime, null, 200, "OK", headers, ByteArrayInputStream(bytes))
        else WebResourceResponse(mime, null, 404, "Not cached", headers, ByteArrayInputStream(ByteArray(0)))
    }

    companion object {
        const val KEEP_FREE_BYTES = 800L * 1024 * 1024
        val HOSTS = setOf("tiles.openfreemap.org", "server.arcgisonline.com", "s3.amazonaws.com")

        @Volatile private var instance: TileCache? = null
        fun get(context: Context): TileCache = instance ?: synchronized(this) {
            instance ?: TileCache(context.applicationContext).also { instance = it }
        }
    }
}
