# ePiE Consortium Poster Site

This directory contains the static website for the May 2026 Consortium presentation, hosting interactive network maps, static maps, and pathogen concentration data for 8 scenarios across 2 basins.

## Documentation

- **[Publishing & Regeneration Guide](../../scripts/POSTER_SITE_DOCS.md)** — How to publish to GitHub Pages and regenerate the site
- **[Project README](../../README.md)** — Main project documentation

## Quick Start

1. **Set up GitHub Pages:**
   - Go to your repository on GitHub
   - Navigate to Settings → Pages
   - Set Source to `docs` folder
   - Click Save

2. **Push to GitHub:**
   ```bash
   git add docs/ scripts/
   git commit -m "Add/update poster site for consortium May 2026"
   git push
   ```

3. **Access the site:**
   - Visit: `https://<your-username>.github.io/ePiE/poster_maps/`
   - Print the QR code: `docs/poster_maps/assets/qr/index_qr.png`

## Site Structure

```
docs/poster_maps/
├── index.html                          # Main landing page (phone-first design)
├── assets/
│   ├── libs/                           # Shared Leaflet/jquery/proj4 libraries
│   └── qr/                             # QR codes (index + 8 scenarios)
├── bega_campy/                         # Bega Campylobacter scenario
│   ├── index.html                      # Scenario detail page
│   ├── interactive_network_map.html     # Interactive network map
│   ├── interactive_tmap_map.html        # Alternative tmap map
│   ├── static_*.png/pdf                # Static maps
│   ├── data/                           # CSV data tables
│   │   └── simulation_results.csv      # Pathogen concentrations (C_w column)
│   └── gis/                            # Shapefiles for QGIS/ArcGIS
├── bega_crypto/                         # Bega Cryptosporidium
├── bega_giardia/                        # Bega Giardia
├── bega_rota/                           # Bega Rotavirus
├── volta_campy/                         # Volta Campylobacter
├── volta_crypto/                         # Volta Cryptosporidium
├── volta_giardia/                        # Volta Giardia
└── volta_rota/                           # Volta Rotavirus
```

## Available Outputs

### Interactive Maps
- **Network maps** — Tap nodes to view discharge, population, and source information
- Leaflet-based, mobile-friendly

### Pathogen Concentration Data
- **simulation_results.csv** — Contains `C_w` column with pathogen concentrations
- Located in each scenario's `data/` subdirectory
- Available for all 8 scenarios

### Static Maps
- Network overview
- Node type distribution
- Agglomeration points
- Poster-ready PNG and PDF (6000x4200px)

### GIS Layers
- `network_points.shp` — Node locations
- `network_rivers.shp` — River reach geometries
- `network_lakes.shp` — Lake polygons

## Regenerating the Site

### After running new simulations:

```bash
# 1. Rebuild the site from current Outputs/
./scripts/build_poster_site.sh

# 2. Regenerate scenario index pages
./scripts/generate_scenario_indexes.sh
```

### To add new scenarios:

1. Run the simulation to generate outputs in `Outputs/`
2. Update the scenario list in `scripts/build_poster_site.sh`
3. Run the build script above
4. Update the main `index.html` to add the new scenario card

### To update QR codes:

The QR codes are generated automatically by `build_poster_site.sh` using an API. To update them:

1. Edit the GitHub username in the QR code URLs in `build_poster_site.sh` (line ~116)
2. Run `./scripts/build_poster_site.sh` again

## Scenarios Included

### Bega Basin (Romania)
- **Bega Crypto** — Cryptosporidium transport model
- **Bega Campy** — Campylobacter transport model
- **Bega Rota** — Rotavirus transport model
- **Bega Giardia** — Giardia transport model

### Volta Basin (Ghana) - Wet Season
- **Volta Crypto** — Cryptosporidium transport model
- **Volta Campy** — Campylobacter transport model
- **Volta Rota** — Rotavirus transport model
- **Volta Giardia** — Giardia transport model

## Known Issues

### Interactive Concentration Maps
Interactive concentration maps (showing pathogen levels as colored nodes) are temporarily unavailable due to a visualization bug in the rendering code. Pathogen concentration data is available in `data/simulation_results.csv` (column `C_w`) for all scenarios.

## Technical Details

- **Framework:** Static HTML/CSS/JavaScript
- **Mapping:** Leaflet.js with custom ePiE styling
- **Design:** Phone-first (48px+ tap targets, single column on mobile)
- **Assets:** ~1MB (deduplicated Leaflet libs)
- **QR Codes:** Generated via QR Server API

## Maintaining the Site

### To change the main index page:
Edit `docs/poster_maps/index.html` — it's a self-contained HTML file with inline CSS.

### To change scenario descriptions:
Edit `scripts/generate_scenario_indexes.sh` — scenario titles and descriptions are in the `SCENARIOS` array.

### To change color scheme:
Edit the CSS variables in the `<style>` block of `index.html`:
```css
:root {
    --primary: #2171b5;      /* Primary blue */
    --secondary: #00bcd4;   /* Cyan */
    --pathogen: #e31a1c;    /* Red for pathogens */
}
```

## Support

For issues or questions about the ePiE model or this poster site, please refer to the main project documentation or contact the ePiE team.
