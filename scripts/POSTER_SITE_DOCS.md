# Poster Site Documentation

This document explains how to publish, regenerate, and understand the output of the ePiE Consortium Poster Site for May 2026.

ePiE stands for Exposure to Pharmaceuticals in the Environment.

## Quick Links

- **Main README:** [`docs/poster_maps/README.md`](../docs/poster_maps/README.md)
- **Live Site:** `https://audlem.github.io/ePiE/poster_maps/`
- **GitHub Repository:** `https://github.com/AudLem/ePiE`
- **Build Scripts:** `build_poster_site.sh`, `generate_scenario_indexes.sh`

---

## Publishing Instructions

### 1. Initial Setup (One-Time)

Enable GitHub Pages for this repository:

1. **Navigate to GitHub**
   - Go to your repository: `https://github.com/AudLem/ePiE`
   - Click **Settings** (top right)
   - Click **Pages** (left sidebar, under "Code and automation")

2. **Configure GitHub Pages**
   - **Source:** Select `Deploy from a branch`
   - **Branch:** Select `main`
   - **Folder:** Select `/docs`
   - Click **Save**

3. **Wait for deployment**
   - GitHub will deploy the site automatically
   - Wait 1-2 minutes for the build to complete
   - The site URL will appear: `https://audlem.github.io/ePiE/`

4. **Access the poster site**
   - Full URL: `https://audlem.github.io/ePiE/poster_maps/`
   - Print the QR code: [`docs/poster_maps/assets/qr/index_qr.png`](../docs/poster_maps/assets/qr/index_qr.png)

### 2. Publishing Updates

After making changes to the site:

```bash
# Commit your changes
git add docs/ scripts/
git commit -m "Update poster site"

# Push to GitHub
git push

# GitHub Pages will automatically rebuild within 1-2 minutes
```

### 3. QR Code Usage

The main QR code for the poster is located at:
```
docs/poster_maps/assets/qr/index_qr.png
```

The QR code should point to:

```text
https://audlem.github.io/ePiE/poster_maps/
```

The build script regenerates the main QR code and one QR code for each scenario.

To use a different site URL later, run:

```bash
SITE_BASE_URL="https://your-site.example/ePiE/poster_maps" ./scripts/build_poster_site.sh
```

---

## How to Regenerate the Site

### After Running New Simulations

If you've run new simulations and want to update the poster site:

```bash
# 1. Build the site from current Outputs/
./scripts/build_poster_site.sh

# 2. Regenerate scenario index pages
./scripts/generate_scenario_indexes.sh

# 3. Commit and push
git add docs/poster_maps/
git commit -m "Regenerate poster site with updated scenarios"
git push
```

### Adding New Scenarios

To add a new scenario to the poster site:

1. **Run the simulation**
   ```bash
   # Example: Run a new scenario
   Rscript -e "
     library(ePiE)
     cfg <- LoadScenarioConfig('YourNewScenario', 'Inputs', 'Outputs')
     state <- BuildNetworkPipeline(cfg)
     results <- RunSimulationPipeline(state, cfg\$target_substance, cpp = FALSE)
   "
   ```

2. **Update the build script**
   - Edit `scripts/build_poster_site.sh`
   - Add your scenario to the `SCENARIOS` array (line ~15-23):
     ```bash
     SCENARIOS=(
       "bega_campy:bega_campy"
       "bega_crypto:bega_crypto"
       # ... existing scenarios ...
       "your_scenario:your_scenario"  # Add this line
     )
     ```

3. **Update the scenario index generator**
   - Edit `scripts/generate_scenario_indexes.sh`
   - Add your scenario to the `SCENARIOS` array (line ~14-22):
     ```bash
     SCENARIOS=(
       "bega_campy:Campylobacter:Description...:Bega:Bacteria"
       # ... existing scenarios ...
       "your_scenario:Your Pathogen:Description...:Your Basin:Type"
     )
     ```

4. **Update the main index.html**
   - Edit `docs/poster_maps/index.html`
   - Add a card in the appropriate basin section (Bega or Volta)

5. **Regenerate and deploy**
   ```bash
   ./scripts/build_poster_site.sh
   ./scripts/generate_scenario_indexes.sh
   git add docs/poster_maps/ scripts/
   git commit -m "Add YourScenario to poster site"
   git push
   ```

### Full Rebuild (From Scratch)

To completely rebuild the site from scratch:

```bash
# Remove existing site
rm -rf docs/poster_maps/bega_* docs/poster_maps/volta_* docs/poster_maps/assets

# Rebuild
./scripts/build_poster_site.sh
./scripts/generate_scenario_indexes.sh

# Verify
ls -la docs/poster_maps/
```

---

## What This Should Generate

### Site Structure

