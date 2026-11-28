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

## Build 2144 roadmap preview

`/home/deck/Downloads/neostation-linux-x86_64-0.16.1+2144-steamos-roadmap-preview.AppImage` was built from `c87abce91c395fb1f0df9f07e02caa67ae174b56` with `LIBRETRO_ARTWORK=true`. SHA-256 `0816820dbc1d06528bff692fe2cd97adb0cdaeefd10d9e80c2fddfb2af6be423`. It adds the artwork layouts, Guides shortcut, official award badges, frontend connection alerts, GD-ROM hashing fix, compatibility home page, launch preflight and artwork search improvements.

Static analysis passed and all 54 changed Dart files passed the formatting check. The offline suites passed 4,160 Flutter and 478 pure Dart tests. Package extraction, version, native dependencies, and byte comparison of the runner, Dart AOT library and CHD library passed. The package excludes private bezel artwork.

Extract-and-run opened the packaged app in a 1280 × 720 window on a 1280 × 800 isolated X11 display. The copied database remained consistent with 1,413 ROM entries. The final home card opened the RetroAchievements Compatibility page. No physical controller, game launch, or live achievement session was verified for this candidate. No gameplay performance benchmark was run. The fixed 2140 Steam target matched its rollback copy and was kept in place pending physical validation.

### Build 2144 Steam Deck Desktop Mode follow-up

The unchanged 2144 artifact mounted read-only through FUSE and reached the systems screen in the active SteamOS KDE Wayland session at 1280 × 800. An isolated SQLite copy passed `quick_check` and retained all 1,413 library records. A separate Flatpak RetroArch 1.22.2 run loaded the NES test fixture in Nestopia on the Deck's AMD GPU, redirected save and state paths, and captured the expected green fixture at the configured 512 × 384 viewport. The capture covers the viewport only. Full-display bezel alignment and launches initiated by NeoStation still require verification. The active session was Desktop Mode. The 2140 Steam shortcut target remains in place.

### Build 2144 launch and bezel handoff

On the Steam Deck host's isolated 1280 × 800 X11 display, the packaged app launched a synthetic NES game from the home screen into the installed Flatpak RetroArch Nestopia core, then returned to the library after a clean exit. The test wrapper selected the installed Flatpak and redirected saves, states and core options. The bezel run used a separate copied NeoStation profile, a synthetic PNG and RetroArch's generated per-launch configuration. A full-display capture had exactly 307,200 gameplay pixels inside the configured 640 × 480 opening at (320, 160). The bezel occupied the remainder of the display. NeoStation cleaned up its generated configuration and overlay directory after exit. A separate No Border run captured the expected gameplay in RetroArch and generated zero overlay or custom viewport directives. These tests used a virtual display. Gaming Mode and the real handheld bezels still require on-device verification.

### Build 2144 imported GBA bezel

The packaged NeoStation launched the local GBA test game through Flatpak RetroArch and its installed mGBA core on the isolated 1280 × 800 virtual display. The full-display capture showed the ci2own bezel around the game's output. RetroArch reported native 240 × 160 geometry. The generated 354 × 236 viewport at (463, 255) preserved 3:2 and all pixels inside the viewport were transparent in the generated PNG. The game exited cleanly to NeoStation, with saves and states redirected and temporary config and border files removed. The test used OpenGL. The live Vulkan graphics configuration and Gaming Mode still need verification.

## Build 2145 stacked 3DS alignment

`/home/deck/Downloads/neostation-linux-x86_64-0.16.1+2145-steamos-3ds-alignment.AppImage` was built from `8aa21f7aae5194b58ec48d06a43d598fb2b27890` with `LIBRETRO_ARTWORK=true`. SHA-256 `c9e3564e1b51ade7a63c7393e0f1a83737579a6ab9a5371f9bd907519006059a`. Package extraction, version, native dependencies, runner and library comparisons passed. 17 focused tests and static analysis passed.

The 2144 test of the local Retro808 black 3DS XL bezel revealed a width-limited opening stopping at the first matching rectangle and biasing both stacked Citra screens upward. Build 2145 keeps the additional clear rows in the same opening so the combined frame can center vertically. The isolated packaged test at 1280 × 800 mounted normally through FUSE, launched the copied 3DS game in Flatpak Citra, and returned to the library on exit. The viewport remained 392 × 470 at x=445 and moved from y=69 to y=171. Its midpoint was y=406 and the complete viewport was transparent in the overlay. The full-display title screen capture showed both screens inside the bezel. Physical touch, controllers and Gaming Mode remain open. The fixed Steam shortcut still targets 2140.

