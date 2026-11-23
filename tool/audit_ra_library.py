"""Read-only local NeoStation RetroAchievements inventory."""
import argparse
from collections import Counter, defaultdict
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import sqlite3
import subprocess
import time
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen

HASH = re.compile(r"[0-9a-f]{32}", re.I)
REGION = re.compile(r"\s+\((?:USA|Europe|Japan|World|Rev [^)]*)\)", re.I)


def title_key(name):
    return " ".join(re.findall(r"\w+", REGION.sub("", name).casefold()))


def supported_files(game_id, directory, key, requests):
    cache = directory / f"supported_game_files_{game_id}.json"
    try:
        response = json.loads(cache.read_text())
        hashes = response["Results"]
        if isinstance(hashes, list):
            return hashes, "cached API response"
    except (OSError, ValueError, KeyError, TypeError):
        pass
    if not key:
        return [], "API key unavailable to this audit"
    if requests.get("blocked"):
        return [], requests["blocked"]
    query = urlencode({"i": game_id, "y": key})
    request = Request(
        f"https://retroachievements.org/API/API_GetGameHashes.php?{query}",
        headers={"User-Agent": "NeoStation-ROM-audit/1.0"},
    )
    time.sleep(1)
    try:
        with urlopen(request, timeout=15) as stream:
            response = json.load(stream)
        hashes = response["Results"]
        if not isinstance(hashes, list):
            raise ValueError("invalid Results type")
    except HTTPError as error:
        reason = f"HTTP {error.code}"
        if error.code in (401, 403, 429, 503):
            requests["blocked"] = reason
        return [], reason
    except (URLError, OSError, ValueError, KeyError, TypeError):
        return [], "transport or response failure"
    directory.mkdir(mode=0o700, parents=True, exist_ok=True)
    cache.write_text(json.dumps(response))
    return hashes, "live API response"


