#!/usr/bin/env bash
# setup-data.sh - Download and extract ePiE input data
#
# Usage:
#   ./scripts/setup-data.sh [DATA_ROOT] [BASE_URL]
#
# Arguments:
#   DATA_ROOT  - Directory where input data will be stored (default: Inputs)
#   BASE_URL   - Base URL for data archives (default: $DATA_URL env var)
#
# The DATA_URL environment variable overrides BASE_URL.
# Set it before running:
#   export DATA_URL=https://surfdrive.surf.nl/files/...
#   ./scripts/setup-data.sh
#
set -euo pipefail

DATA_ROOT="${1:-Inputs}"
BASE_URL="${DATA_URL:-${2:-}}"

if [ -z "$BASE_URL" ]; then
  echo "ERROR: No data URL configured."
  echo ""
  echo "Usage:"
  echo "  ./scripts/setup-data.sh"
  echo "  ./scripts/setup-data.sh Inputs https://example.com/path/"
  echo ""
  echo "Or set the DATA_URL environment variable:"
  echo "  export DATA_URL=https://your-storage-url/"
  echo "  ./scripts/setup-data.sh"
  exit 1
fi

echo ">>> ePiE Data Setup"
echo "    Target directory: ${DATA_ROOT}/"
echo "    Source URL:       ${BASE_URL}"
echo ""

mkdir -p "${DATA_ROOT}/basins" \
         "${DATA_ROOT}/basins/volta" \
         "${DATA_ROOT}/basins/bega" \
         "${DATA_ROOT}/baselines/hydrosheds" \
         "${DATA_ROOT}/baselines/environmental" \
         "${DATA_ROOT}/user"

# download_and_extract URL DEST_SUBDIR [ARCHIVE_NAME]
download_and_extract() {
  local url="$1"
  local dest="$2"
  local archive="${3:-$(basename "$url")}"
  local tmp="/tmp/ePie_data_$$_$(basename "$url")"

  echo "  Downloading ${archive}..."
  if curl -fSL --progress-bar -o "$tmp" "$url"; then
    echo "  Extracting to ${dest}/..."
    mkdir -p "${DATA_ROOT}/${dest}"
    case "$archive" in
      *.tar.gz|*.tgz) tar xzf "$tmp" -C "${DATA_ROOT}/${dest}" ;;
      *.tar.bz2)      tar xjf "$tmp" -C "${DATA_ROOT}/${dest}" ;;
      *.zip)          unzip -qo "$tmp" -d "${DATA_ROOT}/${dest}" ;;
      *.7z)
        if command -v 7z &>/dev/null; then
          7z x -y -o"${DATA_ROOT}/${dest}" "$tmp"
        else
          echo "  WARNING: 7z not installed, skipping $archive"
        fi
        ;;
      *)              echo "  WARNING: unknown format for $archive, copying as-is"
                       cp "$tmp" "${DATA_ROOT}/${dest}/" ;;
    esac
    rm -f "$tmp"
  else
    echo "  WARNING: failed to download ${archive} (skipping)"
    rm -f "$tmp"
  fi
}

echo ">>> Downloading baselines..."
# download_and_extract "${BASE_URL}/baselines_hydrosheds.tar.gz" "baselines/hydrosheds"
# download_and_extract "${BASE_URL}/baselines_environmental.tar.gz" "baselines/environmental"

echo ">>> Downloading basin data..."
# download_and_extract "${BASE_URL}/basins_volta.tar.gz" "basins/volta"
# download_and_extract "${BASE_URL}/basins_bega.tar.gz" "basins/bega"

echo ">>> Downloading user data (WWTP, chemical properties)..."
# download_and_extract "${BASE_URL}/user_data.tar.gz" "user"

echo ""
echo ">>> Setup complete."
echo "    Verify by running:"
echo "      ls -R ${DATA_ROOT}/"
echo "      R CMD INSTALL Package"
echo ""
echo ">>> To download data, populate the URLs in this script"
echo "    (remove the # comments from the download_and_extract calls)"
echo "    and re-run: ./scripts/setup-data.sh"
