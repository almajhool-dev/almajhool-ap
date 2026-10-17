"""
يضبط ملفات Android المولّدة من `flutter create`:
- اسم التطبيق «المبرمج المجهول»
- الصلاحيات المطلوبة فقط
- minSdk 23 + desugaring (مطلوب لإشعارات الجهاز)
- توقيع Release آمن من android/key.properties (إن وُجد)، وإلا توقيع debug
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP = os.path.join(ROOT, "android", "app")
MANIFEST = os.path.join(APP, "src", "main", "AndroidManifest.xml")


def read(p):
    with open(p, encoding="utf-8") as f:
        return f.read()


def write(p, s):
    with open(p, "w", encoding="utf-8") as f:
        f.write(s)


def patch_manifest():
    s = read(MANIFEST)
    s = re.sub(r'android:label="[^"]*"', 'android:label="المبرمج المجهول"', s, count=1)
    # حماية: منع نسخ بيانات الدخول بالنسخ الاحتياطي (حتى ما أحد ينقل جلسة المستخدم لجهاز ثاني)
    if 'android:allowBackup' not in s:
        s = s.replace('android:label="المبرمج المجهول"',
                      'android:label="المبرمج المجهول" android:allowBackup="false" android:fullBackupContent="false"'
                      ' tools:replace="android:allowBackup"', 1)
    perms = [
        "android.permission.INTERNET",
        "android.permission.ACCESS_NETWORK_STATE",
        "android.permission.RECORD_AUDIO",
        "android.permission.POST_NOTIFICATIONS",
        "android.permission.CAMERA",
        "android.permission.MODIFY_AUDIO_SETTINGS",
        "android.permission.BLUETOOTH_CONNECT",
        "android.permission.WAKE_LOCK",
        "android.permission.VIBRATE",
        "android.permission.FOREGROUND_SERVICE",
        "android.permission.FOREGROUND_SERVICE_REMOTE_MESSAGING",
        "android.permission.RECEIVE_BOOT_COMPLETED",
        "android.permission.USE_FULL_SCREEN_INTENT",
        "android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS",
        "android.permission.REQUEST_INSTALL_PACKAGES",
    ]
    block = ""
    for p in perms:
        if p not in s:
            block += f'    <uses-permission android:name="{p}"/>\n'
    if "android.hardware.camera" not in s:
        block += '    <uses-feature android:name="android.hardware.camera" android:required="false"/>\n'
    if block:
        s = s.replace("<application", block + "    <application", 1)
    # خدمة الخلفية لاستقبال المكالمات والرسائل والتطبيق مغلق
    if 'xmlns:tools=' not in s:
        s = s.replace('<manifest ', '<manifest xmlns:tools="http://schemas.android.com/tools" ', 1)
    if "flutter_background_service.BackgroundService" not in s:
        s = s.replace(
            "</application>",
            '    <service\n'
            '            android:name="id.flutter.flutter_background_service.BackgroundService"\n'
            '            android:foregroundServiceType="remoteMessaging"\n'
            '            android:exported="false"\n'
            '            tools:replace="android:exported,android:foregroundServiceType"/>\n'
            '    </application>',
            1,
        )
    # محرك الرسم الحديث (Impeller) هو الافتراضي: تمرير أنعم بدون تقطيع
    # أزرار الإشعارات (رد/رفض) تعمل والتطبيق مغلق
    if "ActionBroadcastReceiver" not in s:
        s = s.replace(
            "</application>",
            '    <receiver android:exported="false"\n'
            '            android:name="com.dexterous.flutterlocalnotifications.ActionBroadcastReceiver"/>\n'
            '        <receiver android:exported="false"\n'
            '            android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver"/>\n'
            '    </application>',
            1,
        )
    # التحديث من داخل التطبيق (ota_update)
    if "OtaUpdateFileProvider" not in s:
        s = s.replace(
            "</application>",
            '    <provider\n'
            '            android:name="sk.fourq.otaupdate.OtaUpdateFileProvider"\n'
            '            android:authorities="${applicationId}.ota_update_provider"\n'
            '            android:exported="false"\n'
            '            android:grantUriPermissions="true">\n'
            '            <meta-data android:name="android.support.FILE_PROVIDER_PATHS" android:resource="@xml/filepaths"/>\n'
            '        </provider>\n'
            '        <receiver android:name="sk.fourq.otaupdate.InstallResultReceiver" android:exported="false">\n'
            '            <intent-filter><action android:name="${applicationId}.ACTION_INSTALL_COMPLETE"/></intent-filter>\n'
            '        </receiver>\n'
            '    </application>',
            1,
        )
    xml_dir = os.path.join(APP, "src", "main", "res", "xml")
    os.makedirs(xml_dir, exist_ok=True)
    write(os.path.join(xml_dir, "filepaths.xml"),
          '<?xml version="1.0" encoding="utf-8"?>\n'
          '<paths xmlns:android="http://schemas.android.com/apk/res/android">\n'
          '    <files-path name="internal_apk_storage" path="ota_update/"/>\n'
          '</paths>\n')
    # نغمات الرنين كموارد نظام (لإشعار المكالمة عبر Google)
    raw_dir = os.path.join(APP, "src", "main", "res", "raw")
    os.makedirs(raw_dir, exist_ok=True)
    snd = os.path.join(ROOT, "assets", "sounds")
    for f in os.listdir(snd):
        if f.startswith("ring_") and f.endswith(".wav"):
            with open(os.path.join(snd, f), "rb") as src, open(os.path.join(raw_dir, f), "wb") as dst:
                dst.write(src.read())
    write(os.path.join(raw_dir, "keep.xml"),
          '<?xml version="1.0" encoding="utf-8"?>\n'
          '<resources xmlns:tools="http://schemas.android.com/tools" tools:keep="@raw/*"/>\n')
    # روابط البث: almajhool://live/<id> تفتح التطبيق مباشرة على البث
    if 'android:scheme="almajhool"' not in s:
        s = s.replace(
            "</activity>",
            '    <intent-filter>\n'
            '                <action android:name="android.intent.action.VIEW"/>\n'
            '                <category android:name="android.intent.category.DEFAULT"/>\n'
            '                <category android:name="android.intent.category.BROWSABLE"/>\n'
            '                <data android:scheme="almajhool" android:host="live"/>\n'
            '            </intent-filter>\n'
            '        </activity>',
            1,
        )
    # حفظ تسجيلات البث في المعرض (أندرويد 9 وأقدم)
    if "WRITE_EXTERNAL_STORAGE" not in s:
        s = s.replace("<application",
                      '<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" android:maxSdkVersion="29"/>\n    <application', 1)
    # نافذة البث الصغيرة العائمة (Picture-in-Picture) مثل تيك توك
    if "supportsPictureInPicture" not in s:
        s = s.replace('android:name=".MainActivity"',
                      'android:name=".MainActivity"\n            android:supportsPictureInPicture="true"\n            android:resizeableActivity="true"', 1)
    # عرض شاشة المكالمة فوق قفل الشاشة
    if "showWhenLocked" not in s:
        s = s.replace('android:name=".MainActivity"',
                      'android:name=".MainActivity"\n            android:showWhenLocked="true"\n            android:turnScreenOn="true"', 1)
    # السماح بفتح الروابط (url_launcher) على Android 11+
    if "<queries>" in s and "android.intent.action.VIEW" not in s:
        s = s.replace(
            "<queries>",
            '<queries>\n        <intent>\n            <action android:name="android.intent.action.VIEW"/>\n'
            '            <data android:scheme="https"/>\n        </intent>',
            1,
        )
    write(MANIFEST, s)
    print("manifest patched")


def patch_kts(path):
    s = read(path)
    s = re.sub(r"minSdk\s*=\s*[^\n]+", "minSdk = 23", s, count=1)
    if "isCoreLibraryDesugaringEnabled" not in s:
        s = re.sub(r"compileOptions\s*\{", "compileOptions {\n        isCoreLibraryDesugaringEnabled = true", s, count=1)
    if "desugar_jdk_libs" not in s:
        s += '\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n}\n'
    if "firebase-messaging:" not in s:
        # للتشخيص من MainActivity (المكتبة موجودة وقت التشغيل عن طريق firebase_messaging)
        s += '\ndependencies {\n    compileOnly("com.google.firebase:firebase-messaging:25.1.3")\n}\n'
    if "webrtc-sdk" not in s:
        # لفلاتر البث: نحتاج واجهات WebRTC وقت الترجمة فقط (موجودة أصلًا مع flutter_webrtc)
        s += '\ndependencies {\n    compileOnly("io.github.webrtc-sdk:android:150.7871.01")\n}\n'
    if "keystoreProperties" not in s:
        header = (
            "import java.util.Properties\n"
            "import java.io.FileInputStream\n\n"
        )
        loader = (
            '\nval keystoreProperties = Properties()\n'
            'val keystorePropertiesFile = rootProject.file("key.properties")\n'
            'if (keystorePropertiesFile.exists()) {\n'
            '    keystoreProperties.load(FileInputStream(keystorePropertiesFile))\n'
            '}\n'
        )
        # الاستيرادات في أول الملف
        s = header + s
        # تحميل الخصائص قبل android {
        s = re.sub(r"\nandroid\s*\{", loader + "\nandroid {", s, count=1)
        signing = (
            "    signingConfigs {\n"
            '        create("release") {\n'
            "            if (keystorePropertiesFile.exists()) {\n"
            '                keyAlias = keystoreProperties["keyAlias"] as String\n'
            '                keyPassword = keystoreProperties["keyPassword"] as String\n'
            '                storeFile = file(keystoreProperties["storeFile"] as String)\n'
            '                storePassword = keystoreProperties["storePassword"] as String\n'
            "            }\n"
            "            enableV1Signing = true\n"
            "            enableV2Signing = true\n"
            "        }\n"
            "    }\n\n"
            "    buildTypes {"
        )
        s = s.replace("    buildTypes {", signing, 1)
        s = re.sub(
            r'signingConfig\s*=\s*signingConfigs\.getByName\("debug"\)',
            'signingConfig = if (keystorePropertiesFile.exists()) signingConfigs.getByName("release") '
            'else signingConfigs.getByName("debug")',
            s,
            count=1,
        )
    if "useLegacyPackaging" not in s:
        # تحديث أسرع: المكتبات مضغوطة داخل الـ APK (84 → ~35 ميگا) وبدون مكتبات x86 اللي ما تحتاجها الهواتف
        s = re.sub(
            r"\n    defaultConfig\s*\{",
            '\n    packaging {\n        jniLibs {\n            useLegacyPackaging = true\n        }\n    }\n\n'
            '    defaultConfig {\n        ndk {\n            abiFilters += listOf("armeabi-v7a", "arm64-v8a")\n        }',
            s,
            count=1,
        )
    write(path, s)
    print("build.gradle.kts patched")


def patch_groovy(path):
    s = read(path)
    s = re.sub(r"minSdk(Version)?\s*=?\s*flutter\.minSdkVersion", "minSdkVersion 23", s, count=1)
    if "coreLibraryDesugaringEnabled" not in s:
        s = re.sub(r"compileOptions\s*\{", "compileOptions {\n        coreLibraryDesugaringEnabled true", s, count=1)
    if "desugar_jdk_libs" not in s:
        s += "\ndependencies {\n    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'\n}\n"
    if "keystoreProperties" not in s:
        loader = (
            "\ndef keystoreProperties = new Properties()\n"
            "def keystorePropertiesFile = rootProject.file('key.properties')\n"
            "if (keystorePropertiesFile.exists()) {\n"
            "    keystoreProperties.load(new FileInputStream(keystorePropertiesFile))\n"
            "}\n"
        )
        s = re.sub(r"\nandroid\s*\{", loader + "\nandroid {", s, count=1)
        signing = (
            "    signingConfigs {\n"
            "        release {\n"
            "            if (keystorePropertiesFile.exists()) {\n"
            "                keyAlias keystoreProperties['keyAlias']\n"
            "                keyPassword keystoreProperties['keyPassword']\n"
            "                storeFile file(keystoreProperties['storeFile'])\n"
            "                storePassword keystoreProperties['storePassword']\n"
            "            }\n"
            "            v1SigningEnabled true\n"
            "            v2SigningEnabled true\n"
            "        }\n"
            "    }\n\n"
            "    buildTypes {"
        )
        s = s.replace("    buildTypes {", signing, 1)
        s = s.replace(
            "signingConfig = signingConfigs.debug",
            "signingConfig = keystorePropertiesFile.exists() ? signingConfigs.release : signingConfigs.debug",
            1,
        ).replace(
            "signingConfig signingConfigs.debug",
            "signingConfig keystorePropertiesFile.exists() ? signingConfigs.release : signingConfigs.debug",
            1,
        )
    if "useLegacyPackaging" not in s:
        s = re.sub(
            r"\n    defaultConfig\s*\{",
            "\n    packagingOptions {\n        jniLibs {\n            useLegacyPackaging true\n        }\n    }\n\n"
            "    defaultConfig {\n        ndk {\n            abiFilters 'armeabi-v7a', 'arm64-v8a'\n        }",
            s,
            count=1,
        )
    write(path, s)
    print("build.gradle patched")


def write_proguard():
    p = os.path.join(APP, "proguard-rules.pro")
    rules = ("-keep class org.webrtc.** { *; }\n-keep class com.cloudwebrtc.webrtc.** { *; }\n-dontwarn org.webrtc.**\n"
             "-keep class io.livekit.** { *; }\n-dontwarn io.livekit.**\n"
             "-keep class com.twilio.audioswitch.** { *; }\n-keep class com.almajhool.** { *; }\n")
    existing = read(p) if os.path.exists(p) else ""
    if "io.livekit" not in existing:
        write(p, existing + rules)
    print("proguard rules written")


MAIN_ACTIVITY = """package com.almajhool.almajhool_app

