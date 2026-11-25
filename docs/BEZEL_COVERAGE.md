# Bezel coverage at 1280 × 800

The audit rendered the installed RetroArch and local handheld collections together with the bundled GermanTacos artwork. It checked all 218 bundled system definitions using a clear opening and a complete aspect-correct viewport. Counts include separate ROM-hack definitions and exclude None. A system with multiple layouts may have fewer choices in its active layout. Geometry results do not measure hardware performance or touch input.

## Multiple compatible choices (42 definitions)

`2600-hacks` `2600` `3ds` `duck-hacks` `duck` `gb-hacks` `gb` `gba-hacks` `gba` `gbc-hacks` `gbc` `genesis` `gg-hacks` `gg` `lynx-hacks` `lynx` `mini-hacks` `mini` `n64-hacks` `n64` `nes-hacks` `nes` `ngp-hacks` `ngp` `ngpc-hacks` `ngpc` `pce-hacks` `pce` `ps1-hacks` `ps1` `psp-hacks` `psp` `sms-hacks` `sms` `snes-hacks` `snes` `ws-hacks` `ws` `wsc-hacks` `wsc` `wsv-hacks` `wsv`

## One compatible choice (40 definitions)

`32x-hacks` `32x` `3do-hacks` `3do` `5200-hacks` `5200` `7800-hacks` `7800` `chf-hacks` `chf` `dc-hacks` `dc` `ds-hacks` `ds` `fc-hacks` `fc` `fds-hacks` `fds` `intv-hacks` `intv` `jag-hacks` `jag` `jagcd-hacks` `jagcd` `mark3-hacks` `mark3` `md-hacks` `md` `neogeo-hacks` `neogeo` `pccd-hacks` `pccd` `pcfx-hacks` `pcfx` `sat-hacks` `sat` `scd-hacks` `scd` `sg1k-hacks` `sg1k`

## No compatible choice (136 definitions)

`3ds-hacks` `a2-hacks` `a2` `a2001-hacks` `a2001` `all` `amazon` `amiga-hacks` `amiga` `android` `arc-hacks` `arc` `ard-hacks` `ard` `ast-hacks` `ast` `aw-hacks` `aw` `bbcmicro-hacks` `bbcmicro` `c64-hacks` `c64` `cdi-hacks` `cdi` `collections` `cpc-hacks` `cpc` `cps1-hacks` `cps1` `cps2-hacks` `cps2` `cps3-hacks` `cps3` `cv-hacks` `cv` `dos-hacks` `dos` `epic` `favorites` `fbneo-hacks` `fbneo` `gc-hacks` `gc` `gen-hacks` `gog` `gw-hacks` `gw` `mame` `mcd-hacks` `mcd` `mo2-hacks` `mo2` `model3-hacks` `model3` `msx-hacks` `msx` `music` `naomi-hacks` `naomi` `naomi2-hacks` `naomi2` `naomigd-hacks` `naomigd` `ngcd-hacks` `ngcd` `palm-hacks` `palm` `pc88-hacks` `pc88` `pc98-hacks` `pc98` `pet-hacks` `pet` `pico-hacks` `pico` `pico8-hacks` `pico8` `plus4-hacks` `plus4` `ports-hacks` `ports` `ps2-hacks` `ps2` `ps3-hacks` `ps3` `pspminis-hacks` `pspminis` `rpgmaker` `satellaview-hacks` `satellaview` `scummvm` `sfc-hacks` `sfc` `sharpx68000-hacks` `sharpx68000` `steam` `switch-hacks` `switch` `tg16-hacks` `tg16` `tgcd-hacks` `tgcd` `tic80-hacks` `tic80` `triforce-hacks` `triforce` `uze-hacks` `uze` `vb-hacks` `vb` `vc4k-hacks` `vc4k` `vect-hacks` `vect` `vic20-hacks` `vic20` `vita-hacks` `vita` `wasm4-hacks` `wasm4` `wii-hacks` `wii` `wiiu-hacks` `wiiu` `windows-hacks` `windows` `x1-hacks` `x1` `xbox-hacks` `xbox` `xbox360-hacks` `xbox360` `zx81-hacks` `zx81` `zxspectrum-hacks` `zxspectrum`

