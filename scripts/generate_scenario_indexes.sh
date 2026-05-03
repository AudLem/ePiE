#!/bin/bash
#
# Generate per-scenario index pages
#

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
POSTER_DIR="${REPO_ROOT}/docs/poster_maps"

# Scenario info (name:title:description:basin:pathogen_type)
SCENARIOS=(
    "bega_campy:Campylobacter:Primary cause of bacterial gastroenteritis. Sensitive to UV and temperature.:Bega:Bacteria"
    "bega_crypto:Cryptosporidium:Highly resistant protozoan. Significant concern for drinking water safety.:Bega:Parasite"
    "bega_giardia:Giardia:Widespread protozoan associated with mixed domestic/wildlife sources.:Bega:Parasite"
    "bega_rota:Rotavirus:Highly infectious viral pathogen, critical for pediatric health modeling.:Bega:Virus"
    "volta_campy:Campylobacter:Modeling bacterial load dynamics near population centers.:Volta:Bacteria"
    "volta_crypto:Cryptosporidium:Visualizing environmental persistence in tropical river reaches.:Volta:Parasite"
    "volta_giardia:Giardia:Mapping protozoan prevalence in the lower Volta network.:Volta:Parasite"
    "volta_rota:Rotavirus:Assessing viral load during peak seasonal discharge.:Volta:Virus"
)

generate_scenario_index() {
    local scenario_dir="$1"
    local title="$2"
    local description="$3"
    local basin="$4"
    local pathogen_type="$5"

    cat > "${scenario_dir}/index.html" << EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=5.0, user-scalable=yes">
    <title>${title} | ePiE Model Portal</title>
    <style>
        :root {
            --primary: #2171b5;
            --secondary: #00bcd4;
            --dark: #2b2b2b;
            --light: #f4f7f6;
            --pathogen: #e31a1c;
        }
        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
            line-height: 1.6;
            color: var(--dark);
            background-color: var(--light);
            margin: 0;
            padding: 0;
        }
        header {
            background: linear-gradient(135deg, var(--primary) 0%, var(--secondary) 100%);
            color: white;
            padding: 1.5rem 1rem 2rem;
            text-align: center;
            box-shadow: 0 4px 12px rgba(0,0,0,0.15);
        }
        header h1 {
            margin: 0 0 0.25rem 0;
            font-size: 1.6rem;
        }
        header .subtitle {
            margin: 0;
            opacity: 0.95;
            font-size: 0.9rem;
        }
        .container {
            max-width: 900px;
            margin: 0 auto 3rem;
            padding: 0 1rem;
        }
        .back-link {
            display: inline-block;
            margin: 1rem 0;
            color: var(--primary);
            text-decoration: none;
            font-weight: 600;
        }
        .back-link:hover {
            text-decoration: underline;
        }
        .scenario-info {
            background: white;
            padding: 1.5rem;
            border-radius: 8px;
            margin-bottom: 2rem;
            box-shadow: 0 2px 10px rgba(0,0,0,0.05);
            border-left: 5px solid var(--secondary);
        }
        .scenario-info h2 {
            margin: 0 0 0.5rem 0;
            color: var(--primary);
        }
        .scenario-info p {
            margin: 0 0 0.5rem 0;
            color: #555;
        }
        .tag {
            display: inline-block;
            background: #f5f5f5;
            padding: 0.25rem 0.6rem;
            border-radius: 4px;
            font-size: 0.75rem;
            font-weight: 600;
            text-transform: uppercase;
            margin-top: 0.5rem;
        }
        .tag-basin { color: var(--primary); border: 1px solid var(--primary); }
        .tag-pathogen { color: var(--pathogen); border: 1px solid var(--pathogen); }
        .section {
            background: white;
            padding: 1.5rem;
            border-radius: 8px;
            margin-bottom: 2rem;
            box-shadow: 0 2px 10px rgba(0,0,0,0.05);
        }
        .section h3 {
            margin: 0 0 1rem 0;
            color: var(--primary);
            font-size: 1.2rem;
            display: flex;
            align-items: center;
            gap: 0.5rem;
        }
        .primary-action {
            display: block;
            background: var(--primary);
            color: white;
            text-align: center;
            padding: 1rem;
            border-radius: 8px;
            text-decoration: none;
            font-weight: bold;
            font-size: 1.1rem;
            margin-bottom: 1rem;
            min-height: 54px;
            display: flex;
            align-items: center;
            justify-content: center;
            transition: background 0.2s;
        }
        .primary-action:hover {
            background: #1a5a8f;
        }
        .file-list {
            list-style: none;
            padding: 0;
            margin: 0;
        }
        .file-list li {
            padding: 0.75rem 0;
            border-bottom: 1px solid #eee;
        }
        .file-list li:last-child {
            border-bottom: none;
        }
        .file-link {
            display: flex;
            align-items: center;
            gap: 0.75rem;
            text-decoration: none;
            color: inherit;
        }
        .file-link:hover .file-name {
            color: var(--primary);
        }
        .file-icon {
            font-size: 1.5rem;
            width: 40px;
            text-align: center;
        }
        .file-info {
            flex-grow: 1;
        }
        .file-name {
            font-weight: 600;
            color: var(--dark);
            margin-bottom: 0.1rem;
        }
        .file-desc {
            font-size: 0.85rem;
            color: #666;
            margin: 0;
        }
        .file-size {
            font-size: 0.8rem;
            color: #999;
        }
        footer {
            text-align: center;
            padding: 2rem 1rem;
            color: #888;
            font-size: 0.85rem;
            background: white;
            border-top: 1px solid #e0e0e0;
        }
    </style>
