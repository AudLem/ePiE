#!/usr/bin/env bash
# setup-data.sh - Download and verify ePiE data archives from GitHub Releases
#
# Usage:
#   ./scripts/setup-data.sh [DATA_ROOT] [RELEASE_TAG]
#
# Arguments:
#   DATA_ROOT    - Root directory for Inputs/ and Outputs/ (default: .)
#   RELEASE_TAG  - GitHub release tag (default: v1.26.0)
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

DATA_ROOT="${1:-$REPO_ROOT}"
RELEASE_TAG="${2:-v1.26.0}"
MANIFEST="$REPO_ROOT/data_manifest.json"

if [ ! -f "$MANIFEST" ]; then
  echo "ERROR: data_manifest.json not found at $MANIFEST"
  exit 1
fi

GITHUB_REPO_URL="$(git -C "$REPO_ROOT" remote get-url origin 2>/dev/null | sed 's|git@github.com:|https://github.com/|' | sed 's|\.git$||')"
if [ -z "$GITHUB_REPO_URL" ]; then
  echo "ERROR: Could not detect GitHub repo URL from git remote"
  exit 1
fi

RELEASE_URL="${GITHUB_REPO_URL}/releases/download/${RELEASE_TAG}"

echo ">>> ePiE Data Setup"
echo "    Repo root:    ${REPO_ROOT}"
echo "    Data root:    ${DATA_ROOT}"
echo "    Release tag:  ${RELEASE_TAG}"
echo "    Download URL: ${RELEASE_URL}"
echo ""

mkdir -p "${DATA_ROOT}/Inputs/basins" \
         "${DATA_ROOT}/Inputs/user" \
         "${DATA_ROOT}/Outputs"

verify_checksum() {
  local file="$1"
  local expected_sha256="$2"
  local actual_sha256
  actual_sha256="$(shasum -a 256 "$file" | awk '{print $1}')"
  if [ "$actual_sha256" != "$expected_sha256" ]; then
    echo "  ERROR: checksum mismatch for $(basename "$file")"
    echo "    expected: $expected_sha256"
    echo "    actual:   $actual_sha256"
    rm -f "$file"
    return 1
  fi
  echo "  Checksum OK"
}

download_archive() {
  local archive_name="$1"
  local extract_dir="$2"
  local expected_sha256="$3"

  local dest_path="${DATA_ROOT}/${extract_dir}"
  local tmp="/tmp/ePie_data_$$_${archive_name}"

  # Check if files are already present
  local archive_prefix="${archive_name%.tar.gz}"
  archive_prefix="${archive_prefix#epie_}"
  case "$archive_prefix" in
    basins_volta)    marker="${dest_path}/volta/af_riv_dry_season.shp" ;;
    basins_bega)     marker="${dest_path}/bega/bega_basin.shp" ;;
    user_data)       marker="${dest_path}/chem_Oldenkamp2018_SI.xlsx" ;;
    outputs_prebuilt) marker="${DATA_ROOT}/Outputs/volta_wet/pts.csv" ;;
    *)                marker="" ;;
  esac

  if [ -n "$marker" ] && [ -f "$marker" ]; then
    echo "  [SKIP] $(basename "$archive_name") — files already present"
    return 0
  fi

  echo "  Downloading ${archive_name}..."
  if ! curl -fSL --progress-bar -o "$tmp" "${RELEASE_URL}/${archive_name}"; then
    echo "  ERROR: failed to download ${archive_name}"
    rm -f "$tmp"
    return 1
  fi

  echo "  Verifying checksum..."
  verify_checksum "$tmp" "$expected_sha256" || return 1

  echo "  Extracting to ${dest_path}..."
  mkdir -p "$dest_path"
  tar xzf "$tmp" -C "$dest_path"
  rm -f "$tmp"

  echo "  Done."
}

echo ">>> Downloading basin and user data..."
echo ""

if command -v jq &>/dev/null; then
  # Parse manifest with jq
  for archive in epie_basins_volta.tar.gz epie_basins_bega.tar.gz epie_user_data.tar.gz epie_outputs_prebuilt.tar.gz; do
    sha256="$(jq -r ".archives.\"$archive\".sha256" "$MANIFEST")"
    extract_to="$(jq -r ".archives.\"$archive\".extract_to" "$MANIFEST")"
    echo "--- $archive ---"
    download_archive "$archive" "$extract_to" "$sha256" || echo "  WARNING: skipped $archive"
    echo ""
  done
else
  # Fallback: hardcode from manifest (works without jq)
  echo "--- epie_basins_volta.tar.gz ---"
  download_archive "epie_basins_volta.tar.gz" "Inputs/basins/" \
    "dcc091b03c282c6d8e8666388ae4ee1ddd095f5373586c6273bc5da381ff0c0f" || echo "  WARNING: skipped"
  echo ""
  echo "--- epie_basins_bega.tar.gz ---"
  download_archive "epie_basins_bega.tar.gz" "Inputs/basins/" \
    "f5fb6db63f36f58fd82cbbe63c196c92108761272e37a7b7f331a627e4d575fb" || echo "  WARNING: skipped"
  echo ""
  echo "--- epie_user_data.tar.gz ---"
  download_archive "epie_user_data.tar.gz" "Inputs/" \
    "5e170d8ffcc78877e0b67bf19735a750109d6168de7287404ff1b7e89e69f315" || echo "  WARNING: skipped"
  echo ""
  echo "--- epie_outputs_prebuilt.tar.gz ---"
  download_archive "epie_outputs_prebuilt.tar.gz" "" \
    "0b2bbfc47f277151c10c5540099f40cd350907caeeb44768048a7e095d4877db" || echo "  WARNING: skipped"
  echo ""
fi

echo ">>> Setup complete."
echo ""
echo "    Data directories:"
echo "      Inputs/basins/volta/   — Volta basin data"
echo "      Inputs/basins/bega/    — Bega basin data"
echo "      Inputs/user/           — Chemical properties, EEF points"
echo "      Outputs/               — Pre-built networks"
echo ""
echo "    Verify by running:"
echo "      Rscript scripts/smoke-test.R"
echo ""
echo "    Baseline data (not bundled) must be downloaded manually:"
echo "      HydroSHEDS  — https://www.hydrosheds.org/"
echo "      FLO1K       — https://doi.org/10.1594/PANGAEA.868758"
echo "      WorldClim   — https://www.worldclim.org/data/worldclim21.html"
echo "      GHS-POP     — https://ghsl.jrc.ec.europa.eu/ghs_pop2019.php"
echo ""
echo "    Place baseline data in Inputs/baselines/ (see docs/GETTING_STARTED.md)."
