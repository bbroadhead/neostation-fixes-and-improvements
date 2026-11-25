# AppImage build history

Artifact filenames share the prefix `neostation-linux-x86_64-0.16.1+` and suffix `.AppImage`. Preview filenames and local binaries record packaging outcomes. Exact commits require build evidence, especially on dirty worktrees. Older test filenames were reused or copied, so the suffix alone is insufficient to establish identity.

| Build or suffix | Associated behavior and evidence |
|---|---|
| 2134 upstream | Official stable baseline. Historical original retained in archives. |
| 2134 screenscraper-fix | Safe credential/error handling and bounded retries. Startup smoke and mocked tests. Approved developer credentials required for local ScreenScraper. |
| 2134 libretro-artwork; libretro-chd-fix; library-scraper | Public Libretro images, CHD startup correction, full-library scraper entry and Libretro metadata. Historical alternate filenames could contain byte-identical packages. Isolated boot and a live EarthBound sample verified. |
| 2134 deck-library-preview; ra-compatibility-preview | Cover-first grid, Libretro scrape/import, editable search title, hash compatibility/details. Startup tested. |
| 2134 artwork-overrides-preview; libretro-gallery-preview; rom-dedup / rom-dedup-preview; ra-artwork-preview | Manual path/category persistence and reset, remote Libretro gallery, duplicate-byte scan protection and hash-verified RA media. Startup and targeted regressions recorded in session log. |
| 2134 improvements-test / improvements-r2-test; artwork-priority-test / artwork-priority-r2-test | Composite carousel, staged provider media, metadata, incompatible collection, Desktop shoulder keys and prioritized SteamGridDB/RA/Libretro with provenance. R2 builds startup verified. Earlier variants retained in archive. |
| 2134 batch-scraping-test; compatibility-review-test | Batch counters/failures/missing-only retry, incompatibility reason filters and ROM details. Startup verified. |
| 2134 artwork-gallery-test; favorites-divider-test; steamgriddb-key-test | Larger icon/multi-provider picker with Logo, favorites divider and persistent SteamGridDB key entry. Historical startup checks. |
| 2134 provider-parity-test; screenscraper-api-test; arduboy-home-test; collections-back-test; scraper-and-rom-scan-test | Shared matching and catalogue zero-sets, persistent ScreenScraper credentials, Arduboy home card, Back button, regional title/logo fixes and in-place imports. Historical startup and offline tests. |
| 2134 scraper-import-test / scraper-import-r2-test; steamos-library-recovery | Archived custom scraper/import and recovery snapshots. Recovery was authoritative for installed behavior during Nov 22 integration. Its stripped binary limits source attribution. |
| 2135 steamos-integration-preview | Stable integration ending at `13488ff`. Recovered hacks assets, NeoAssets-first at that stage, targeted import/recheck and GameCube hashes. Normal FUSE, isolated library retention and prior build backup verified. Present in Downloads and package directories. |
| 2136 steamos-steamgriddb | `bf0af2b`, current copy under `release/archive/`. Restored auth feedback and automatic priority. Packaged dummy-key and UI checked. CDN variant still failed. |
| 2137 steamos-steamgriddb | `289915e` per packaging logs/reflog, no embedded commit ID. Live key success, provider results and saved cover on isolated profile. Last shortcut target found in Nov 23 audit. |
| 2138 steamos-visual-profiles-preview | First packaged Phase 1 preview, dirty tree on `289915e`. Aggregate systems incorrectly listed as hardware profiles. |
| 2139 steamos-visual-profiles-preview | Filtered aggregate views and Search, extracted and launched isolated profile, opened Game Boy editor. |
| 2140 steamos-visual-profiles-preview | Latest preview in `release/`. Fixed GBA viewport bias and Collections Back. Historical packaged UI confirmed Back. GBA Vulkan screenshot black. Based on `289915e` plus dirty source. |

The November 24 consolidation verified the 2140 SHA-256 sidecar and read its SquashFS listing, including AppRun, desktop entry, Flutter assets and libapp.so. The package listing did not establish that the newly identified bezel directory was bundled. No build, emulator launch or Steam shortcut change was made in this audit.

Use one fixed filename and path for the current launchable AppImage. Keep the existing Steam shortcut target as the stable path unless the owner explicitly chooses another one. Build and verify each candidate separately, archive the previous artifact under a versioned filename with its checksum, then atomically replace the file at the stable path on the same filesystem. Record each build’s source SHA and checksum. Failed or unfinished previews stay separate from the current launchable AppImage. Keep rollback copies under `~/Downloads/neostation-archive/` or the applicable release archive. Native dependency reuse was used for historical builds where the host lacked the full toolchain.

Build 2140 SHA-256 `234ef6a20426af7dff78a36c3ea4b42c470c3ea7188487ff7be14ef9095cedec`.

## Build 2141 handheld bezels

The descriptive candidate is `~/Downloads/neostation-linux-x86_64-0.16.1+2141-steamos-handheld-bezels.AppImage`. Source commit `06fbdce` records the recovered Visual Profiles code and the new local pack integration. Built with `LIBRETRO_ARTWORK=true` and verified version, extraction, launcher/shared-library binary parity and native dependencies. SHA-256 `7b76fd104ea1459cff72f638707d2e4fcb4ff0027894fb89031fa4044f0539fc`. The package excludes the private artwork.

The Steam shortcut target was rechecked and points to the existing 2140 path. Builds 2137 and 2140 were backed up under `~/Downloads/neostation-archive/` and compared byte-for-byte. The candidate started on the isolated desktop display, retained all 1,413 records in the current library snapshot, and showed the imported GBA thumbnail and large preview. The selection survived an app restart. The packaged picker returned to None on selection. Physical gameplay alignment, controller behavior, save/resume and Hardcore verification remain open, so the shortcut still launches 2140.

## Build 2142 native border overrides

`~/Downloads/neostation-linux-x86_64-0.16.1+2142-steamos-native-border-overrides.AppImage` uses source commit `9bc1ed3` with `LIBRETRO_ARTWORK=true`. SHA-256 `28a5fc354b2de5eb1c79d7c436353f2f8d4f360c5595cd0c473b83d2af414750`. Package extraction, checksum, dependencies and isolated library startup passed. Steam still targets build 2140 at the same path pending hardware validation.

## Build 2143 DS split-window bezel

`~/Downloads/neostation-linux-x86_64-0.16.1+2143-steamos-ds-split-bezel.AppImage` uses `e68ecbd` with `LIBRETRO_ARTWORK=true`. SHA-256 `812a742714baf7b06348f12866fe54cc698b7376014f6ac0ba58bb8f246d0ec1`. Packaging verified extraction, checksum, dependencies and isolated startup. The existing Steam target remained at 2140 pending physical validation.
