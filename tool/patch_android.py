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


def main():
    patch_manifest()
    write_proguard()
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