## Stable baseline rebuild of 2145

The official stable beta tag is already an ancestor of the fork. Rebuilt from a clean detached checkout of `8aa21f7aae5194b58ec48d06a43d598fb2b27890` with Flutter 3.47.9 and `LIBRETRO_ARTWORK=true` in the existing Ubuntu 24.04 build image. The full Flutter run passed 4,311 tests and pure Dart passed 478 tests. Static analysis reported no issues. The rebuild retained the vendored miniz C compiler warning.

`/home/deck/Downloads/neostation-linux-x86_64-0.16.1+2145-steamos-stable-baseline-rebuild.AppImage` has SHA-256 `7f190d336827a64c9fcb4cb512b17d1fc14d00d0fe531a5876b770b8a167b7fa`. The extracted executable, AOT library and CHD plugin matched the clean build bundle. The original and repackaged images each reached the home screen through FUSE in Desktop Mode at 1280 × 800. Both isolated SQLite copies returned `quick_check=ok` and retained 1,413 ROM records. The previous fixed Steam shortcut and the original 2145 image were preserved. The rebuild smoke did not exercise a fresh gameplay session or live scrapers.

## Build 2146 bezel coverage preview

`/home/deck/Downloads/neostation-linux-x86_64-0.16.1+2146-steamos-bezel-coverage-preview.AppImage` contains the source changes in `a82fcef`. Built with `LIBRETRO_ARTWORK=true`. SHA-256 `30c7d3d2b6a0485e76da191d93ab62b93aef399bec97a3c27c023fa206f6a9b5`. Package extraction confirmed the executable, AOT library, CHD plugin, six new overlays and their license match the build inputs. The full Flutter suite passed 4,312 tests, pure Dart passed 478, and the focused bezel and inventory run passed 10. Static analysis reported no issues.

The AppImage reached the home screen in Desktop Mode. The automated pointer injection did not start the GBA fixture in that session. On an isolated 1280 × 800 display, the packaged frontend launched the GBA fixture in Flatpak RetroArch's mGBA core, the emulator rendered six seconds of content, and NeoStation handled the exit. The captured zoomed viewport was 957 × 638 at (162, 81), compared with the 354 × 236 viewport recorded for the original bezel. The full-display capture showed the title screen inside the opening, and all pixels in the generated overlay across the gameplay rectangle had alpha zero. This test used the isolated OpenGL configuration. Gaming Mode, physical touch and physical controller input remain unverified for 2146.

## Build 2147 dual-screen preview

`/home/deck/Downloads/neostation-linux-x86_64-0.16.1+2147-steamos-dual-screen-preview.AppImage` contains `adc3b299e0da0db8620040240dbd71e897881910` with `LIBRETRO_ARTWORK=true`. SHA-256 `dddadc426d2d861ce8220566b61f316b997433595732f47a78cabeab2189902a`. Package comparison verified the app, CHD plugin and both collections of bundled overlays. The full Flutter suite passed 4,313 tests, pure Dart passed 478, and static analysis reported no issues.

On a temporary 1280 × 800 display, the packaged app launched melonDS DS side by side and captured both screens at 1024 × 384, starting at (128, 208). The first fixture attempts reached the DSi NAND error screen. A standard DS cartridge booted and ran six seconds. The DS harness did not confirm frontend return after emulator shutdown. The packaged Citra launch used an isolated large-and-small layout, captured a 1150 × 575 frame at (65, 112), ran 11 seconds and returned to the library. Pixel inspection confirmed transparency across both captured viewports. The tests used isolated OpenGL configurations and did not verify physical touch or Gaming Mode.

## Build 2148 Visual Profile tabs preview

`/home/deck/Downloads/neostation-linux-x86_64-0.16.1+2148-steamos-visual-profile-tabs-preview.AppImage` contains `f7031b7dd263a58cbb7603a9568655334f77381e` with `LIBRETRO_ARTWORK=true`. SHA-256 `a50ab7b4c785cce9e59c21bc956e0f89cf23c232bb0a0872874a3cfa1d82c670`. Package extraction verified the app, overlays, CHD plugin and shader preview images. The full Flutter suite passed 4,315 tests, pure Dart passed 478, and static analysis reported no issues.

