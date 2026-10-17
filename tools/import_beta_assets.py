#!/usr/bin/env python3
"""Import the deliberately small Godot prototype asset set from a pinned Beta commit.

Requires Python 3.10+ and Pillow. Run from any directory:
    python tools/import_beta_assets.py
Only the files declared below, data manifests, and docs/ASSET_PROVENANCE.md are written.
No clone, external conversion binary, or working-copy dependency is required.
"""

from __future__ import annotations

import hashlib
import io
import json
from pathlib import Path
import sys
import time
from urllib.parse import quote
from urllib.request import Request, urlopen

from PIL import Image, ImageOps, __version__ as PILLOW_VERSION


ROOT = Path(__file__).resolve().parents[1]
SOURCE_REPOSITORY = "https://github.com/Andreatz/Arkamon-Beta"
SOURCE_COMMIT = "7ec91d1f4e3e5252317044b1ee300b8b3e4d80a7"
RAW_BASE = f"https://raw.githubusercontent.com/Andreatz/Arkamon-Beta/{SOURCE_COMMIT}/"
STARTERS = [1, 5, 9]
ENCOUNTERS = [28, 32, 42, 56]
SPECIES = STARTERS + ENCOUNTERS
RECORDS: list[dict] = []
FETCHED: dict[str, bytes] = {}


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def fetch(source_path: str) -> bytes:
    if source_path not in FETCHED:
        url = RAW_BASE + quote(source_path, safe="/")
        request = Request(url, headers={"User-Agent": "Arkamon-Godot pinned asset importer"})
        for attempt in range(3):
            try:
                with urlopen(request, timeout=120) as response:
                    FETCHED[source_path] = response.read()
                break
            except OSError:
                if attempt == 2:
                    raise
                time.sleep(attempt + 1)
    return FETCHED[source_path]


def write_bytes(path: str, data: bytes) -> None:
    destination = ROOT / path
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_bytes(data)


def write_json(path: str, data: dict | list) -> None:
    write_bytes(path, (json.dumps(data, ensure_ascii=False, indent=2) + "\n").encode("utf-8"))


def record(source_path: str, output_path: str | None, transform: str, **extra) -> None:
    original = fetch(source_path)
    row = {
        "source_path": source_path,
        "source_url": RAW_BASE + quote(source_path, safe="/"),
        "source_sha256": sha256(original),
        "source_bytes": len(original),
        "output_path": output_path,
        "transform": transform,
        **extra,
    }
    if output_path:
        output = (ROOT / output_path).read_bytes()
        row.update(output_sha256=sha256(output), output_bytes=len(output))
    RECORDS.append(row)


def image_bytes(image: Image.Image, format: str, **options) -> bytes:
    buffer = io.BytesIO()
    image.save(buffer, format=format, **options)
    return buffer.getvalue()


