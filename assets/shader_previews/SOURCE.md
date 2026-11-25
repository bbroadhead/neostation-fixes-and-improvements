# Shader preview captures

`raw.png` is an original 256 × 192 pixel-art sample. The other PNGs are the
same sample captured from the RetroArch 1.22.2 image viewer after rendering
each preset at 960 × 720 with its default parameters. GLSL captures used the
`gl` backend. Slang captures used `glcore`. These images show the effects at
one output size and provide no performance measurement.

| Preset | GLSL | Slang |
| --- | --- | --- |
| Sharp Bilinear Simple | `interpolation/sharp-bilinear-simple.glslp` | `pixel-art-scaling/sharp-bilinear-simple.slangp` |
| LCD Grid v2 | `handheld/lcd-grid-v2.glslp` | `handheld/lcd-grid-v2.slangp` |
| CRT Pi | `crt/crt-pi.glslp` | `crt/crt-pi.slangp` |

[RetroArch shader guide](https://docs.libretro.com/guides/shaders/)