</head>
<body>

<header>
    <h1>${title}</h1>
    <p class="subtitle">${basin} Basin | ${pathogen_type} Transport Model</p>
</header>

<div class="container">
    <a href="../index.html" class="back-link">← Back to All Scenarios</a>

    <div class="scenario-info">
        <h2>About This Scenario</h2>
        <p>${description}</p>
        <span class="tag tag-basin">${basin} Basin</span>
        <span class="tag tag-pathogen">${pathogen_type}</span>
    </div>

    <div class="section">
        <h3>🗺️ Network Maps</h3>
        <a href="interactive_network_map.html" class="primary-action">
            Open Interactive Network Map →
        </a>
        <p style="margin-top: 0.5rem; color: #666; font-size: 0.9rem;">
            Tap on any node to view discharge, population, and source information.
        </p>
        <ul class="file-list">
EOF

    # List HTML maps
    if [[ -f "${scenario_dir}/interactive_tmap_map.html" ]]; then
        cat >> "${scenario_dir}/index.html" << EOF
            <li>
                <a href="interactive_tmap_map.html" class="file-link">
                    <span class="file-icon">📊</span>
                    <div class="file-info">
                        <div class="file-name">Interactive Tmap Map</div>
                        <p class="file-desc">Alternative interactive map using tmap</p>
                    </div>
                </a>
            </li>
EOF
    fi

    cat >> "${scenario_dir}/index.html" << EOF
        </ul>
    </div>

    <div class="section">
        <h3>📊 Concentration Data</h3>
        <p style="color: #666; font-size: 0.9rem; margin-bottom: 1rem;">
          <strong>Note:</strong> Interactive concentration maps are temporarily unavailable due to a visualization bug. 
          Pathogen concentration data is available in the simulation results table below.
        </p>
        <ul class="file-list">
EOF

    # List HTML maps
    if [[ -f "${scenario_dir}/interactive_tmap_map.html" ]]; then
        cat >> "${scenario_dir}/index.html" << EOF
            <li>
                <a href="interactive_tmap_map.html" class="file-link">
                    <span class="file-icon">📊</span>
                    <div class="file-info">
                        <div class="file-name">Interactive Tmap Map</div>
                        <p class="file-desc">Alternative interactive map using tmap</p>
                    </div>
                </a>
            </li>
EOF
    fi

    cat >> "${scenario_dir}/index.html" << EOF
        </ul>
    </div>

    <div class="section">
        <h3>🖼️ Static Maps</h3>
        <ul class="file-list">
