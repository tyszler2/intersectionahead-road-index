# Data ↔ App Changelog

## Active Baseline
- Date: 2026-02-17
- Pack Version: v2
- Release ID: pending-update
- Regions: nyc_tristate, new_jersey, greater_philadelphia, northern_delaware, cupertino
- App Branch/Commit: working tree
- Notes: Raw GPS authoritative ON is active baseline; Cupertino region bounds expanded in app config.

---

## Entries

### 2026-02-17 03:40 ET — [APP] Manifest-driven region bootstrap + safe fallback
- Changed:
  - Integrated manifest fetch/decode at app startup and replaced hard-coded runtime region wiring with manifest-derived regions when available.
  - Kept hard-coded region list as explicit fallback when manifest is missing/invalid.
  - Added resolver logic to convert manifest shards into `RoadIndexRegion` bounds/base URLs.
- Files changed:
  - `Sources/EngineAlpha/RoadIndexManifest.swift`
  - `Sources/EngineAlpha/RoadIndexRegionResolver.swift` (new)
  - `Sources/EngineAlpha/RoadIndexEngine.swift`
  - `IntersectionAheadApp/IntersectionAheadApp/EngineViewModel.swift`
  - `Tests/EngineAlphaTests/EngineAlphaTests.swift`
- Verification run:
  - `xcodebuild -project /Users/sam/Documents/Codex/IntersectionAheadApp/IntersectionAheadApp.xcodeproj -scheme IntersectionAheadApp -sdk iphonesimulator -configuration Debug -derivedDataPath /tmp/IntersectionAheadDerivedData build` ✅
  - Unit tests added for manifest decode success/failure and resolver fallback path.
- Blockers:
  - none

### 2026-02-17 03:15 ET — [DATA] Handoff to App Master (Data pipeline phase complete)
- Changed:
  - Data Master implementation for automation scaffold is complete for this phase:
    - profile config (`tools/config/coverage_profiles.yaml`)
    - build/verify/publish scripts (`tools/scripts/build_profile.sh`, `tools/scripts/verify_release.sh`, `tools/scripts/publish_release.sh`)
    - CI workflows (`.github/workflows/build_publish_data.yml`, `.github/workflows/verify_data_integrity.yml`)
    - additive app-facing manifest contract (`Sources/EngineAlpha/RoadIndexManifest.swift`)
- Why:
  - Prevent duplicate effort and separate ownership cleanly between data pipeline and app integration.
- App impact:
  - required
- Required app action (if any):
  - App Master now owns follow-on work only:
    - consume `road-index/manifest.json`
    - replace hard-coded region config with manifest-derived config (with safe fallback)
    - add manifest decode/fallback tests
  - App Master must not rebuild data packs or edit data pipeline scripts/workflows for this handoff.
- Verification:
  - Data scaffold files are present and changelog entries updated.
- Release refs:
  - local workspace handoff marker on 2026-02-17

### 2026-02-17 02:55 ET — [DATA] Automated profile pipeline + manifest contract scaffolded
- Changed:
  - Added profile config: `tools/config/coverage_profiles.yaml` with `pilot_northeast` and `north_america_full`.
  - Added orchestration script: `tools/scripts/build_profile.sh`.
    - Builds shard(s) from profile.
    - Publishes unified `road-index/<release_region_id>/...` plus optional legacy shard region paths.
    - Generates additive release files: `manifest.json`, `build_report.json`.
  - Added integrity gate script: `tools/scripts/verify_release.sh`.
    - Checks seam tile presence, binary header magic, sample decode via `RoadIndexCLI`, optional remote header checks.
  - Added publish script: `tools/scripts/publish_release.sh`.
    - Syncs `road-index` payload into target publish repo and writes `road-index/manifest.json`.
  - Added GitHub Actions workflows:
    - `.github/workflows/build_publish_data.yml` (nightly + manual).
    - `.github/workflows/verify_data_integrity.yml` (PR/manual verification).
  - Added app-facing manifest contract model:
    - `Sources/EngineAlpha/RoadIndexManifest.swift` (`RoadIndexReleaseManifest` + reader).
- Why:
  - Move from ad-hoc region rebuilds to reproducible profile-driven data releases with a single app-facing region assumption path.
- App impact:
  - additive
- Required app action (if any):
  - App thread can begin consuming `road-index/manifest.json` and migrate region config from hard-coded list to generated metadata.
- Verification:
  - Script syntax checks pass (`bash -n` for new scripts).
  - Scoped profile build executed successfully (`pilot_northeast`, `northern_delaware` shard) and emitted release artifacts under `/tmp/ia_release_test/...`.
  - During full pilot test, two source-path issues were discovered and corrected in profile config:
    - `nyc_tristate` source path.
    - `greater_philadelphia` source switched to `source-pbf/pennsylvania-latest.osm.pbf`.
