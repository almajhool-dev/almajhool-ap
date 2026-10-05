# MapLibre ships its own consumer rules; keep JNI-bound classes just in case.
-keep class org.maplibre.android.** { *; }
-dontwarn org.maplibre.android.**
-keep class org.maplibre.geojson.** { *; }
-keep class org.maplibre.turf.** { *; }
-keep class com.google.gson.** { *; }
-dontwarn org.maplibre.geojson.**
