# Release Process

This guide describes how to publish a new ePiE code release and the matching data assets used by `scripts/setup-data.sh`.

Large `Inputs/` and `Outputs/` data are not committed to git. Release data assets are packaged as `.tar.gz` archives, uploaded to a GitHub Release, and referenced from `data_manifest.json` with SHA-256 checksums. Patch releases may publish input archives only; in that case users regenerate `Outputs/` by running scenarios locally.

## 1. Prerequisites

Run all commands from the repository root.

```bash
git status --short
gh auth status
command -v Rscript
command -v tar
command -v shasum
command -v jq
```

Before cutting a release, confirm:

- The working tree contains only intentional changes.
- `gh auth status` shows access to `AudLem/ePiE`.
- Required source data exists under `Inputs/`.
- Prebuilt network outputs exist under `Outputs/` only if the release will publish output archives.
- The intended release tag is known, for example `v1.27.0`.

## 2. Prepare the Code Release

Update version metadata:

```bash
$EDITOR Package/DESCRIPTION
```

Set:

- `Version:` to the new package version, for example `1.27.0`.
- `Date:` to the release date.

Run checks:

```bash
Rscript scripts/smoke-test.R
R CMD INSTALL Package
```

Run focused tests for any changed behavior. For example:

```bash
Rscript -e 'pkgload::load_all("Package", quiet = TRUE); testthat::test_file("Package/tests/testthat/test-visualization-spec.R")'
```

Commit the code, documentation, config, and manifest changes:

```bash
git status --short
git add Package/DESCRIPTION data_manifest.json README.md docs scripts .vscode
git commit -m "Prepare v1.27.0 release"
```

Review `git status --short` before committing and avoid adding unrelated local notes, generated reports, or temporary data files.

Create and push the tag:

```bash
git tag -a v1.27.0 -m "ePiE v1.27.0"
git push origin main
git push origin v1.27.0
```

## 3. Build Data Archives

Create a local staging directory outside git-tracked data paths:

```bash
mkdir -p release-assets
rm -f release-assets/*.tar.gz release-assets/SHA256SUMS
```

Build the input archives expected by `scripts/setup-data.sh`:

```bash
tar -czf release-assets/epie_basins_volta.tar.gz -C Inputs/basins volta
tar -czf release-assets/epie_basins_bega.tar.gz -C Inputs/basins bega
tar -czf release-assets/epie_user_data.tar.gz -C Inputs user
```

Only build `epie_outputs_prebuilt.tar.gz` for releases that intentionally publish prebuilt outputs:

```bash
tar -czf release-assets/epie_outputs_prebuilt.tar.gz -C . Outputs
```

The archive layouts must match `data_manifest.json`:

| Archive | Extracted by setup script into | Archive must contain |
|---|---|---|
| `epie_basins_volta.tar.gz` | `Inputs/basins/` | `volta/...` |
| `epie_basins_bega.tar.gz` | `Inputs/basins/` | `bega/...` |
| `epie_user_data.tar.gz` | `Inputs/` | `user/...` |
| `epie_outputs_prebuilt.tar.gz` | repository data root | `Outputs/...` when published |

Compute checksums and sizes:

```bash
for f in release-assets/*.tar.gz; do
  shasum -a 256 "$f"
  bytes=$(wc -c < "$f" | tr -d ' ')
  printf "%s  %s bytes\n" "$(basename "$f")" "$bytes"
done | tee release-assets/SHA256SUMS
```

## 4. Update `data_manifest.json`

Edit `data_manifest.json`:

- Set `version` to the package version, for example `1.27.0`.
- Set `release_tag` to the GitHub release tag, for example `v1.27.0`.
- Set `generated` to the release date.
- Replace each archive `sha256`.
- Replace each archive `size_bytes`.
- Keep each `extract_to` value unchanged unless `scripts/setup-data.sh` is updated at the same time.
- Remove `epie_outputs_prebuilt.tar.gz` from `archives` for input-only releases.

Validate JSON:

```bash
jq . data_manifest.json >/dev/null
```

Commit the manifest if it changed after the first release commit:

```bash
git add data_manifest.json
git commit -m "Update data manifest for v1.27.0"
git push origin main
```

If the tag already exists before the manifest commit, move it only when the release has not been published yet:

```bash
git tag -fa v1.27.0 -m "ePiE v1.27.0"
git push origin v1.27.0 --force
```

Do not move a public tag after users have started downloading it. Create a patch tag instead.

## 5. Create or Update the GitHub Release

> [!IMPORTANT]
> **Pushing a git tag does NOT create a GitHub Release.**
> The `git push origin v1.27.0` command only makes the tag visible in the code history. You **must** run the `gh release create` command below to create the official release object, upload the data archives, and make the release visible on the repository's "Releases" page.

Create the release and upload data assets:

```bash
gh release create v1.27.0 \
  release-assets/epie_basins_volta.tar.gz \
  release-assets/epie_basins_bega.tar.gz \
  release-assets/epie_user_data.tar.gz \
  --title "ePiE v1.27.0" \
  --notes "Release v1.27.0 with updated input data assets. Regenerate Outputs/ locally by running scenarios."
```

If the release already exists, upload or replace assets:

```bash
gh release upload v1.27.0 release-assets/*.tar.gz --clobber
```

Confirm assets are visible:

```bash
gh release view v1.27.0 --web
```

## 6. Verify From a Clean Checkout

Use a fresh checkout or temporary directory:

```bash
tmpdir=$(mktemp -d)
git clone git@github.com:AudLem/ePiE.git "$tmpdir/ePiE"
cd "$tmpdir/ePiE"
git checkout v1.27.0
./scripts/setup-data.sh . v1.27.0
R CMD INSTALL Package
Rscript scripts/smoke-test.R
Rscript scripts/run_all_scenarios.R
```

A release is ready when:

- `setup-data.sh` downloads every archive listed in `data_manifest.json`.
- Every archive checksum passes.
- Required marker files exist in `Inputs/`.
- `R CMD INSTALL Package` succeeds.
- `scripts/smoke-test.R` exits with status `0`.
- Full scenarios regenerate expected `Outputs/`.

## 7. Failure Handling

| Symptom | Action |
|---|---|
| Checksum mismatch | Rebuild the archive, recompute SHA-256, update `data_manifest.json`, re-upload the asset. |
| Missing marker files after extraction | Rebuild the archive with the correct internal directory layout. |
| `setup-data.sh` cannot download an asset | Check the release tag, asset name, repository remote, and GitHub release visibility. |
| `jq` manifest parsing fails | Fix JSON syntax before publishing. |
| Users already downloaded a bad public tag | Create a patch release tag instead of moving the existing tag. |

## 8. Final Checklist

Before announcing the release:

- `git status --short` is clean except for intentionally ignored local data.
- `data_manifest.json` points to the release tag being published.
- GitHub Release contains every `.tar.gz` asset listed in `data_manifest.json`.
- Fresh-checkout verification passed.
- Release notes mention any data/layout changes that affect reproducibility.
