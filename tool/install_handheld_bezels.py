#!/usr/bin/env python3
"""Install a personally obtained ci2own Handheld Bezels Pack 2.1.0 locally."""

import argparse
import shutil
import tempfile
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument(
        "--retroarch-root",
        type=Path,
        default=Path.home() / ".var/app/org.libretro.RetroArch/config/retroarch",
    )
    args = parser.parse_args()
    source = args.source.resolve(strict=True)
    pairs = [
        image
        for image in sorted(source.glob("*/_Default/**/*.png"))
        if image.is_file()
        and not image.is_symlink()
        and image.with_suffix(".ini").is_file()
        and not image.with_suffix(".ini").is_symlink()
    ]
    if not pairs:
        parser.error("source must contain system folders with matching PNG/INI pairs")
    parent = args.retroarch_root / "neostation-border-packs"
    destination = parent / "handheld-2.1.0"
    if destination.exists():
        for image in pairs:
            for original in (image, image.with_suffix(".ini")):
                installed = destination / original.relative_to(source)
                if not installed.is_file() or original.read_bytes() != installed.read_bytes():
                    parser.error(f"existing installation differs at {installed}")
        print(f"{len(pairs)} matching pairs already installed at {destination}")
        return

    parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".handheld-install-", dir=parent) as scratch:
        staged = Path(scratch) / "handheld-2.1.0"
        for image in pairs:
            target = staged / image.relative_to(source)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(image, target)
            shutil.copyfile(image.with_suffix(".ini"), target.with_suffix(".ini"))
        staged.rename(destination)
    print(f"Installed {len(pairs)} pairs at {destination}")


if __name__ == "__main__":
    main()