import android.content.pm.PackageManager
import android.content.pm.Signature
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.PrintWriter
import java.io.StringWriter
import java.security.MessageDigest

class MainActivity : FlutterActivity() {
    // ملف إعدادات Flutter إذا تضخّم (نسخ محادثات/رسائل قديمة) كان يعلّك التطبيق على شاشة الشعار.
    // هنا نشيل القوائم الكبيرة بس، ونخلي تسجيل الدخول والإعدادات مثل ما هي.
    private fun slimPrefs() {
        val dir = java.io.File(applicationInfo.dataDir, "shared_prefs")
        val f = java.io.File(dir, "FlutterSharedPreferences.xml")
        if (!f.exists() || f.length() < 1500000L) return
        val drop = ArrayList<String>()
        val tmp = java.io.File(dir, "FlutterSharedPreferences.slim")
        java.io.FileInputStream(f).use { ins ->
            val p = android.util.Xml.newPullParser()
            p.setInput(ins, "UTF-8")
            java.io.FileOutputStream(tmp).use { out ->
                val w = android.util.Xml.newSerializer()
                w.setOutput(out, "UTF-8")
                w.startDocument("UTF-8", true)
                w.startTag(null, "map")
                var ev = p.eventType
                while (ev != org.xmlpull.v1.XmlPullParser.END_DOCUMENT) {
                    if (ev == org.xmlpull.v1.XmlPullParser.START_TAG && p.depth == 2) {
                        val tag = p.name
                        val name = p.getAttributeValue(null, "name") ?: ""
                        val big = name.contains("::msgs_") || name.endsWith("::conversations") || name.endsWith("::feed")
                        if (tag == "string") {
                            val text = p.nextText()
                            if (big) drop.add(name) else {
                                w.startTag(null, "string"); w.attribute(null, "name", name); w.text(text); w.endTag(null, "string")
                            }
                        } else {
                            val v = p.getAttributeValue(null, "value")
                            w.startTag(null, tag); w.attribute(null, "name", name)
                            if (v != null) w.attribute(null, "value", v)
                            w.endTag(null, tag)
                        }
                    }
                    ev = p.next()
                }
                w.endTag(null, "map")
                w.endDocument()
            }
        }
        if (drop.isEmpty()) { tmp.delete(); return }
        java.io.File(dir, "FlutterSharedPreferences.xml.bak").delete()
        if (!tmp.renameTo(f)) { tmp.delete(); return }
        // إذا الإعدادات محمّلة أصلًا بالذاكرة (خدمة الخلفية شغالة) نشيلها من هناك هم
        try {
            val e = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE).edit()
            for (k in drop) e.remove(k)
            e.commit()
        } catch (t: Throwable) {}
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        try { slimPrefs() } catch (t: Throwable) {}
        // حفظ سبب أي انهيار حتى يُرسل للمطوّر عند الفتح التالي
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { t, e ->
            try {
                val sw = StringWriter()
                e.printStackTrace(PrintWriter(sw))
                getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE).edit()
                    .putString("flutter.last_crash", ("[" + t.name + "] " + sw.toString()).take(1800)).commit()
            } catch (_: Throwable) {}
            previous?.uncaughtException(t, e)
        }
        super.onCreate(savedInstanceState)
        // حماية: منع تصوير الشاشة وتسجيلها داخل التطبيق (تطلع سوداء)
        window.setFlags(android.view.WindowManager.LayoutParams.FLAG_SECURE,
            android.view.WindowManager.LayoutParams.FLAG_SECURE)
    }

    // ---- نافذة البث الصغيرة (PiP) ----
    private var pipChannel: MethodChannel? = null
    private var autoPip = false

    private fun pipParams(): android.app.PictureInPictureParams? {
        if (Build.VERSION.SDK_INT < 26) return null
        val b = android.app.PictureInPictureParams.Builder().setAspectRatio(android.util.Rational(9, 16))
        if (Build.VERSION.SDK_INT >= 31) b.setAutoEnterEnabled(autoPip)
        return b.build()
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (autoPip && Build.VERSION.SDK_INT >= 26 && Build.VERSION.SDK_INT < 31) {
            try {
                val p = pipParams()
                if (p != null) enterPictureInPictureMode(p)
            } catch (t: Throwable) {}
        }
    }

    override fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean, newConfig: android.content.res.Configuration) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        try {
            pipChannel?.invokeMethod("pip", isInPictureInPictureMode)
        } catch (t: Throwable) {}
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        pipChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "almajhool/pip")
        pipChannel?.setMethodCallHandler { call, result ->
            if (call.method == "setAuto") {
                val want = call.argument<Boolean>("on") ?: false
                autoPip = want && Build.VERSION.SDK_INT >= 26 &&
                    packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)
                try {
                    val p = pipParams()
                    if (p != null) setPictureInPictureParams(p)
                } catch (t: Throwable) {}
                result.success(autoPip)
            } else {
                result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "almajhool/filters")
            .setMethodCallHandler { call, result ->
                if (call.method == "set") {
                    val ok = FilterManager.set(call.argument<String>("track") ?: "", call.argument<String>("name") ?: "none")
                    result.success(ok)
                } else {
                    result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "almajhool/integrity")
            .setMethodCallHandler { call, result ->
                if (call.method == "sig") {
                    try {
                        result.success(signatures().map { sha256(it) })
                    } catch (e: Exception) {
                        result.success(listOf<String>())
                    }
                } else if (call.method == "installApk") {
                    // تثبيت ملف التحديث اللي نزّلناه بسرعة (تنزيل متوازي)
                    try {
                        val path = call.argument<String>("path") ?: ""
                        if (Build.VERSION.SDK_INT >= 26 && !packageManager.canRequestPackageInstalls()) {
                            startActivity(android.content.Intent(android.provider.Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                android.net.Uri.parse("package:" + packageName)))
                            result.success("need_permission")
                        } else {
                            val uri = androidx.core.content.FileProvider.getUriForFile(this,
                                packageName + ".ota_update_provider", java.io.File(path))
                            val i = android.content.Intent(android.content.Intent.ACTION_VIEW)
                            i.setDataAndType(uri, "application/vnd.android.package-archive")
                            i.addFlags(android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION or android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(i)
                            result.success("ok")
                        }
                    } catch (t: Throwable) {
                        result.success("error:" + t.javaClass.simpleName + ":" + (t.message ?: ""))
                    }
                } else if (call.method == "fcmDiag") {
                    // تشخيص إشعارات Google: السبب الحقيقي للرفض + نسخة خدمات Play، وإذا نجح يرجع الرمز
                    Thread {
                        val sb = StringBuilder()
                        try {
                            val gms = packageManager.getPackageInfo("com.google.android.gms", 0)
                            @Suppress("DEPRECATION")
                            val vc = if (Build.VERSION.SDK_INT >= 28) gms.longVersionCode else gms.versionCode.toLong()
                            sb.append("gms=").append(vc).append(" ")
                        } catch (t: Throwable) {
                            sb.append("gms=none ")
                        }
                        var out: String
                        try {
                            val tok = com.google.android.gms.tasks.Tasks.await(
                                com.google.firebase.messaging.FirebaseMessaging.getInstance().token,
                                60, java.util.concurrent.TimeUnit.SECONDS)
                            out = "ok:" + tok
                        } catch (e: Throwable) {
                            var c: Throwable? = e
                            var d = 0
                            while (c != null && d < 6) {
                                sb.append(" <- ").append(c.javaClass.simpleName).append(": ").append(c.message ?: "")
                                c = c.cause
                                d++
                            }
                            out = "err:" + sb.toString()
                        }
                        runOnUiThread { result.success(out) }
                    }.start()
                } else if (call.method == "hooked") {
                    Thread {
                    // كشف أدوات التلاعب اللي تنحقن داخل التطبيق (Frida / Xposed / LSPosed / Substrate)
                    val found = mutableListOf<String>()
                    try {
                        val maps = java.io.File("/proc/self/maps").readText()
                        for (k in listOf("frida-agent", "frida-gadget", "libfrida", "gum-js-loop", "XposedBridge",
                                "liblspd", "lspatch", "libsubstrate", "edxposed", "libriru_edxp")) {
                            if (maps.contains(k, ignoreCase = true)) found.add(k)
                        }
                    } catch (t: Throwable) {}
                    try {
                        // منفذ خادم Frida الافتراضي 27042 (69A2)
                        for (f in listOf("/proc/net/tcp", "/proc/net/tcp6")) {
                            val txt = java.io.File(f).readText()
                            if (txt.contains(":69A2 ")) { found.add("frida-port"); break }
                        }
                    } catch (t: Throwable) {}
                    try {
                        val st = java.io.File("/proc/self/status").readText()
                        val tp = st.substringAfter("TracerPid:", "0").trim().takeWhile { it.isDigit() }.toIntOrNull() ?: 0
                        if (tp != 0) found.add("tracer")
                    } catch (t: Throwable) {}
                    if ((applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) != 0) found.add("debuggable")
                    runOnUiThread { result.success(found) }
                    }.start()
                } else if (call.method == "sdk") {
                    result.success(Build.VERSION.SDK_INT)
                } else if (call.method == "abis") {
                    result.success(Build.SUPPORTED_ABIS.toList())
                } else if (call.method == "lastExit") {
                    // بخيط جانبي: قراءة سجل الانهيار ممكن تتأخر، وما نريد شاشة الشعار تعلك
                    Thread {
                        val r = try { lastExit() } catch (t: Throwable) { null }
                        runOnUiThread { result.success(r) }
                    }.start()
                } else if (call.method == "recentNativeCrashes") {
                    Thread {
                    var n = 0
                    try {
                        if (Build.VERSION.SDK_INT >= 30) {
                            val am = getSystemService(android.app.ActivityManager::class.java)
                            val since = System.currentTimeMillis() - 86400000L
                            for (x in am.getHistoricalProcessExitReasons(packageName, 0, 16)) {
                                if (x.reason == android.app.ApplicationExitInfo.REASON_CRASH_NATIVE && x.timestamp > since) n++
                            }
                        }
                    } catch (t: Throwable) {}
                    runOnUiThread { result.success(n) }
                    }.start()
                } else {
                    result.notImplemented()
                }
            }
    }

    private fun signatures(): List<Signature> {
        return if (Build.VERSION.SDK_INT >= 28) {
            val info = packageManager.getPackageInfo(packageName, PackageManager.GET_SIGNING_CERTIFICATES)
            val si = info.signingInfo ?: return emptyList()
            val arr = if (si.hasMultipleSigners()) si.apkContentsSigners else si.signingCertificateHistory
            arr?.toList() ?: emptyList()
        } else {
            @Suppress("DEPRECATION")
            val info = packageManager.getPackageInfo(packageName, PackageManager.GET_SIGNATURES)
            @Suppress("DEPRECATION")
            info.signatures?.toList() ?: emptyList()
        }
    }

    /** سبب آخر إغلاق للتطبيق (انهيار، نفاد ذاكرة...) لإرساله للمطوّر */
    private fun lastExit(): String? {
        if (Build.VERSION.SDK_INT < 30) return null
        return try {
            val am = getSystemService(android.app.ActivityManager::class.java)
            val list = am.getHistoricalProcessExitReasons(packageName, 0, 1)
            if (list.isEmpty()) return null
            val e = list[0]
            val prefs = getSharedPreferences("almajhool_exit", MODE_PRIVATE)
            if (prefs.getLong("ts", 0) == e.timestamp) return null
            prefs.edit().putLong("ts", e.timestamp).apply()
            val interesting = e.reason == android.app.ApplicationExitInfo.REASON_CRASH ||
                e.reason == android.app.ApplicationExitInfo.REASON_CRASH_NATIVE ||
                e.reason == android.app.ApplicationExitInfo.REASON_ANR ||
                e.reason == android.app.ApplicationExitInfo.REASON_LOW_MEMORY
            if (!interesting) return null
            "reason=" + e.reason + " status=" + e.status + " desc=" + (e.description ?: "") +
                " pss=" + e.pss + " api=" + Build.VERSION.SDK_INT + " model=" + Build.MODEL +
                " hw=" + Build.HARDWARE + " trace=" + traceOf(e)
        } catch (t: Throwable) {
            null
        }
    }

    /** أهم أسطر آثار الانهيار الأصلي (أسماء المكتبات والدوال فقط). */
    private fun traceOf(e: android.app.ApplicationExitInfo): String {
        return try {
            val bytes = e.traceInputStream?.use { ins ->
                val buf = java.io.ByteArrayOutputStream()
                val b = ByteArray(16384)
                var total = 0
                while (true) {
                    val n = ins.read(b)
                    if (n <= 0 || total > 600000) break
                    buf.write(b, 0, n); total += n
                }
                buf.toByteArray()
            } ?: return ""
            val pb = parseTombstone(bytes)
            if (pb.isNotEmpty()) return pb.take(2000)
            val runs = ArrayList<String>()
            val sb = StringBuilder()
            for (x in bytes) {
                val c = x.toInt() and 0xff
                if (c in 32..126) sb.append(c.toChar()) else {
                    if (sb.length >= 6) runs.add(sb.toString())
                    sb.setLength(0)
                }
            }
            if (sb.length >= 6) runs.add(sb.toString())
            val keys = listOf("Abort", "signal", "SIG", ".so", "::", "Java_", "webrtc", "jni", "Exception", "assert", "Check failed", "Fatal")
            val seen = LinkedHashSet<String>()
            for (r in runs) {
                if (keys.any { r.contains(it) }) seen.add((if (r.startsWith("/")) r.substringAfterLast('/') else r).take(140))
                if (seen.size >= 40) break
            }
            seen.joinToString(" ; ").take(2000)
        } catch (t: Throwable) { "err:" + t.javaClass.simpleName }
    }

    // قراءة مبسطة لملف الانهيار (protobuf): رسالة الإيقاف + آخر أسطر السجل المهمة
    private fun readVarint(b: ByteArray, pos: IntArray): Long {
        var r = 0L; var shift = 0
        while (pos[0] < b.size) {
            val c = b[pos[0]++].toInt() and 0xff
            r = r or ((c and 0x7f).toLong() shl shift)
            if (c and 0x80 == 0) break
            shift += 7
            if (shift > 63) break
        }
        return r
    }

    private fun fields(b: ByteArray, from: Int, to: Int, cb: (Int, Int, Int) -> Unit) {
        val pos = intArrayOf(from)
        while (pos[0] < to) {
            val key = readVarint(b, pos)
            val f = (key shr 3).toInt(); val t = (key and 7).toInt()
            when (t) {
                0 -> readVarint(b, pos)
                1 -> pos[0] += 8
                5 -> pos[0] += 4
                2 -> {
                    val len = readVarint(b, pos).toInt()
                    if (len < 0 || pos[0] + len > to) return
                    cb(f, pos[0], len)
                    pos[0] += len
                }
                else -> return
            }
        }
    }

    private fun parseTombstone(b: ByteArray): String {
        return try {
            var abort = ""
            val logs = ArrayList<String>()
            fields(b, 0, b.size) { f, off, len ->
                if (f == 14) abort = String(b, off, len)
                if (f == 18) fields(b, off, off + len) { f2, off2, len2 ->
                    if (f2 == 2) {
                        var tag = ""; var msg = ""
                        fields(b, off2, off2 + len2) { f3, o3, l3 ->
                            if (f3 == 5) tag = String(b, o3, l3)
                            if (f3 == 6) msg = String(b, o3, l3)
                        }
                        val low = (tag + msg).lowercase()
                        if (low.contains("flutter") || low.contains("fatal") || low.contains("check failed") ||
                            low.contains("webrtc") || low.contains("egl") || low.contains("abort") || low.contains("error")) {
                            logs.add(tag + ": " + msg.take(220))
                        }
                    }
                }
            }
            if (abort.isEmpty() && logs.isEmpty()) "" else
                "ABORT=" + abort.take(600) + " LOGS=" + logs.takeLast(10).joinToString(" | ")
        } catch (t: Throwable) { "" }
    }

    private fun sha256(s: Signature): String {
        val d = MessageDigest.getInstance("SHA-256").digest(s.toByteArray())
        return d.joinToString("") { "%02X".format(it) }
    }
}
"""


def write_main_activity():
    """MainActivity مع قناة فحص سلامة التطبيق (بصمة التوقيع) وفلاتر البث."""
    base = os.path.join(APP, "src", "main", "kotlin")
    filters_src = read(os.path.join(ROOT, "tool", "android", "FilterManager.kt"))
    for root, _dirs, files in os.walk(base):
        for f in files:
            if f == "MainActivity.kt":
                write(os.path.join(root, f), MAIN_ACTIVITY)
                write(os.path.join(root, "FilterManager.kt"), filters_src)
                print("MainActivity patched:", os.path.join(root, f))
                return
    target = os.path.join(base, "com", "almajhool", "almajhool_app")
    os.makedirs(target, exist_ok=True)
    write(os.path.join(target, "MainActivity.kt"), MAIN_ACTIVITY)
    write(os.path.join(target, "FilterManager.kt"), filters_src)
    print("MainActivity written")


def main():
    patch_manifest()
    write_proguard()
    write_main_activity()
    kts = os.path.join(APP, "build.gradle.kts")
    groovy = os.path.join(APP, "build.gradle")
    if os.path.exists(kts):
        patch_kts(kts)
    elif os.path.exists(groovy):
        patch_groovy(groovy)
    else:
        print("no app gradle file found", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
