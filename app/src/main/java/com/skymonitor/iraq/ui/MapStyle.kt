package com.skymonitor.iraq.ui

/**
 * Dark radar-style vector map built on free, keyless public services:
 *  - OpenFreeMap vector tiles (OpenMapTiles schema, OpenStreetMap data) — names shown in Arabic (name:ar)
 *  - AWS Terrain Tiles (Terrarium DEM) for 3D relief shading
 *  - 3D extruded buildings at street zoom
 */
enum class MapMode { SATELLITE, RADAR }

object MapStyle {
    fun forMode(mode: MapMode): String = if (mode == MapMode.RADAR) json else satellite

    /**
     * Satellite imagery (Esri World Imagery, keyless with attribution) with the same Arabic labels,
     * borders and coloured 3D buildings on top.
     */
    val satellite: String by lazy {
        val root = org.json.JSONObject(json)
        root.getJSONObject("sources").put("sat", org.json.JSONObject()
            .put("type", "raster").put("tileSize", 256).put("maxzoom", 19)
            .put("tiles", org.json.JSONArray().put("https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}"))
            .put("attribution", "Imagery © Esri, Maxar, Earthstar Geographics"))
        val keep = setOf("boundary-provinces", "boundary-countries", "roads-major", "buildings-3d",
            "label-water", "label-roads", "label-airports", "label-villages", "label-towns", "label-provinces", "label-countries", "label-cities")
        val old = root.getJSONArray("layers")
        val layers = org.json.JSONArray()
        layers.put(org.json.JSONObject().put("id", "sat").put("type", "raster").put("source", "sat")
            .put("paint", org.json.JSONObject().put("raster-fade-duration", 120)))
        for (i in 0 until old.length()) {
            val l = old.getJSONObject(i)
            val id = l.getString("id")
            if (id !in keep) continue
            val paint = l.optJSONObject("paint") ?: org.json.JSONObject()
            when {
                id.startsWith("label-") -> paint.put("text-color", if (id == "label-countries" || id == "label-cities") "#FFFFFF" else "#F1F1E8")
                    .put("text-halo-color", "#000000").put("text-halo-width", 1.6)
                id == "roads-major" -> { l.put("minzoom", 11); paint.put("line-color", "#F4E2B0").put("line-opacity", 0.35) }
                id == "boundary-countries" -> paint.put("line-color", "#FFE08A")
                id == "boundary-provinces" -> paint.put("line-color", "#FFFFFF").put("line-opacity", 0.55)
                id == "buildings-3d" -> { l.put("minzoom", 14); paint.put("fill-extrusion-opacity", 0.92) }
            }
            l.put("paint", paint)
            layers.put(l)
        }
        root.put("layers", layers).toString()
    }

    private const val AR = """["coalesce", ["get", "name:ar"], ["get", "name"]]"""
    private const val FONT = """["Noto Sans Regular"]"""
    private const val FONT_BOLD = """["Noto Sans Bold"]"""