After running `build_poster_site.sh`, the following structure is created:

```
docs/poster_maps/
├── index.html                          # Main landing page (phone-first)
├── README.md                           # Site documentation
│
├── assets/                             # Shared assets
│   ├── libs/                           # Shared Leaflet/jquery/proj4 libraries (~956KB)
│   │   ├── jquery-3.6.0/
│   │   ├── leaflet-1.3.1/
│   │   ├── leaflet-binding-2.2.3/
│   │   ├── leaflet-providers-3.0.0/
│   │   ├── proj4-2.6.2/
│   │   └── ...
│   └── qr/                             # QR codes (9 PNG files)
│       ├── index_qr.png                # Master QR for poster
│       ├── bega_campy_qr.png
│       ├── bega_crypto_qr.png
│       ├── bega_giardia_qr.png
│       ├── bega_rota_qr.png
│       ├── volta_campy_qr.png
│       ├── volta_crypto_qr.png
│       ├── volta_giardia_qr.png
│       └── volta_rota_qr.png
│
├── bega_campy/                         # Bega Campylobacter scenario
│   ├── index.html                      # Scenario detail page
│   ├── interactive_network_map.html     # Interactive Leaflet map
│   ├── interactive_tmap_map.html        # Interactive tmap map
│   ├── static_agglomerations.png       # Agglomeration map
│   ├── static_network_overview.png     # Network topology
│   ├── static_node_types.png           # Node type distribution
│   ├── static_network_poster.png       # High-res poster (6000x4200px)
│   ├── static_network_poster.pdf       # PDF poster
│   │
│   ├── data/                           # CSV data tables
│   │   ├── pts.csv                     # Network nodes
│   │   ├── hl.csv                      # Lake polygons
│   │   ├── hydrology_nodes.csv         # Discharge data
│   │   ├── simulation_results.csv      # Pathogen concentrations (C_w)
│   │   ├── pathogen_provenance_summary.csv
│   │   ├── run_provenance_summary.csv
│   │   ├── lake_connections.csv
│   │   └── lake_connection_diagnostics.csv
│   │
│   └── gis/                            # Shapefiles for QGIS/ArcGIS
│       ├── network_points.{shp,dbf,prj,shx}
│       ├── network_rivers.{shp,dbf,prj,shx}
│       ├── network_canals.{shp,dbf,prj,shx}  # Volta scenarios only
│       └── network_lakes.{shp,dbf,prj,shx}
│
├── bega_crypto/                         # Bega Cryptosporidium (same structure)
├── bega_giardia/                        # Bega Giardia (same structure)
├── bega_rota/                           # Bega Rotavirus (same structure)
├── volta_campy/                         # Volta Campylobacter (same structure)
├── volta_crypto/                         # Volta Cryptosporidium (same structure)
├── volta_giardia/                        # Volta Giardia (same structure)
└── volta_rota/                           # Volta Rotavirus (same structure)
```

### Generated Content Summary

| Category | Count | Description |
|----------|-------|-------------|
| **Scenarios** | 8 | 4 Bega + 4 Volta wet season |
| **Interactive Maps** | 16 | 2 per scenario (Leaflet + tmap) |
| **Static Maps** | 40 | 5 per scenario (4 PNG + 1 PDF) |
| **Data Tables** | 72 | 9 CSV files per scenario |
| **GIS Layers** | 28 | 3 shapefiles per Bega scenario, 4 per Volta scenario |
| **QR Codes** | 9 | 1 master + 8 per-scenario |
| **Total Files** | ~250+ | Including library assets |

### File Sizes

| Component | Size |
|-----------|------|
| `assets/libs/` | ~956 KB (deduplicated) |
| `assets/qr/` | ~5 KB (9 PNG files) |
| Per scenario | ~4 MB (Bega) / ~3 MB (Volta) |
| **Total site** | ~34 MB |

### Key Features Generated

#### 1. Phone-First Index Page (`index.html`)
- Responsive design (1 column on mobile, 4 on desktop)
- 48px+ tap targets for touch
- Master QR code for poster
- Per-scenario cards with inline QR codes
- Scientific overview with file type explanations
- Known issues section

#### 2. Scenario Detail Pages (8 × `index.html`)
- Scenario title, description, basin, pathogen type
- Interactive network map link (primary action)
- Concentration data section (CSV download)
- Static maps list with descriptions
- Data tables list with file sizes
- GIS layers download link
- Back button to main index

#### 3. Interactive Network Maps (16 files)
- Leaflet-based interactive maps
- Node popups with discharge, population, source info
- Zoom and pan controls
- Layer toggle (network, lakes, points)