def verify_gamecube(path):
    try:
        result = subprocess.run(
            ["flatpak", "run", "--command=dolphin-tool",
             "org.DolphinEmu.dolphin-emu", "verify", "-a", "rchash", "-i", path],
            capture_output=True, text=True, timeout=30,
        )
        digest = result.stdout.strip().lower()
        if result.returncode == 0 and HASH.fullmatch(digest):
            return digest
    except (OSError, subprocess.TimeoutExpired):
        pass
    return None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("database", type=Path)
    parser.add_argument("report", type=Path)
    parser.add_argument("--gamecube", type=Path, help="Private offline hash results")
    parser.add_argument("--supported-files-cache", type=Path)
    parser.add_argument("--rehash-gamecube", action="store_true")
    parser.add_argument("--live", action="store_true", help="Use RA_API_KEY from the environment")
    args = parser.parse_args()
    os.umask(0o077)
    key = os.environ.get("RA_API_KEY") if args.live else None
    db = sqlite3.connect(args.database.resolve().as_uri() + "?mode=ro", uri=True)
    db.row_factory = sqlite3.Row
    db.execute("BEGIN")
    indexed = list(db.execute(
        """SELECT u.*, s.folder_name, s.ra_id, s.ra_hash_algo
           FROM user_roms u LEFT JOIN app_systems s ON s.id=u.app_system_id
           ORDER BY u.app_system_id, u.filename, u.rom_path"""
    ))
    roots = [Path(row[0]) for row in db.execute("SELECT path FROM user_rom_folders")]
    aliases = defaultdict(set)
    extensions = defaultdict(set)
    for row in db.execute("SELECT system_id, folder_name FROM app_system_folders"):
        aliases[row["folder_name"].casefold()].add(row["system_id"])
    for row in db.execute("SELECT system_id, extension FROM app_system_extensions"):
        extensions[row["system_id"]].add(row["extension"].lower())
    catalogue = defaultdict(list)
    titles = defaultdict(set)
    exact = defaultdict(set)
    for row in db.execute("SELECT * FROM app_ra_game_list"):
        game_id = row["game_id"]
        catalogue[game_id].append(row)
        if row["title"]:
            titles[(row["console_id"], title_key(row["title"]))].add(game_id)
        if row["hash"]:
            exact[(row["console_id"], row["hash"].lower())].add(game_id)
    db.close()

    indexed_paths = {os.path.realpath(row["rom_path"]) for row in indexed}
    observed, unindexed, ambiguous = set(), {}, {}
    walk_errors = []
    for root in roots:
        if not root.is_dir():
            walk_errors.append(f"Root unavailable {root}")
            continue
        for folder, dirs, files in os.walk(root, onerror=lambda exc: walk_errors.append(str(exc))):
            dirs[:] = sorted(name for name in dirs if not name.startswith("."))
            inferred = set()
            for part in reversed(Path(folder).relative_to(root).parts):
                inferred = aliases.get(part.casefold(), set())
                if inferred:
                    break
            for name in sorted(files):
                if name.startswith("."):
                    continue
                path = Path(folder) / name
                canonical = os.path.realpath(path)
                if canonical in observed:
                    continue
                observed.add(canonical)
                if canonical in indexed_paths:
                    continue
                possible = {system for system in inferred
                            if path.suffix[1:].lower() in extensions[system]}
                if len(possible) == 1:
                    unindexed[path] = next(iter(possible))
                elif possible:
                    ambiguous[path] = ", ".join(sorted(possible))
    gc = json.loads(args.gamecube.read_text()) if args.gamecube else {}
    sections, verified = [], 0
    categories = Counter()
    api_results, requests = {}, {}
    cache = args.supported_files_cache or (
        args.report.parent / ".ra-hash-cache" if args.live
        else args.database.parent / "ra_cache"
    )
    for row in indexed:
        path = Path(row["rom_path"])
        system = row["folder_name"] or row["app_system_id"]
        parent = "genesis" if system == "gen-hacks" else system.removesuffix("-hacks")
        platform = int(row["ra_id"]) if str(row["ra_id"]).isdigit() else None
        algo = row["ra_hash_algo"] or "unavailable"
        digest = row["ra_hash"]
        provenance = "stored NeoStation hash, not recalculated"
        if parent == "gc":
            digest = gc.get(str(path))
            if args.rehash_gamecube and str(path) not in gc:
                digest = verify_gamecube(str(path))
            algo = "Dolphin/rcheevos logical disc hash"
            provenance = "fresh offline verification" if digest else "Dolphin verifier unavailable or failed"
        exact_ids = exact[(platform, digest.lower())] if digest and HASH.fullmatch(digest) else set()
        manual = row["ra_match_source"] == "manual"
        cached_id = row["id_ra"]
        game_id = cached_id if manual else (next(iter(exact_ids)) if len(exact_ids) == 1 else cached_id)
        suspected = row["title_name"] or path.stem
        if not game_id:
            candidates = titles[(platform, title_key(suspected))]
            if len(candidates) == 1:
                game_id = next(iter(candidates))
        rows = catalogue[game_id]
        count = max((int(entry["num_achievements"] or 0) for entry in rows), default=None)
        set_status = "unknown" if count is None else f"{count} achievements in local catalogue"
        if game_id in exact_ids and count and path.is_file():
            verified += 1
            continue
        hashes = {entry["hash"].lower(): "" for entry in rows if entry["hash"]}
        status = "game ID unavailable"
        if game_id:
            if game_id not in api_results:
                api_results[game_id] = supported_files(game_id, cache, key, requests)
            results, status = api_results[game_id]
            for item in results:
                if isinstance(item, dict):
                    value = item.get("MD5", "")
                    if isinstance(value, str) and HASH.fullmatch(value):
                        hashes[value.lower()] = item.get("Name") or ""
        if (digest and digest.lower() in hashes and count and path.is_file()
                and (game_id in exact_ids or status in ("live API response", "cached API response"))):
            verified += 1
            continue
        if manual and game_id not in exact_ids:
            category, reason = "F", "Manual association is not confirmed by an exact hash."
        elif not path.is_file() or not digest:
            category, reason = "E", f"ROM missing or compatible hash unavailable. Stored skip reason {row['ra_hash_skipped'] or 'unrecorded'}."
        elif game_id in exact_ids and count == 0:
            category, reason = "B", "Exact local catalogue match has zero achievements in that snapshot."
        elif args.live and game_id and status not in ("live API response", "cached API response", "API key unavailable to this audit"):
            category, reason = "D", f"Supported-files request failed ({status})."
        elif game_id and count and hashes and digest.lower() not in hashes:
            category, reason = "A", "Title candidate has a set but the hash is absent from all retrieved entries. Title-only candidates require confirmation."
        else:
            category, reason = "C", "The available data did not establish an exact match for a game with achievements."
        categories[category] += 1
        try:
            size = f"{path.stat().st_size} bytes"
        except OSError:
            size = "unavailable"
        sections.append(
            f"[{category}] {path.name}\nPath {path}\n"
            f"System {system} | parent {parent} | RetroAchievements console {platform or 'unknown'}\n"
            f"Format {path.suffix or 'unknown'} | size {size}\n"
            f"Hash {digest or 'unavailable'} | method {algo} | {provenance}\n"
            f"Title {suspected}"
            + (f" | indexed title {rows[0]['title']}" if rows else "")
            + f"\nGame ID {game_id or 'unknown'} | set {set_status}\n"
            + (f"https://retroachievements.org/game/{game_id}\n" if game_id else "")
            + f"Reason {reason}\nSupported files API status {status}\n"
            + ("\n".join(f"  {digest}  {name or '(revision unavailable)'}"
                         for digest, name in sorted(hashes.items())) if hashes else
               "  No supported hashes retrieved")
            + "\nNext action "
            + {"A": "Confirm the title and compare your own dump with the set’s supported-files list.",
               "B": "Check the game page for changes since the catalogue snapshot.",
               "C": "Verify the title/revision and refresh the console catalogue.",
               "D": "Rerun with API access after resolving the recorded failure.",
               "E": "Restore access to the ROM, then recalculate with the matching console’s hash method.",
               "F": "Verify the selected set against the actual ROM hash."}[category]
        )

    text = [
        "PRIVATE · RETROACHIEVEMENTS ROM COMPATIBILITY AUDIT",
        datetime.now(timezone.utc).isoformat(),
        f"Indexed rows accounted for {len(indexed)}. Exact hash matches with achievements {verified}.",
        "Category totals for indexed rows " + ", ".join(f"{c} {categories[c]}" for c in "ABCDEF"),
        f"Configured roots {len(roots)}. Distinct visible files enumerated {len(observed)}.",
        f"Potential unindexed ROMs {len(unindexed)}. Ambiguous unindexed paths {len(ambiguous)}.",
        "Coverage is partial. Non-GameCube hashes come from the read-only NeoStation snapshot.",
        "The directory walk does not reproduce every NeoStation scan rule.",
        "A cached or live hash match does not test emulator sign-in, Hardcore eligibility or unlocks.",
        "Rerun this script with --rehash-gamecube and optionally --live with RA_API_KEY set privately.",
        "Refresh other cached hashes with NeoStation’s RetroAchievements re-match tool before rerunning.",
        "Walk errors\n" + ("\n".join(walk_errors) or "None"),
        "Configured roots\n" + "\n".join(map(str, roots)),
        *sections,
        "Potential unindexed ROMs (unprocessed)\n"
        + "\n".join(f"{system}  {path}" for path, system in sorted(unindexed.items())),
        "Ambiguous unindexed files (unprocessed)\n"
        + "\n".join(f"{systems}  {path}" for path, systems in sorted(ambiguous.items())),
    ]
    assert len(indexed) == verified + sum(categories.values())
    args.report.parent.mkdir(parents=True, exist_ok=True)
    with args.report.open("w", encoding="utf-8") as output:
        os.fchmod(output.fileno(), 0o600)
        output.write("\n\n".join(text) + "\n")
    print(*text[2:6], sep="\n")


if __name__ == "__main__":
    main()