The preview reached the home screen through FUSE in Desktop Mode at 1280 × 800. Its isolated SQLite database passed the integrity check and retained 1,413 ROM records. A widget regression exercised the new tabs, shader choice and bezel preservation. The three bundled shader effects were captured from RetroArch 1.22.2 running the original preview scene on GLSL and Slang, then tested as packaged assets. See [shader preview sources](assets/shader_previews/SOURCE.md). On-device bumper interaction and a packaged Visual Profiles dialog walkthrough remain open.

## Build 2149 shader library preview

`/home/deck/Downloads/neostation-linux-x86_64-0.16.1+2149-steamos-shader-library-preview.AppImage` contains `8ea767a0bd13aab42f0f35c7089f73ac3a2fdc1b` with `LIBRETRO_ARTWORK=true`. SHA-256 `03e7a1e7a16af6c6cc62d4f13733f68c679a3c62b50aa2f362db0ae0729ca6b2`. The extracted app, native libraries, overlays and sample assets matched the bundle. It started through FUSE in Desktop Mode at 1280 × 800 and retained 1,413 ROM records in an isolated SQLite copy that passed integrity checks. The full Flutter suite passed 4,318 tests, pure Dart passed 478, and static analysis was clean.

The shared registry discovers the configured RetroArch shader directory, filters to GLSL on OpenGL and Slang on Vulkan or OpenGL Core, and supports searching and filtering by collection folder. The editor reads declared parameter defaults and bounds. Adjustments use a temporary preset referencing the installed original. In RetroArch 1.22.2 the temporary CRT Pi GLSL scanline brightness override changed the rendered scene. Bundled previews cover the three captured presets at their defaults. Arbitrary installed presets and tuned values can have no matching preview. There is no per-preset performance benchmark or physical controller validation in this build.

## Build 2150 per-game Visual Profiles preview

`/home/deck/Downloads/neostation-linux-x86_64-0.16.1+2150-steamos-game-visual-profiles-preview.AppImage` was built with `LIBRETRO_ARTWORK=true` from the app source in `6ea805cf100683c73637f124564085f1c7a4ad04`. SHA-256 `7298e670d4cc8388ab2cf23862347ef3b6b79b53338f594cb05d4e1d4c4e953a`. The full run passed 4,319 Flutter tests and 478 pure Dart tests. The focused rerun against the final source passed 14 tests. Static analysis reported no issues.

Desktop Mode startup retained 1,413 ROMs in the isolated SQLite copy and passed its integrity check. An isolated packaged mGBA launch verified that the game-level None shader wrote `video_shader_enable = "false"` while the system bezel supplied the existing 957 × 638 viewport. The fixture ran six seconds and NeoStation handled the exit. The focused cases cover the opposite inheritance direction, preferences reload and the relationship to older game profiles. Physical controller navigation, live RetroAchievements and Gaming Mode remain open.

## Build 2151 library and achievements preview

The November 27 baseline was verified at `/home/deck/Documents/neostation/neostation-linux-x86_64-0.16.1+2151-steamos-library-and-achievements-preview.AppImage`. It matches the earlier build checksum `3a4e43b57a5e0e13b41437199e4c1e01f04b7b9ab861c2b3050cc351a965f694`. The Steam shortcut targets this filepath. Desktop FUSE startup reached the home screen and the isolated SQLite profile retained 1,413 ROM rows with a clean integrity check. The archived versions live under `/home/deck/Documents/neostation/neostation-archive/`.

## Build 2152 artwork and library preview

`/home/deck/Documents/neostation/neostation-linux-x86_64-0.16.1+2152-steamos-artwork-and-library-preview.AppImage` uses `b6d3807e0f50b30ceadf351f9465bec37b64d3e7` on `feature/steamos-stable-2145-refinements`. It was built with Flutter 3.47.9 and `LIBRETRO_ARTWORK=true` in the Ubuntu 24.04 build container. SHA-256 `204fb1473ca209f6b4b6d0fd21922b6bea62cd24ea2b3d011fc54d75dff5c31b`.

Package extraction verified the runner, native libraries, handheld bezels, and shader previews. It reached the Desktop Mode home screen through FUSE. The isolated database retained 1,413 identical ROM records, 1,122 identical scraped metadata records and its saved collections. The 2151 binary remains available in the archive. Its former location resolves to 2152 for the existing Steam shortcut. Static analysis, 146 focused tests, 4,185 offline Flutter tests and 479 pure Dart tests passed. A second startup through the exact Steam target also reached the home screen. See [development progress](DEVELOPMENT_PROGRESS.md) for physical validation still open and the web artwork provider findings.
