#!/bin/bash
#
# Build Poster Site for Consortium May 2026
#
# This script copies scenario outputs to docs/poster_maps/ and creates
# a phone-friendly index with QR codes for GitHub Pages.
#
# Usage: ./build_poster_site.sh

set -e  # Exit on error

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUTS_DIR="${REPO_ROOT}/Outputs"
POSTER_DIR="${REPO_ROOT}/docs/poster_maps"
ASSETS_DIR="${POSTER_DIR}/assets"
LIBS_DIR="${ASSETS_DIR}/libs"
QR_DIR="${ASSETS_DIR}/qr"
SITE_BASE_URL="${SITE_BASE_URL:-https://audlem.github.io/ePiE/poster_maps}"
REPO_ROOT_PREFIX="${REPO_ROOT%/}/"

# Scenarios to process (output_dir:web_path)
SCENARIOS=(
    "bega_campy:bega_campy"
    "bega_crypto:bega_crypto"
    "bega_giardia:bega_giardia"
    "bega_rota:bega_rota"
    "volta_campy_wet:volta_campy"
    "volta_crypto_wet:volta_crypto"
    "volta_giardia_wet:volta_giardia"
    "volta_rota_wet:volta_rota"
)

echo "=========================================="
echo "Building Poster Site for Consortium 2026"
echo "=========================================="
echo ""

# Create directory structure
echo "Creating directory structure..."
mkdir -p "${POSTER_DIR}"
mkdir -p "${LIBS_DIR}"
mkdir -p "${QR_DIR}"

generate_qr() {
    local url="$1"
    local output_file="$2"

    if ! command -v curl >/dev/null 2>&1; then
        echo "  Warning: curl not found; QR code not updated: ${output_file}"
        return
    fi

    if ! curl --silent --show-error --fail --get \
        --data-urlencode "size=300x300" \
        --data-urlencode "data=${url}" \
        "https://api.qrserver.com/v1/create-qr-code/" \
        --output "${output_file}"; then
        echo "  Warning: QR code not updated for ${url}"
    fi
}

build_gis_index() {
    local scenario_dir="$1"
    local gis_dir="${scenario_dir}/gis"

    if [[ ! -d "${gis_dir}" ]]; then
        return
    fi

    for shp in network_points network_rivers network_lakes; do
        if [[ -f "${gis_dir}/${shp}.shp" ]] && command -v zip >/dev/null 2>&1; then
            (
                cd "${gis_dir}"
                zip -q -j "${shp}_shapefile.zip" "${shp}".*
            )
        fi
    done

    cat > "${gis_dir}/index.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>GIS Downloads | ePiE Poster Site</title>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
            background: #f4f7f6;
            color: #2b2b2b;
            line-height: 1.6;
            margin: 0;
            padding: 2rem 1rem;
        }
        main {
            max-width: 900px;
            margin: 0 auto;
            background: white;
            border-radius: 8px;
            padding: 1.5rem;
            box-shadow: 0 2px 10px rgba(0,0,0,0.06);
        }
        h1 {
            color: #2171b5;
            margin-top: 0;
        }
        a {
            color: #2171b5;
            font-weight: 600;
        }
        .layer {
            border-top: 1px solid #e6e6e6;
            padding: 1rem 0;
        }
        .layer h2 {
            font-size: 1.1rem;
            margin: 0 0 0.4rem;
        }
        .components {
            display: flex;
            flex-wrap: wrap;
            gap: 0.5rem;
            margin-top: 0.5rem;
        }
        .components a {
            background: #eef5fb;
            border-radius: 4px;
            padding: 0.25rem 0.5rem;
            text-decoration: none;
        }
    </style>
</head>
<body>
<main>
    <p><a href="../index.html">Back to scenario page</a></p>
    <h1>GIS Downloads</h1>
    <p>Download the ZIP files for QGIS or ArcGIS. Each ZIP contains the required shapefile components.</p>
