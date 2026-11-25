# Handheld bezel setup on SteamOS

The local pack is **Handheld Bezels Pack v2.0, version 2.1.0**, by **ci2own**. The author credits and RocketLauncher format are documented on the [LaunchBox release page](https://forums.launchbox-app.com/files/file/2429-handheld-bezels-pack-v20/). The release page and the local PNG/INI pairs provide no redistribution grant. Keep the original images, sidecars and derivative thumbnails local. The app and public AppImage contain the reader and renderer.

From a source checkout, install your existing copy for the active Flatpak RetroArch installation:

```bash
python3 tool/install_handheld_bezels.py assets/images/bezels
```

The tool copies paired assets to `~/.var/app/org.libretro.RetroArch/config/retroarch/neostation-border-packs/handheld-2.1.0/`, preserving their relative paths. It skips macOS metadata and keeps RetroArch settings and the original pack intact. An existing identical installation is accepted. Use `--retroarch-root` to stage an isolated test copy. The installer refuses to overwrite different local files.

Open **Settings → Visual Profiles**, choose the system or configured RetroArch core, and use the border selector. A thumbnail and the display-opening preview identify the current selection. Save applies that choice for the selected scope. Select **None** for native gameplay framing with the current shader preference. The game emulator settings can override a profile for an individual game. The original TV overlay is excluded; a stored ID for it resolves to native framing without a NeoStation overlay.

## Compatibility

The reader matches the system folder, validates the sibling RocketLauncher INI, deduplicates exact PNG bytes per system, and uses the declared region and the image’s actual clear pixels together. It keeps the artwork’s native proportions, normally filling the monitor and cropping only the decoration. Launch-time PNG and CFG files are temporary. Since build 2142, an explicit border selection applies after simple native core, folder and game overrides for that session. Native configurations involving includes, rotation or a video-driver change keep their layout. None keeps the native override behavior.

The available single-opening catalog covers Game Boy, Game Boy Color, Game Boy Advance, Game Gear, PSP, Atari Lynx, Neo Geo Pocket/Color, WonderSwan/Color, Mega Duck, Pokémon Mini and Watara Supervision. WonderSwan variants are filtered by portrait/landscape where the active geometry is available. Existing compatible single-opening DS and 3DS borders remain available. Switch and the remaining legacy systems lack a supported native overlay path or system mapping in this integration. Standalone Dolphin retains the previous launch-only resolution profiles.

### Nintendo DS split-window shell

Build 2143 fits the pack’s two DS openings separately when the selected core is **melonDS DS** with one fixed **Top/Bottom** or **Bottom/Top** layout and a compatible gap. The local artwork passed validation at 1280 × 800 with a **100-pixel gap**. The border picker uses the active core or game options. For a per-core profile, set the layout and gap in RetroArch’s native core options before opening the picker. Size and position are fixed for this shell so neither game screen drifts under the hinge. NeoStation reads the options and leaves them on disk unchanged. Layout cycling, incompatible gaps, and unsupported cores keep the native presentation. On-device touch and gameplay validation remain open. [melonDS DS core documentation](https://docs.libretro.com/library/melonds_ds/)

The pack’s 3DS shell still requires independent screen placement. The documented Citra libretro core offers fixed layouts without a gap adjustment. NeoStation skips this shell to prevent occlusion. [Citra core options](https://docs.libretro.com/library/citra/#core-options)

Use the fixed Steam shortcut path for promoted releases and a separately named AppImage in Downloads for candidate testing. Preserve the last working artifact for rollback.