## Geometry failures

The listed assets failed for at least one audited layout. Nintendo DS passed with the dedicated 100-pixel-gap layout. The 3DS result concerns the separate two-opening ci2own file. The locally imported contiguous 3DS artwork has a complete calculated viewport, with prior runtime evidence for stacked Citra only.

- **3ds** — Bezel Nintendo 3DS.png
- **ds** — Bezel Nintendo DS.png
- **gb** — ctr/borders/gb-alt3, ctr/borders/gb-alt3-grid-gray, ctr/borders/gb-alt3-grid-green, ctr/borders/gb-integer-grid-gray, gb
- **gbc** — ctr/borders/gb-alt3, ctr/borders/gb-alt3-grid-gray, ctr/borders/gb-alt3-grid-green, ctr/borders/gb-integer-grid-gray, gb
- **nes** — ctr/borders/nes-integer-mame-phosphors
- **ps1** — ctr/borders/psx-integer, ctr/borders/psx-integer-mame-phosphors
- **snes** — pegasus/snes87, snes-lttp

## Handheld zoom variants

Zoomed choices center and enlarge the declared gameplay opening, with space left around the screen. Both choices read the same PNG and the zoom keeps the image aspect ratio. These are maximal geometry measurements. An active profile can use a smaller integer-scaled viewport.

| System | Original → zoomed viewport |
| --- | --- |
| duck | 176x158 → 708x637 |
| gb | 232x209 → 710x639 |
| gba | 354x236 → 957x638 |
| gbc | 231x208 → 708x637 |
| lynx | 231x147 → 999x637, 232x148 → 998x636 |
| mini | 212x141 → 954x636 |
| ngp | 234x222 → 672x638 |
| ngpc | 233x221 → 669x636 |
| psp | 350x197 → 1020x574 |
| ws | 212x329 → 410x637, 330x212 → 992x638 |
| wsc | 212x329 → 410x637, 330x212 → 992x638 |
| wsv | 236x236 → 638x638 |

## Collection review

| Collection | Result |
| --- | --- |
| [GermanTacos](https://github.com/GermanTacos/overlays/tree/50599bfa3f217920706c0fb833b36f706d507a23) | Six MIT-licensed 16:10 overlays for N64 and PlayStation. The package includes the original copyright and license. |
| [Covarr](https://github.com/Covarr/covarr-bezel-bezels) | Handheld releases include 16:10 variants. The repository did not show a redistribution license. |
| [Duimon RetroArch Overlays](https://github.com/Duimon/Retroarch-Overlays/blob/master/LICENSE.md) | CC BY-NC-ND 4.0. The project includes shader-hybrid and plain overlays. |
| [Duimon Mega Bezel](https://github.com/Duimon/Duimon-Mega-Bezel) and [Potato](https://github.com/Duimon/Duimon-Mega-Bezel-Potato) | Presets depend on the Mega Bezel shader and require backend and performance checks. |
| [Watomsk](https://github.com/Watomsk/Overlays) | Resolution-specific overlays. The repository did not show a redistribution license. |
| [The Bezel Project](https://github.com/thebezelproject) | Per-system repositories and per-game configuration. Individual artwork needs its own provenance and gameplay-window check. |
| [Libretro Overlay Borders](https://github.com/libretro/overlay-borders) | MIT license. Includes Vectrex artwork and 16:9 collections. Vectrex tint overlays need different handling from a clear decorative window. |
| [Libretro Common Overlays](https://github.com/libretro/common-overlays) | CC BY 4.0. Existing RetroArch and CTR decorative presets were audited. Input overlays with interactive controls are unsuitable as decorative presets. |