EOF

    for shp in network_points network_rivers network_lakes; do
        if [[ -f "${gis_dir}/${shp}.shp" ]]; then
            case "$shp" in
                network_points) desc="Point locations for network nodes." ;;
                network_rivers) desc="River reach line geometries." ;;
                network_lakes) desc="Lake polygon geometries." ;;
            esac

            cat >> "${gis_dir}/index.html" << EOF
    <section class="layer">
        <h2>${shp}</h2>
        <p>${desc}</p>
EOF

            if [[ -f "${gis_dir}/${shp}_shapefile.zip" ]]; then
                cat >> "${gis_dir}/index.html" << EOF
        <p><a href="${shp}_shapefile.zip">Download ${shp}_shapefile.zip</a></p>
EOF
            fi

            cat >> "${gis_dir}/index.html" << EOF
        <div class="components">
EOF

            for ext in shp dbf shx prj cpg; do
                if [[ -f "${gis_dir}/${shp}.${ext}" ]]; then
                    cat >> "${gis_dir}/index.html" << EOF
            <a href="${shp}.${ext}">${shp}.${ext}</a>
EOF
                fi
            done

            cat >> "${gis_dir}/index.html" << EOF
        </div>
    </section>
EOF
        fi
    done

    cat >> "${gis_dir}/index.html" << 'EOF'
</main>
</body>
</html>
EOF
}

normalize_html_widget_frontmatter() {
    local html_file="$1"

    if [[ ! -f "${html_file}" ]]; then
        return
    fi

    if [[ "$(sed -n '1p' "${html_file}")" != "---" ]]; then
        return
    fi

    local tmp_file="${html_file}.tmp"
    awk '
        BEGIN {
            state = "front"
            in_header = 0
            in_head = 0
            header = ""
            head = ""
            body = ""
        }
        NR == 1 && $0 == "---" {
            next
        }
        state == "front" {
            if ($0 == "---") {
                state = "body"
                next
            }
            if ($0 == "header-include: |") {
                in_header = 1
                in_head = 0
                next
            }
            if ($0 == "head: |") {
                in_header = 0
                in_head = 1
                next
            }
            if ($0 ~ /^[^[:space:]].*:/) {
                in_header = 0
                in_head = 0
                next
            }
            if (in_header) {
                sub(/^  /, "")
                header = header $0 "\n"
                next
            }
            if (in_head) {
                sub(/^  /, "")
                head = head $0 "\n"
                next
            }
            next
        }
        state == "body" {
            body = body $0 "\n"
        }
        END {
            print "<!DOCTYPE html>"
            print "<html lang=\"en\">"
            print "<head>"
            print "<meta charset=\"utf-8\"/>"
            printf "%s", head
            printf "%s", header
            print "<title>leaflet</title>"
            print "</head>"
            print "<body>"
            printf "%s", body
            print "</body>"
            print "</html>"
        }
    ' "${html_file}" > "${tmp_file}"
    mv "${tmp_file}" "${html_file}"
}

