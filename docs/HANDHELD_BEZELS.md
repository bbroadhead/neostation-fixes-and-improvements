# Handheld bezel setup on SteamOS

The local pack is **Handheld Bezels Pack v2.0, version 2.1.0**, by **ci2own**. The author credits and RocketLauncher format are documented on the [LaunchBox release page](https://forums.launchbox-app.com/files/file/2429-handheld-bezels-pack-v20/). The release page and the local PNG/INI pairs provide no redistribution grant. Keep the original images, sidecars and derivative thumbnails local. The app and public AppImage contain the reader and renderer.

From a source checkout, install your existing copy for the active Flatpak RetroArch installation:

```bash
python3 tool/install_handheld_bezels.py assets/images/bezels
```

The tool copies paired assets to `~/.var/app/org.libretro.RetroArch/config/retroarch/neostation-border-packs/handheld-2.1.0/`, preserving their relative paths. It skips macOS metadata and keeps RetroArch settings and the original pack intact. An existing identical installation is accepted. Use `--retroarch-root` to stage an isolated test copy. The installer refuses to overwrite different local files.

Open **Settings → Visual Profiles**, choose the system or configured RetroArch core, and use the border selector. A thumbnail and the display-opening preview identify the current selection. Save applies that choice for the selected scope. Select **None** for native gameplay framing with the current shader preference. The game emulator settings can override a profile for an individual game. The original TV overlay is excluded; a stored ID for it resolves to native framing without a NeoStation overlay.

## Compatibility

The reader matches the system folder, validates the sibling RocketLauncher INI, deduplicates exact PNG bytes per system, and uses the declared region and the image’s actual clear pixels together. It keeps the artwork’s native proportions, normally filling the monitor and cropping only the decoration. Launch-time PNG and CFG files are temporary. Native core/folder/game overrides that would invalidate the viewport continue to take precedence.

The available single-opening catalog covers Game Boy, Game Boy Color, Game Boy Advance, Game Gear, PSP, Atari Lynx, Neo Geo Pocket/Color, WonderSwan/Color, Mega Duck, Pokémon Mini and Watara Supervision. WonderSwan variants are filtered by portrait/landscape where the active geometry is available. The original pack includes Nintendo DS and 3DS shells with two separated transparent windows. NeoStation’s current native RetroArch adapter provides one continuous viewport for fixed combined layouts, so those two pack entries are skipped. Existing compatible single-opening DS/3DS borders remain available. A split-window adapter would need per-core screen placement and touch mapping. Switch and the remaining legacy systems lack a supported native overlay path or system mapping in this integration. Standalone Dolphin retains the previous launch-only resolution profiles.

Use the fixed Steam shortcut path for promoted releases and a separately named AppImage in Downloads for candidate testing. Preserve the last working artifact for rollback.