EOF

    # List static maps
    for f in static_network_overview.png static_node_types.png static_agglomerations.png static_network_poster.png static_network_poster.pdf; do
        if [[ -f "${scenario_dir}/${f}" ]]; then
            size=$(ls -lh "${scenario_dir}/${f}" | awk '{print $5}')
            desc=""
            case "$f" in
                static_network_overview.png) desc="Overview of the river network topology" ;;
                static_node_types.png) desc="Node type distribution (WWTP, agglomeration, junctions)" ;;
                static_agglomerations.png) desc="Population centers and agglomeration points" ;;
                static_network_poster.png) desc="High-resolution poster-ready network map" ;;
                static_network_poster.pdf) desc="PDF version of the poster map" ;;
            esac
            cat >> "${scenario_dir}/index.html" << EOF
            <li>
                <a href="${f}" class="file-link">
                    <span class="file-icon">🖼️</span>
                    <div class="file-info">
                        <div class="file-name">${f}</div>
                        <p class="file-desc">${desc}</p>
                    </div>
                    <span class="file-size">${size}</span>
                </a>
            </li>
EOF
        fi
    done

    cat >> "${scenario_dir}/index.html" << EOF
        </ul>
    </div>

    <div class="section">
        <h3>📊 Data Tables</h3>
        <ul class="file-list">
EOF

    # List data files
    for f in pts.csv simulation_results.csv hydrology_nodes.csv pathogen_provenance_summary.csv run_provenance_summary.csv lake_connections.csv lake_connection_diagnostics.csv hl.csv; do
        if [[ -f "${scenario_dir}/data/${f}" ]]; then
            size=$(ls -lh "${scenario_dir}/data/${f}" | awk '{print $5}')
            desc=""
            case "$f" in
                pts.csv) desc="Network node coordinates and attributes" ;;
                simulation_results.csv) desc="Pathogen concentrations at each node" ;;
                hydrology_nodes.csv) desc="Discharge and volume data for network nodes" ;;
                pathogen_provenance_summary.csv) desc="Pathogen parameter sources and citations" ;;
                run_provenance_summary.csv) desc="Model run configuration and data sources" ;;
                lake_connections.csv) desc="Lake inlet/outlet routing information" ;;
                lake_connection_diagnostics.csv) desc="Lake connectivity validation results" ;;
                hl.csv) desc="Lake polygon and attribute data" ;;
            esac
            cat >> "${scenario_dir}/index.html" << EOF
            <li>
                <a href="data/${f}" class="file-link">
                    <span class="file-icon">📊</span>
                    <div class="file-info">
                        <div class="file-name">${f}</div>
                        <p class="file-desc">${desc}</p>
                    </div>
                    <span class="file-size">${size}</span>
                </a>
            </li>
EOF
        fi
    done

    cat >> "${scenario_dir}/index.html" << EOF
        </ul>
    </div>

    <div class="section">
        <h3>📐 GIS Layers</h3>
        <ul class="file-list">
EOF

    # List GIS files
    for shp in network_points network_rivers network_lakes; do
        if ls "${scenario_dir}/gis/${shp}".shp >/dev/null 2>&1; then
            desc=""
            case "$shp" in
                network_points) desc="Point locations for network nodes" ;;
                network_rivers) desc="River reach line geometries" ;;
                network_lakes) desc="Lake polygon geometries" ;;
            esac
            cat >> "${scenario_dir}/index.html" << EOF
            <li>
                <a href="gis/" class="file-link">
                    <span class="file-icon">📐</span>
                    <div class="file-info">
                        <div class="file-name">${shp}.shp (+ .dbf, .prj, .shx)</div>
                        <p class="file-desc">${desc} — Download folder for all shapefile components</p>
                    </div>
                </a>
            </li>
EOF
        fi
    done

    cat >> "${scenario_dir}/index.html" << EOF
        </ul>
    </div>
</div>

<footer>
    <p>&copy; 2026 ePiE Project | Consortium Presentation May 6th</p>
</footer>

</body>
</html>
EOF
}

# Generate index pages for each scenario
for scenario in "${SCENARIOS[@]}"; do
    IFS=':' read -r name title desc basin pathogen <<< "$scenario"
    scenario_dir="${POSTER_DIR}/${name}"
    echo "Generating index for: ${name}"
    generate_scenario_index "$scenario_dir" "$title" "$desc" "$basin" "$pathogen"
done

echo "Done! Generated index pages for all scenarios."