# Copy and process each scenario
for scenario_pair in "${SCENARIOS[@]}"; do
    output_dir="${scenario_pair%%:*}"
    web_path="${scenario_pair##*:}"

    scenario_dir="${POSTER_DIR}/${web_path}"
    plots_dir="${OUTPUTS_DIR}/${output_dir}/plots"
    output_root_dir="${OUTPUTS_DIR}/${output_dir}"
    network_output_dir="${output_root_dir}"
    if [[ "${output_dir}" == bega_* ]]; then
        network_output_dir="${OUTPUTS_DIR}/bega"
    elif [[ "${output_dir}" == volta_*_wet ]]; then
        network_output_dir="${OUTPUTS_DIR}/volta_wet"
    fi
    network_plots_dir="${network_output_dir}/plots"

    echo "Processing: ${output_dir} -> ${web_path}"

    # Create scenario subdirectories
    mkdir -p "${scenario_dir}/data"
    mkdir -p "${scenario_dir}/gis"

    # Copy HTML maps
    interactive_network_map="${plots_dir}/interactive_network_map.html"
    if [[ ! -f "${interactive_network_map}" && -f "${network_plots_dir}/interactive_network_map.html" ]]; then
        interactive_network_map="${network_plots_dir}/interactive_network_map.html"
    fi
    if [[ -f "${interactive_network_map}" ]]; then
        cp "${interactive_network_map}" "${scenario_dir}/"
        sed -i '' 's|interactive_network_map_files/|../assets/libs/|g' "${scenario_dir}/interactive_network_map.html"
    fi

    if [[ -f "${plots_dir}/concentration_map.html" ]]; then
        cp "${plots_dir}/concentration_map.html" "${scenario_dir}/"
        sed -i '' 's|concentration_map_files/|../assets/libs/|g' "${scenario_dir}/concentration_map.html"
    fi

    if [[ -f "${plots_dir}/concentration_segments_map.html" ]]; then
        cp "${plots_dir}/concentration_segments_map.html" "${scenario_dir}/"
        sed -i '' 's|concentration_segments_map_files/|../assets/libs/|g' "${scenario_dir}/concentration_segments_map.html"
    fi

    interactive_tmap_map="${plots_dir}/interactive_tmap_map.html"
    if [[ ! -f "${interactive_tmap_map}" && -f "${network_plots_dir}/interactive_tmap_map.html" ]]; then
        interactive_tmap_map="${network_plots_dir}/interactive_tmap_map.html"
    fi
    if [[ -f "${interactive_tmap_map}" ]]; then
        cp "${interactive_tmap_map}" "${scenario_dir}/"
        sed -i '' 's|interactive_tmap_map_files/|../assets/libs/|g' "${scenario_dir}/interactive_tmap_map.html"
        normalize_html_widget_frontmatter "${scenario_dir}/interactive_tmap_map.html"
    fi

    # Copy static maps
    for f in static_network_overview.png static_node_types.png static_agglomerations.png static_network_poster.png static_network_poster.pdf; do
        source_plot="${plots_dir}/${f}"
        if [[ ! -f "${source_plot}" && -f "${network_plots_dir}/${f}" ]]; then
            source_plot="${network_plots_dir}/${f}"
        fi
        if [[ -f "${source_plot}" ]]; then
            cp "${source_plot}" "${scenario_dir}/"
        fi
    done

    # Copy data tables
    for f in pts.csv simulation_results.csv hydrology_nodes.csv pathogen_provenance_summary.csv \
              run_provenance_summary.csv lake_connections.csv lake_connection_diagnostics.csv hl.csv; do
        if [[ -f "${output_root_dir}/${f}" ]]; then
            cp "${output_root_dir}/${f}" "${scenario_dir}/data/"
            if [[ "${f}" == "run_provenance_summary.csv" ]]; then
                sed -i '' "s|${REPO_ROOT_PREFIX}||g" "${scenario_dir}/data/${f}"
            fi
        fi
    done

    # Copy shapefiles
    for shp in network_points network_rivers network_lakes; do
        if ls "${output_root_dir}/${shp}".* >/dev/null 2>&1; then
            cp "${output_root_dir}/${shp}".* "${scenario_dir}/gis/"
        fi
    done

    build_gis_index "${scenario_dir}"
    generate_qr "${SITE_BASE_URL}/${web_path}/" "${QR_DIR}/${web_path}_qr.png"
done

echo ""
echo "Generating QR code for main poster page..."
generate_qr "${SITE_BASE_URL}/" "${QR_DIR}/index_qr.png"

# Deduplicate Leaflet assets
echo ""
echo "Deduplicating Leaflet library assets..."
# Use the first scenario's lib files as the source
FIRST_SCENARIO=$(ls "${OUTPUTS_DIR}" | head -1)
for d in "${OUTPUTS_DIR}/${FIRST_SCENARIO}/plots/"*_files; do
    if [[ -d "$d" ]]; then
        cp -r "$d/"* "${LIBS_DIR}/"
        echo "  Copied shared libs from $(basename "$d")"
    fi
done

echo ""
echo "=========================================="
echo "Build complete!"
echo "=========================================="
echo "Site location: ${POSTER_DIR}/"
echo ""
echo "Next steps:"
echo "  1. Review the generated site"
echo "  2. Set GitHub Pages source to 'docs/' folder"
echo "  3. Push to GitHub"
echo ""