- Release refs:
  - local workspace implementation on 2026-02-17

### 2026-02-17 — [DATA] Current baseline snapshot (Data Master)
- Changed:
  - Revalidated pipeline baseline in one place: builder script, v2 pack schema, region inventory, and publish checks.
  - Confirmed v2 metadata paths are active in builder/reader for `junctions` and `services`.
  - Confirmed current local coverage inventory:
    - `road-index`: `cupertino` (147 chunks), `nyc_tristate` (100 chunks)
    - `road-index-v2`: `cupertino` (147), `nyc_tristate` (100), `new_jersey` (38), `greater_philadelphia` (18), `northern_delaware` (4)
- Why:
  - Keep data decisions reproducible and aligned with app-visible behavior before next publish wave.
- App impact:
  - Baseline only (no runtime behavior change from this entry alone).
- Verification:
  - Inventory from local chunk counts and schema check (`IAR1` payload v2 with junction/service counts).
- Release refs:
  - local workspace snapshot on 2026-02-17

### 2026-02-17 01:20 ET — [DATA] Cupertino coverage expanded (150-mile radius bbox)
- Changed:
  - Rebuilt `cupertino` region pack with expanded bbox.
  - Synced rebuilt chunks into local `road-index/cupertino`.
  - Published updated `cupertino` chunks to `intersectionahead-road-index` repo.
- Why:
  - Simulator freeway scenarios were leaving the prior Cupertino bounds.
- App impact:
  - required
- Required app action (if any):
  - App region bounds for `cupertino` must match the new bbox.
  - Reinstall/refresh app and clear old cached chunks if stale coverage persists.
- Verification:
  - Cupertino chunk files exist in expanded x/y range at z10.
  - App build succeeds after bbox update.
- Release refs:
  - repo/commit: `tyszler2/intersectionahead-road-index` @ `59c2ddb`
  - manifest/checksum: not yet formalized

### 2026-02-17 01:20 ET — [APP] Matcher/UI updates for NEXT + services
- Changed:
  - Added pull-over mode behavior and dual-side NEXT display logic.
  - Added conditions so Left/Right shows only when both sides exist and differ by name.
  - Updated Cupertino bounds in app region config.
- Why:
  - Improve NEXT clarity and freeway service usefulness.
- Data dependency:
  - partial
- Required data action (if any):
  - Continue improving junction/service coverage consistency for labels and services.
- Verification:
  - iOS simulator build succeeded.

---

## Later (Tangent Parking Lot)
- [ ] Formalize release manifest/checksum file for each pack publish.
- [ ] Decide whether ON labels should always combine `ref + name` at schema level.
- [ ] Add lightweight overlap-resolution policy for region boundaries.
- [ ] Promote `build_report.json` regression metrics from placeholders to computed fill-rate metrics (named segment rate, junction ref fill-rate, service counts by kind).

---

## Next 3 Concrete Data Actions

### 1) Rebuild `nyc_tristate` v2 pack from source to improve route ref/name fill where OSM already has tags
- Command:
```bash
/Users/sam/Documents/Codex/IntersectionAhead/tools/scripts/build_region.sh \
  nyc_tristate nyc-tristate-merged.osm.pbf \
  -75.6 39.7 -71.5 42.6 road-index-v2
```
- Expected app-visible impact:
  - Better ON-road label consistency from fresh extraction (`name`, `name:en`, fallback `ref`) and fresher exit metadata in updated tiles.

### 2) Improve border reliability immediately by seeding overlap tiles into the active `nyc_tristate` serving path
- Command:
```bash
rsync -a /Users/sam/Documents/Codex/IntersectionAhead/road-index-v2/new_jersey/ \
  /Users/sam/Documents/Codex/IntersectionAhead/road-index/nyc_tristate/
rsync -a /Users/sam/Documents/Codex/IntersectionAhead/road-index-v2/greater_philadelphia/ \
  /Users/sam/Documents/Codex/IntersectionAhead/road-index/nyc_tristate/
rsync -a /Users/sam/Documents/Codex/IntersectionAhead/road-index-v2/northern_delaware/ \
  /Users/sam/Documents/Codex/IntersectionAhead/road-index/nyc_tristate/
```
- Expected app-visible impact:
  - Fewer missing-NEXT/service moments near NJ/PA/DE seams before full multi-region app rollout.

### 3) Run publish integrity checks on representative z10 seam tiles before app QA
- Command:
```bash
/bin/zsh -lc 'for region in nyc_tristate new_jersey greater_philadelphia northern_delaware; do
  echo "== $region ==";
  curl -I -s "https://tyszler2.github.io/intersectionahead-road-index/road-index/$region/10/298/387.iarc" \
    | rg -n "HTTP/|content-length|last-modified|etag";
done'
```
- Expected app-visible impact:
  - Early detection of missing/stale chunks that otherwise surface as silent transition failures in drive tests.