def import_creature(species_id: int) -> None:
    source_path = f"public/sprites/front_sprites/{species_id}.png"
    original = Image.open(io.BytesIO(fetch(source_path))).convert("RGBA")
    bounds = original.getchannel("A").getbbox()
    if not bounds:
        raise ValueError(f"Empty creature image: {source_path}")
    creature = original.crop(bounds)
    creature.thumbnail((464, 464), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (512, 512), (0, 0, 0, 0))
    canvas.alpha_composite(creature, ((512 - creature.width) // 2, 488 - creature.height))
    output = f"assets/creatures/{species_id}.png"
    write_bytes(output, image_bytes(canvas, "PNG", optimize=True))
    record(source_path, output, "Crop full nonzero-alpha bounds; resize to fit 464x464 with Lanczos; center on transparent 512x512 canvas, bottom at y=488.", source_size=list(original.size), source_alpha_bounds=list(bounds))


def import_background(name: str, extension: str) -> None:
    source_path = f"public/backgrounds/{name}.{extension}"
    original = ImageOps.exif_transpose(Image.open(io.BytesIO(fetch(source_path)))).convert("RGB")
    original_size = original.size
    original.thumbnail((1600, 1600), Image.Resampling.LANCZOS)
    output = f"assets/backgrounds/{name}.webp"
    write_bytes(output, image_bytes(original, "WEBP", quality=85, method=6))
    record(source_path, output, "Apply EXIF orientation; convert RGB; fit inside 1600x1600 without enlarging; encode WebP quality=85 method=6.", source_size=list(original_size), output_size=list(original.size))


def import_idle(species_id: int) -> dict:
    base = f"public/sprites/arkamon/{species_id}/front/"
    metadata_path = base + "idle.metadata.json"
    metadata = json.loads(fetch(metadata_path))
    sheet_info = metadata["sheet"]
    source_path = base + sheet_info["file"]
    original_bytes = fetch(source_path)
    if sha256(original_bytes) != sheet_info["sha256"]:
        raise ValueError(f"Upstream atlas checksum mismatch: {source_path}")
    source = Image.open(io.BytesIO(original_bytes)).convert("RGBA")
    cell_width, cell_height = sheet_info["cellWidth"], sheet_info["cellHeight"]
    count, columns = sheet_info["frameCount"], sheet_info["columns"]
    union = [cell_width, cell_height, 0, 0]
    for frame in range(count):
        x, y = (frame % columns) * cell_width, (frame // columns) * cell_height
        bounds = source.crop((x, y, x + cell_width, y + cell_height)).getchannel("A").getbbox()
        if bounds:
            union = [min(union[0], bounds[0]), min(union[1], bounds[1]), max(union[2], bounds[2]), max(union[3], bounds[3])]
    scale = min(224 / (union[2] - union[0]), 224 / (union[3] - union[1]))
    frame_size = (round((union[2] - union[0]) * scale), round((union[3] - union[1]) * scale))
    rows = (count + columns - 1) // columns
    atlas = Image.new("RGBA", (columns * 256, rows * 256), (0, 0, 0, 0))
    for frame in range(count):
        x, y = (frame % columns) * cell_width, (frame // columns) * cell_height
        cropped = source.crop((x + union[0], y + union[1], x + union[2], y + union[3]))
        cropped = cropped.resize(frame_size, Image.Resampling.LANCZOS)
        destination = ((frame % columns) * 256 + (256 - frame_size[0]) // 2, (frame // columns) * 256 + 240 - frame_size[1])
        atlas.alpha_composite(cropped, destination)
    output = f"assets/animations/{species_id}_idle.webp"
    write_bytes(output, image_bytes(atlas, "WEBP", lossless=True, method=6))
    record(metadata_path, None, "Read original atlas geometry, timing and checksum. Original metadata not copied; compact runtime metadata is in data/animations.json.")
    record(source_path, output, "Find one shared alpha-bounds union over every frame; crop each frame to that same rectangle; scale uniformly to fit 224x224; pack transparent 256x256 cells with bottom at y=240. Preserve all original frames in original order and original FPS. Encode lossless WebP.", source_size=list(source.size), source_cell=[cell_width, cell_height], shared_alpha_bounds=union, source_frame_count=count, source_fps=sheet_info["fps"])
    return {
        "texture": "res://" + output,
        "cell_size": [256, 256],
        "columns": columns,
        "rows": rows,
        "frame_count": count,
        "fps": sheet_info["fps"],
        "duration": sheet_info["durationSeconds"],
        "loop": True,
        "source_frame_indices": list(range(count)),
    }


def main() -> None:
    for filename in ("pokemon.json", "mosse.json", "tipi.json", "crescita_hp.json"):
        source_path = "src/data/" + filename
        data = fetch(source_path)
        json.loads(data)  # Validate before copying the original bytes unchanged.
        output = "data/" + filename
        write_bytes(output, data)
        record(source_path, output, "Byte-for-byte copy of complete original JSON.")

    pokemon = {p["id"]: p for p in json.loads(fetch("src/data/pokemon.json"))}
    moves = {m["id"]: m for m in json.loads(fetch("src/data/mosse.json"))}
    for species_id in SPECIES:
        for move_id in pokemon[species_id]["mosse"]:
            if move_id and moves[move_id].get("effetto") not in (None, "CURA", "CURA_PCT"):
                raise ValueError(f"Unsupported prototype move {move_id} on species {species_id}")
        import_creature(species_id)
        print(f"Imported {species_id}: {pokemon[species_id]['nome']}", flush=True)
    for name, extension in (("battle_forest", "jpg"), ("laboratory", "png"), ("route_1", "jpg")):
        import_background(name, extension)

    audio_path = "src/data/audio-selections.json"
    audio = json.loads(fetch(audio_path))
    sound_mapping = {
        "hit": audio["choices"]["event:hit"]["soundId"],
        "confirm": audio["choices"]["event:click"]["soundId"],
        "capture": audio["choices"]["event:capture"]["soundId"],
        "heal": "48262802520e9d8a",  # M_H_AreaHeal_CE, as named in the original selection table.
    }
    for name, sound_id in sound_mapping.items():
        sound = audio["sounds"][sound_id]
        source_path = "public/" + sound["src"].lstrip("/")
        output = f"assets/audio/{name}.ogg"
        data = fetch(source_path)
        if not data.startswith(b"OggS"):
            raise ValueError(f"Expected Ogg audio: {source_path}")
        write_bytes(output, data)
        record(source_path, output, "Byte-for-byte copy of selected Ogg audio.", sound_id=sound_id, sound_name=sound["name"], original_source_path="public/" + sound["originalSrc"])
    record(audio_path, None, "Read Beta sound selection and original-source mappings; table not copied.")
    credit_path = "public/sounds/Part 1/Fairy magic/CreditToZachry.txt"
    credit_output = "assets/audio/CreditToZachry.txt"
    write_bytes(credit_output, fetch(credit_path))
    record(credit_path, credit_output, "Byte-for-byte copy of credit notice found alongside the original heal sound.")

    animations = {str(species_id): import_idle(species_id) for species_id in STARTERS}
    write_json("data/animations.json", {"schema_version": 1, "idle": animations})
    prototype = {
        "schema_version": 1,
        "source_repository": SOURCE_REPOSITORY,
        "source_commit": SOURCE_COMMIT,
        "starters": STARTERS,
        "encounters": ENCOUNTERS,
        "starting_level": 5,
        "sprites": {str(i): f"res://assets/creatures/{i}.png" for i in SPECIES},
        "backgrounds": {name: f"res://assets/backgrounds/{name}.webp" for name in ("battle_forest", "laboratory", "route_1")},
        "audio": {name: f"res://assets/audio/{name}.ogg" for name in sound_mapping},
        "animations": "res://data/animations.json",
        "notes": ["Original names, types, move IDs and complete data tables are unchanged.", "Only the seven listed species have imported static sprites. No evolution is included in this first slice.", "All 96 idle frames of each starter are imported at their original 24 FPS; no new animation frames are generated."],
    }
    write_json("data/prototype.json", prototype)
    manifest = {"schema_version": 1, "source_repository": SOURCE_REPOSITORY, "source_commit": SOURCE_COMMIT, "pillow_version": PILLOW_VERSION, "files": RECORDS}
    write_json("data/import_manifest.json", manifest)
    write_provenance(pokemon)
    total = sum(p.stat().st_size for folder in (ROOT / "assets", ROOT / "data") for p in folder.rglob("*") if p.is_file() and not p.name.endswith(".import"))
    print(f"Import complete: {len(RECORDS)} source records; assets + data {total / 1048576:.2f} MiB", flush=True)


def write_provenance(pokemon: dict) -> None:
    lines = [
        "# Asset provenance", "",
        f"All imported material comes from [{SOURCE_REPOSITORY}]({SOURCE_REPOSITORY}), pinned to commit `{SOURCE_COMMIT}`. The importer reads raw URLs at this commit; it does not use an older local checkout.", "",
        "Run `python tools/import_beta_assets.py` with Python 3.10+ and Pillow. The importer copies the four complete JSON tables without changing their bytes, transforms only the explicitly selected images, and copies the selected Ogg audio without conversion. It writes SHA-256 values for both upstream and resulting files to `data/import_manifest.json`.", "",
        f"This run used Pillow {PILLOW_VERSION}. Image bytes may vary between Pillow/codec versions; pin the same version when exact processed-file reproducibility matters. Every original checksum is independent of that version.", "",
        "## Included creatures", "",
        "| Role | ID | Original name | Original type |", "| --- | ---: | --- | --- |",
    ]
    for i in SPECIES:
        p = pokemon[i]
        lines.append(f"| {'Starter' if i in STARTERS else 'Encounter'} | {i} | {p['nome']} | {p['tipo']} |")
    lines += ["", "Static sprites retain transparency, fit a transparent 512×512 canvas and are cropped only to their full nonzero-alpha bounds. The starter idle sheets preserve every original frame in order and the original timing, with a common crop and scale across frames; the compact 256×256-cell atlases are described in `data/animations.json`. No AI generation, synthesized in-between frames or frame reversal was used.", "", "## Rights and credits", "",
        "The pinned repository tree contains no root LICENSE file, and no explicit image or data license was found alongside the imported sources. This document records provenance, not a new license or a claim that the files are public domain. Rights for public redistribution still depend on the original rights holders and the project's permissions.", "",
        "The original sound table names upstream sound-pack files. In particular, the selected hit sound points to `sounds/Part 1/Ichigo Mashimoro SFX rips/Hit.mp3`; no redistribution license was found for it. The selected heal sound is `M_H_AreaHeal_CE` from `Fairy magic`; the available `CreditToZachry.txt` notice is preserved verbatim in `assets/audio/`. A credit notice alone does not establish a license. Click and capture also have no verified license in the inspected tree.", "",
        "The Kenney license elsewhere in Beta applies to its VFX primitives; none of those primitives are imported here, and that license is not attributed to these unrelated images or sounds.", "",
        "## File checksums", "", "The complete machine-readable audit includes source URLs, paths, byte counts, transformations and SHA-256 values in `data/import_manifest.json`. The table below is generated by the same script.", "",
        "| Output / metadata source | Source path | Original SHA-256 | Result SHA-256 |", "| --- | --- | --- | --- |",
    ]
    for row in RECORDS:
        label = row["output_path"] or "Metadata read only"
        lines.append(f"| `{label}` | [{row['source_path']}]({row['source_url']}) | `{row['source_sha256']}` | `{row.get('output_sha256', '—')}` |")
    write_bytes("docs/ASSET_PROVENANCE.md", ("\n".join(lines) + "\n").encode("utf-8"))


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError) as error:
        print(f"Asset import failed: {error}", file=sys.stderr)
        sys.exit(1)
