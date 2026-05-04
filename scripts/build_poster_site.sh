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

# Copy and process each scenario
for scenario_pair in "${SCENARIOS[@]}"; do
    output_dir="${scenario_pair%%:*}"
    web_path="${scenario_pair##*:}"

    scenario_dir="${POSTER_DIR}/${web_path}"
    plots_dir="${OUTPUTS_DIR}/${output_dir}/plots"
    output_root_dir="${OUTPUTS_DIR}/${output_dir}"

    echo "Processing: ${output_dir} -> ${web_path}"

    # Create scenario subdirectories
    mkdir -p "${scenario_dir}/data"
    mkdir -p "${scenario_dir}/gis"

    # Copy HTML maps
    if [[ -f "${plots_dir}/interactive_network_map.html" ]]; then
        cp "${plots_dir}/interactive_network_map.html" "${scenario_dir}/"
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

    if [[ -f "${plots_dir}/interactive_tmap_map.html" ]]; then
        cp "${plots_dir}/interactive_tmap_map.html" "${scenario_dir}/"
        sed -i '' 's|interactive_tmap_map_files/|../assets/libs/|g' "${scenario_dir}/interactive_tmap_map.html"
    fi

    # Copy static maps
    for f in static_network_overview.png static_node_types.png static_agglomerations.png static_network_poster.png static_network_poster.pdf; do
        if [[ -f "${plots_dir}/${f}" ]]; then
            cp "${plots_dir}/${f}" "${scenario_dir}/"
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
