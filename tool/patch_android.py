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
    write(path, s)
    print("build.gradle patched")


def write_proguard():
    p = os.path.join(APP, "proguard-rules.pro")
    rules = "-keep class org.webrtc.** { *; }\n-keep class com.cloudwebrtc.webrtc.** { *; }\n-dontwarn org.webrtc.**\n"
    existing = read(p) if os.path.exists(p) else ""
    if "org.webrtc" not in existing:
        write(p, existing + rules)
    print("proguard rules written")


MAIN_ACTIVITY = """package com.almajhool.almajhool_app

import android.content.pm.PackageManager
import android.content.pm.Signature
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.security.MessageDigest

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "almajhool/integrity")
            .setMethodCallHandler { call, result ->
                if (call.method == "sig") {
                    try {
                        result.success(signatures().map { sha256(it) })
                    } catch (e: Exception) {
                        result.success(listOf<String>())
                    }
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

    private fun sha256(s: Signature): String {
        val d = MessageDigest.getInstance("SHA-256").digest(s.toByteArray())
        return d.joinToString("") { "%02X".format(it) }
    }
}
"""


def write_main_activity():
    """MainActivity مع قناة فحص سلامة التطبيق (بصمة التوقيع)."""
    base = os.path.join(APP, "src", "main", "kotlin")
    for root, _dirs, files in os.walk(base):
        for f in files:
            if f == "MainActivity.kt":
                write(os.path.join(root, f), MAIN_ACTIVITY)
                print("MainActivity patched:", os.path.join(root, f))
                return
    target = os.path.join(base, "com", "almajhool", "almajhool_app")
    os.makedirs(target, exist_ok=True)
    write(os.path.join(target, "MainActivity.kt"), MAIN_ACTIVITY)
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