#### 4. Pathogen Concentration Data (8 × CSV)
- `simulation_results.csv` — Primary concentration table
  - `C_w` column: pathogen concentration (oocysts/L)
  - `Q` column: discharge (m³/s)
  - `Hylak_id`: lake identifier
  - `pt_type`: node type (START, node, MOUTH, agglomeration, WWTP)
  - `x`, `y`: coordinates
  - Full provenance metadata

#### 5. Static Maps (40 files)
- `static_network_overview.png` — Full network topology
- `static_node_types.png` — Node type distribution
- `static_agglomerations.png` — Population centers
- `static_network_poster.png` — 6000×4200px poster (300 DPI)
- `static_network_poster.pdf` — Vector version for printing

#### 6. GIS Layers (28 shapefile sets)
- `network_points.shp` — Point locations for all nodes
- `network_rivers.shp` — River reach line geometries
- `network_canals.shp` — Canal reach line geometries for Volta scenarios only
- `network_lakes.shp` — Lake polygon geometries
- Compatible with QGIS, ArcGIS, and other GIS software

#### 7. QR Codes (9 PNG files)
- Master QR code for the index page (for the main poster)
- 8 per-scenario QR codes (for individual poster panels if needed)
- 300×300 pixels, suitable for printing

---

## Troubleshooting

### Site Not Loading After Push

1. **Check GitHub Pages status:**
   - Go to repository → Actions → Pages
   - Check for deployment errors

2. **Verify branch is correct:**
   ```bash
   git branch --show-current  # Should be 'main'
   ```

3. **Wait for deployment:**
   - GitHub Pages can take 1-5 minutes to build
   - Check the deployment timestamp in repository → Settings → Pages

### QR Codes Show Wrong URL

The default QR code URL is:

```text
https://audlem.github.io/ePiE/poster_maps/
```

If the site moves, rebuild with a new base URL:

```bash
SITE_BASE_URL="https://your-site.example/ePiE/poster_maps" ./scripts/build_poster_site.sh
./scripts/generate_scenario_indexes.sh
git add docs/poster_maps/ scripts/build_poster_site.sh
git commit -m "Fix poster QR code URL"
git push
```

If you only need to regenerate the current QR codes:

```bash
./scripts/build_poster_site.sh
git add docs/poster_maps/
git commit -m "Regenerate poster QR codes"
git push
```

### Interactive Maps Not Working

1. **Check library paths:**
   - HTML files should reference `../assets/libs/`
   - Verify `docs/poster_maps/assets/libs/` exists and contains files

2. **Rebuild the site:**
   ```bash
   rm -rf docs/poster_maps/assets/libs
   ./scripts/build_poster_site.sh
   ```

### Missing Scenario After Rebuild

If a scenario doesn't appear after regeneration:

1. **Check if Outputs exist:**
   ```bash
   ls Outputs/your_scenario/plots/
   ```

2. **Check build script array:**
   - Verify scenario is in `SCENARIOS` array in `build_poster_site.sh`
   - Format: `"output_dir:web_path"`

3. **Rebuild manually:**
   ```bash
   # Force rebuild for specific scenario
   rm -rf docs/poster_maps/your_scenario
   ./scripts/build_poster_site.sh
   ```

---

## Maintenance

### Regular Updates

**After running new pathogen simulations:**
```bash
# 1. Run simulations (if needed)
Rscript scripts/poster_consortium_06_may_2026.R

# 2. Regenerate site
./scripts/build_poster_site.sh
./scripts/generate_scenario_indexes.sh

# 3. Review changes
git status

# 4. Commit and push
git add docs/poster_maps/
git commit -m "Update poster site with new simulation results"
git push
```

### Customizing the Design

**To change colors:**
Edit CSS variables in `docs/poster_maps/index.html`:
```css
:root {
    --primary: #2171b5;      /* Primary blue */
    --secondary: #00bcd4;   /* Cyan */
    --pathogen: #e31a1c;    /* Red for pathogens */
}
```

**To change scenario descriptions:**
Edit `SCENARIOS` array in `scripts/generate_scenario_indexes.sh`:
```bash
"bega_crypto:Cryptosporidium:Your description here:Bega:Parasite"
```

**To add new pathogen types:**
Edit CSS in `docs/poster_maps/index.html` to add new tag classes:
```css
.tag-yourtype { color: #your-color; border: 1px solid #your-color; background: #your-bg; }
```

---

## Related Documentation

- [Main README](../README.md) — Project overview
- [Poster Site README](../docs/poster_maps/README.md) — Site structure and features
- [RELEASE_PROCESS.md](../docs/RELEASE_PROCESS.md) — Publishing code releases
- [DATA_REQUIREMENTS.md](../Package/DATA_REQUIREMENTS.md) — Data input requirements

---

## Contact

For questions about the poster site or ePiE model, please refer to the main project documentation or contact the ePiE team.