    val json: String = """
{
  "version": 8,
  "name": "SkyMonitorRadar",
  "glyphs": "https://tiles.openfreemap.org/fonts/{fontstack}/{range}.pbf",
  "sources": {
    "omt": { "type": "vector", "url": "https://tiles.openfreemap.org/planet",
             "attribution": "© OpenFreeMap © OpenMapTiles © OpenStreetMap" },
    "dem": { "type": "raster-dem", "encoding": "terrarium", "tileSize": 256, "maxzoom": 12,
             "tiles": ["https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png"],
             "attribution": "Terrain: Mapzen / AWS Terrain Tiles" }
  },
  "layers": [
    { "id": "bg", "type": "background", "paint": { "background-color": "#0B1318" } },

    { "id": "landcover", "type": "fill", "source": "omt", "source-layer": "landcover",
      "paint": { "fill-color": ["match", ["get", "class"], "sand", "#141A17", "wood", "#0F1C17", "grass", "#0F1A16", "farmland", "#101A15", "#0E1714"],
                 "fill-opacity": 0.75 } },
    { "id": "landuse", "type": "fill", "source": "omt", "source-layer": "landuse", "minzoom": 8,
      "paint": { "fill-color": "#121B21", "fill-opacity": 0.8 } },
    { "id": "park", "type": "fill", "source": "omt", "source-layer": "park",
      "paint": { "fill-color": "#0E1D17", "fill-opacity": 0.6 } },

    { "id": "relief", "type": "hillshade", "source": "dem",
      "paint": { "hillshade-exaggeration": 0.75, "hillshade-shadow-color": "#000000",
                 "hillshade-highlight-color": "#3B6158", "hillshade-accent-color": "#12302A",
                 "hillshade-illumination-direction": 315 } },

    { "id": "water", "type": "fill", "source": "omt", "source-layer": "water",
      "paint": { "fill-color": "#0A2433" } },
    { "id": "rivers", "type": "line", "source": "omt", "source-layer": "waterway",
      "paint": { "line-color": "#11405B", "line-width": ["interpolate", ["linear"], ["zoom"], 4, 0.6, 10, 1.6, 14, 3] } },

    { "id": "airport-runways", "type": "line", "source": "omt", "source-layer": "aeroway", "minzoom": 9,
      "filter": ["==", ["get", "class"], "runway"],
      "paint": { "line-color": "#3E5D6A", "line-width": ["interpolate", ["exponential", 2], ["zoom"], 9, 1, 15, 30] } },

    { "id": "roads-minor", "type": "line", "source": "omt", "source-layer": "transportation", "minzoom": 11,
      "filter": ["match", ["get", "class"], ["minor", "service", "tertiary", "secondary"], true, false],
      "paint": { "line-color": "#1B272E", "line-width": ["interpolate", ["linear"], ["zoom"], 11, 0.5, 16, 4] } },
    { "id": "roads-major", "type": "line", "source": "omt", "source-layer": "transportation", "minzoom": 5,
      "filter": ["match", ["get", "class"], ["motorway", "trunk", "primary"], true, false],
      "paint": { "line-color": "#26353E", "line-width": ["interpolate", ["linear"], ["zoom"], 5, 0.4, 10, 1.4, 16, 7] } },

    { "id": "boundary-provinces", "type": "line", "source": "omt", "source-layer": "boundary", "minzoom": 4,
      "filter": ["all", ["==", ["get", "admin_level"], 4], ["!=", ["get", "maritime"], 1]],
      "paint": { "line-color": "#2E6A5A", "line-width": ["interpolate", ["linear"], ["zoom"], 4, 0.5, 10, 1.4], "line-dasharray": [3, 2] } },
    { "id": "boundary-countries", "type": "line", "source": "omt", "source-layer": "boundary",
      "filter": ["all", ["==", ["get", "admin_level"], 2], ["!=", ["get", "maritime"], 1]],
      "paint": { "line-color": "#47B08C", "line-width": ["interpolate", ["linear"], ["zoom"], 1, 0.6, 6, 1.6, 12, 2.6] } },

    { "id": "buildings-3d", "type": "fill-extrusion", "source": "omt", "source-layer": "building", "minzoom": 13,
      "paint": { "fill-extrusion-color": ["interpolate", ["linear"], ["coalesce", ["get", "render_height"], 8],
                     0, "#CFC2A8", 10, "#C4B391", 25, "#B9A78A", 50, "#9DB0C2", 120, "#7F9BB8"],
                 "fill-extrusion-vertical-gradient": true,
                 "fill-extrusion-height": ["coalesce", ["get", "render_height"], 8],
                 "fill-extrusion-base": ["coalesce", ["get", "render_min_height"], 0],
                 "fill-extrusion-opacity": 0.85 } },

    { "id": "label-water", "type": "symbol", "source": "omt", "source-layer": "water_name",
      "layout": { "text-field": $AR, "text-font": $FONT, "text-size": 12, "text-max-width": 8 },
      "paint": { "text-color": "#3F7896", "text-halo-color": "#0A2433", "text-halo-width": 1 } },
    { "id": "label-roads", "type": "symbol", "source": "omt", "source-layer": "transportation_name", "minzoom": 13,
      "layout": { "text-field": $AR, "text-font": $FONT, "text-size": 11, "symbol-placement": "line" },
      "paint": { "text-color": "#8FA39D", "text-halo-color": "#0B1318", "text-halo-width": 1.2 } },
    { "id": "label-airports", "type": "symbol", "source": "omt", "source-layer": "aerodrome_label", "minzoom": 8,
      "layout": { "text-field": $AR, "text-font": $FONT, "text-size": 11, "text-offset": [0, 0.6], "text-anchor": "top" },
      "paint": { "text-color": "#7FB8D6", "text-halo-color": "#0B1318", "text-halo-width": 1.2 } },
    { "id": "label-villages", "type": "symbol", "source": "omt", "source-layer": "place", "minzoom": 10,
      "filter": ["match", ["get", "class"], ["village", "suburb"], true, false],
      "layout": { "text-field": $AR, "text-font": $FONT, "text-size": 11 },
      "paint": { "text-color": "#8FA39D", "text-halo-color": "#0B1318", "text-halo-width": 1.2 } },
    { "id": "label-towns", "type": "symbol", "source": "omt", "source-layer": "place", "minzoom": 7,
      "filter": ["==", ["get", "class"], "town"],
      "layout": { "text-field": $AR, "text-font": $FONT, "text-size": 12 },
      "paint": { "text-color": "#B3C6C0", "text-halo-color": "#0B1318", "text-halo-width": 1.3 } },
    { "id": "label-provinces", "type": "symbol", "source": "omt", "source-layer": "place", "minzoom": 4.5, "maxzoom": 9,
      "filter": ["==", ["get", "class"], "state"],
      "layout": { "text-field": $AR, "text-font": $FONT, "text-size": 12, "text-letter-spacing": 0.05 },
      "paint": { "text-color": "#6FAE98", "text-halo-color": "#0B1318", "text-halo-width": 1.3 } },
    { "id": "label-countries", "type": "symbol", "source": "omt", "source-layer": "place", "maxzoom": 8,
      "filter": ["==", ["get", "class"], "country"],
      "layout": { "text-field": $AR, "text-font": $FONT_BOLD,
                  "text-size": ["interpolate", ["linear"], ["zoom"], 1, 10, 4, 15, 7, 19], "text-max-width": 7 },
      "paint": { "text-color": "#A6F0D2", "text-halo-color": "#0B1318", "text-halo-width": 1.8 } },
    { "id": "label-cities", "type": "symbol", "source": "omt", "source-layer": "place", "minzoom": 4,
      "filter": ["==", ["get", "class"], "city"],
      "layout": { "text-field": $AR, "text-font": $FONT_BOLD,
                  "text-size": ["interpolate", ["linear"], ["zoom"], 4, 11, 10, 16] },
      "paint": { "text-color": "#E2EEEA", "text-halo-color": "#0B1318", "text-halo-width": 1.5 } }
  ]
}
""".trimIndent()
}
