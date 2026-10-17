#!/usr/bin/env python3
"""Import the Godot campaign assets from a pinned Beta commit.

Requires Python 3.10+ and Pillow. Run from any directory:
    python tools/import_beta_assets.py --skip-animations
    python tools/import_beta_assets.py --animations-only
    python tools/import_beta_assets.py --animations-only --animation-states idle --cache-only
    python tools/import_beta_assets.py
Only the files declared below, data manifests, and docs/ASSET_PROVENANCE.md are written.
No clone, external conversion binary, or working-copy dependency is required.
"""

from __future__ import annotations

import hashlib
import io
import json
import argparse
import ast
import re
import tempfile
from concurrent.futures import ThreadPoolExecutor
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
CACHE = Path(tempfile.gettempdir()) / "arkamon-beta-godot-cache" / SOURCE_COMMIT
CACHE_ONLY = False


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def fetch(source_path: str) -> bytes:
    cached = CACHE / source_path
    if not cached.is_file():
        if CACHE_ONLY:
            raise ValueError(f"Missing original in cache-only mode: {source_path}")
        url = RAW_BASE + quote(source_path, safe="/")
        request = Request(url, headers={"User-Agent": "Arkamon-Godot pinned asset importer"})
        for attempt in range(3):
            try:
                with urlopen(request, timeout=120) as response:
                    data = response.read()
                cached.parent.mkdir(parents=True, exist_ok=True)
                cached.write_bytes(data)
                break
            except OSError:
                if attempt == 2:
                    raise
                time.sleep(attempt + 1)
    return cached.read_bytes()


def write_bytes(path: str, data: bytes) -> None:
    destination = ROOT / path
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = destination.with_name(destination.name + ".tmp")
    temporary.write_bytes(data)
    temporary.replace(destination)


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


def tree_entries() -> list[dict]:
    path = CACHE / "tree.json"
    if not path.exists():
        if CACHE_ONLY:
            raise ValueError("Missing repository tree in cache-only mode")
        request = Request(f"https://api.github.com/repos/Andreatz/Arkamon-Beta/git/trees/{SOURCE_COMMIT}?recursive=1", headers={"User-Agent": "Arkamon-Godot importer"})
        with urlopen(request, timeout=60) as response:
            data = response.read()
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
    return json.loads(path.read_bytes())["tree"]


class LiteralParser:
    """Parse only inert JS object/array literals, without executing TypeScript."""
    token = re.compile(r"\s+|//[^\n]*|/\*.*?\*/|'(?:\\.|[^'\\])*'|\"(?:\\.|[^\"\\])*\"|-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?|[A-Za-z_$][\w$]*|[{}\[\]:,]", re.S)

    def __init__(self, source: str):
        self.tokens = []
        offset = 0
        while offset < len(source):
            match = self.token.match(source, offset)
            if not match:
                raise ValueError(f"Unsupported TypeScript literal near {source[offset:offset+60]!r}")
            value = match.group()
            offset = match.end()
            if not value.isspace() and not value.startswith(("//", "/*")):
                self.tokens.append(value)
        self.index = 0

    def take(self) -> str:
        token = self.tokens[self.index]
        self.index += 1
        return token

    def value(self):
        token = self.take()
        if token == "{":
            result = {}
            while self.tokens[self.index] != "}":
                key = self.take()
                if key.startswith(("'", '"')):
                    key = ast.literal_eval(key)
                if self.take() != ":":
                    raise ValueError("Expected object property colon")
                result[key] = self.value()
                if self.tokens[self.index] == ",":
                    self.take()
                elif self.tokens[self.index] != "}":
                    raise ValueError("Expected object comma")
            self.take()
            return result
        if token == "[":
            result = []
            while self.tokens[self.index] != "]":
                result.append(self.value())
                if self.tokens[self.index] == ",":
                    self.take()
                elif self.tokens[self.index] != "]":
                    raise ValueError("Expected array comma")
            self.take()
            return result
        if token.startswith(("'", '"')):
            return ast.literal_eval(token)
        if token in ("true", "false", "null"):
            return {"true": True, "false": False, "null": None}[token]
        if re.fullmatch(r"-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?", token):
            return float(token) if any(c in token for c in ".eE") else int(token)
        raise ValueError(f"Executable expression rejected in data literal: {token}")


def ts_literal(source: str, declaration: str):
    marker = source.index(declaration)
    start = source.index("=", marker) + 1
    # Find the end using a string/comment-aware scanner, not by evaluating TS.
    match = re.search(r"[\[{]", source[start:])
    if not match:
        raise ValueError(f"No literal for {declaration}")
    start += match.start()
    depth = 0
    pattern = re.compile(r"//[^\n]*|/\*.*?\*/|'(?:\\.|[^'\\])*'|\"(?:\\.|[^\"\\])*\"|[{}\[\]]", re.S)
    for token in pattern.finditer(source, start):
        text = token.group()
        if text in ("{", "["):
            depth += 1
        elif text in ("}", "]"):
            depth -= 1
            if depth == 0:
                return LiteralParser(source[start:token.end()]).value()
    raise ValueError(f"Unterminated literal {declaration}")


def import_world(entries: list[dict]) -> None:
    for filename in ("pokemon.json", "mosse.json", "tipi.json", "crescita_hp.json", "mappe.json", "incontri.json", "allenatori.json"):
        source = "src/data/" + filename
        data = fetch(source)
        json.loads(data)
        output = "data/" + filename
        write_bytes(output, data)
        record(source, output, "Byte-for-byte complete original JSON.")
    maps = {}
    for entry in entries:
        source = entry["path"]
        if source.startswith("src/data/localMaps/") and source.endswith(".ts") and not source.endswith("/types.ts"):
            parsed = ts_literal(fetch(source).decode("utf-8"), "export const ")
            parsed["texture"] = "res://assets/maps/" + Path(parsed["image"]).stem + ".webp"
            maps[parsed["id"]] = parsed
            record(source, None, "Parse inert TypeScript data literal into data/world/local_maps.json; preserve node/road coordinates, IDs and original image; add Godot texture path.")
    write_json("data/world/local_maps.json", {"schema_version": 1, "maps": maps})
    source = "src/data/mainMapRoads.ts"
    text = fetch(source).decode("utf-8")
    connections = ts_literal(text, "MAIN_MAP_ROAD_CONNECTIONS")
    start = re.search(r"MAIN_MAP_START_NODE\s*=\s*'([^']+)'", text).group(1)
    coords_source = "src/scenes/MappaPrincipaleScene.tsx"
    coordinates = ts_literal(fetch(coords_source).decode("utf-8"), "const COORDS:")
    nodes = [{"id": key, **value} for key, value in coordinates.items()]
    write_json("data/world/main_map_roads.json", {"schema_version": 1, "start_node": start, "connections": connections, "nodes": nodes, "texture": "res://assets/maps/Mappa-Finale.webp"})
    record(source, None, "Parse original main-map start node and undirected connections into data/world/main_map_roads.json.")
    record(coords_source, None, "Extract only the inert original COORDS literal into main_map_roads.json nodes; percentages remain 0..100.")
    print(f"World data ready: {len(maps)} local maps, {len(nodes)} world nodes, {len(connections)} roads", flush=True)


def convert_image(source: str, output: str, max_size: int = 1600, transparent: bool = False) -> None:
    original = ImageOps.exif_transpose(Image.open(io.BytesIO(fetch(source)))).convert("RGBA" if transparent else "RGB")
    original_size = original.size
    original.thumbnail((max_size, max_size), Image.Resampling.LANCZOS)
    write_bytes(output, image_bytes(original, "WEBP", quality=82, method=4))
    record(source, output, f"Preserve aspect ratio and complete image, apply EXIF orientation, fit within {max_size}x{max_size}; WebP quality82 method4. Alpha preserved when present.", source_size=list(original_size), output_size=list(original.size))


def import_full_images(entries: list[dict], workers: int) -> None:
    pokemon = json.loads((ROOT / "data/pokemon.json").read_bytes())
    with ThreadPoolExecutor(max_workers=workers) as pool:
        for completed, _ in enumerate(pool.map(import_creature, [p["id"] for p in pokemon]), 1):
            if completed % 20 == 0 or completed == len(pokemon):
                print(f"Creature portraits {completed}/{len(pokemon)}", flush=True)
    backgrounds, maps, jobs = {}, {}, []
    for entry in entries:
        source = entry["path"]
        if entry["type"] != "blob" or not source.lower().endswith((".png", ".jpg", ".webp")):
            continue
        if source.startswith("public/backgrounds/"):
            output = "assets/backgrounds/" + Path(source).stem + ".webp"
            backgrounds[Path(source).stem] = "res://" + output
            jobs.append((source, output, 1600, False))
        elif source.startswith("public/maps/"):
            output = "assets/maps/" + Path(source).stem + ".webp"
            maps[Path(source).stem] = "res://" + output
            jobs.append((source, output, 2000, False))
        elif source.startswith("public/ui/transitions/"):
            output = "assets/transitions/" + Path(source).stem + ".webp"
            jobs.append((source, output, 1600, True))
    with ThreadPoolExecutor(max_workers=workers) as pool:
        list(pool.map(lambda job: convert_image(*job), jobs))
    for player in (1, 2):
        source = f"public/ui/player{player}.png"
        output = f"assets/ui/player{player}.png"
        im = Image.open(io.BytesIO(fetch(source))).convert("RGBA")
        im.thumbnail((256, 256), Image.Resampling.LANCZOS)
        write_bytes(output, image_bytes(im, "PNG", optimize=True))
        record(source, output, "Preserve RGBA; fit within 256x256 with Lanczos.")
    write_json("data/world_assets.json", {"schema_version": 1, "backgrounds": backgrounds, "maps": maps, "main_map": "res://assets/maps/Mappa-Finale.webp", "players": {"1": "res://assets/ui/player1.png", "2": "res://assets/ui/player2.png"}})
    write_world_aggregate(backgrounds)
    prototype_path = ROOT / "data/prototype.json"
    prototype = json.loads(prototype_path.read_bytes()) if prototype_path.exists() else {"schema_version": 2, "source_repository": SOURCE_REPOSITORY, "source_commit": SOURCE_COMMIT, "starters": STARTERS, "encounters": ENCOUNTERS, "starting_level": 5, "animations": "res://data/animations.json"}
    prototype["sprites"] = {str(p["id"]): f"res://assets/creatures/{p['id']}.png" for p in pokemon}
    prototype["notes"] = ["Complete original catalogue: 110 species. Full world metadata is in data/world/.", "Real animations are available only for the species listed in data/animations.json; every other species uses its original transparent static portrait."]
    write_json("data/prototype.json", prototype)
    print(f"World images ready: {len(backgrounds)} backgrounds, {len(maps)} map images, 2 player portraits", flush=True)


def import_audio() -> None:
    source_table = "src/data/audio-selections.json"
    table = json.loads(fetch(source_table))
    choices = {"hit": table["choices"]["event:hit"]["soundId"], "confirm": table["choices"]["event:click"]["soundId"], "capture": table["choices"]["event:capture"]["soundId"], "heal": "48262802520e9d8a"}
    for name, sound_id in choices.items():
        sound = table["sounds"][sound_id]
        source = "public/" + sound["src"].lstrip("/")
        data = fetch(source)
        if not data.startswith(b"OggS"):
            raise ValueError(f"Expected Ogg: {source}")
        output = f"assets/audio/{name}.ogg"
        write_bytes(output, data)
        record(source, output, "Byte-for-byte selected original Ogg.", sound_id=sound_id, sound_name=sound["name"], original_source_path="public/" + sound["originalSrc"])
    record(source_table, None, "Original source sound selection and provenance mapping.")
    source = "public/sounds/Part 1/Fairy magic/CreditToZachry.txt"
    output = "assets/audio/CreditToZachry.txt"
    write_bytes(output, fetch(source))
    record(source, output, "Preserve original credit notice verbatim.")


def write_world_aggregate(backgrounds: dict) -> None:
    main_map = json.loads((ROOT / "data/world/main_map_roads.json").read_bytes())
    raw_maps = json.loads((ROOT / "data/world/local_maps.json").read_bytes())["maps"]
    local_maps = {}
    for key, value in raw_maps.items():
        local_maps[key] = {**value, "original_image": value["image"], "image": value["texture"]}
    location_backgrounds = dict(backgrounds)
    for node in main_map["nodes"]:
        location = node["id"]
        slug = location.lower()
        if location.startswith("Percorso_"):
            slug = "route_" + location.split("_")[1]
        elif location == "ReggioCalabria":
            slug = "reggio_calabria"
        elif location == "Molisnt":
            slug = "molise"
        elif location == "Pordenone":
            slug = "laboratory"
        location_backgrounds[location] = backgrounds.get(slug, local_maps.get(location, {}).get("image", main_map["texture"]))
    nodes = [{**node, "label": node["id"].replace("_", " ")} for node in main_map["nodes"]]
    write_json("data/world.json", {"schema_version": 1, "main_map": {"image": main_map["texture"], "nodes": nodes, "roads": main_map["connections"], "start_node": main_map["start_node"]}, "local_maps": local_maps, "backgrounds": location_backgrounds})


def import_full_animation(metadata_path: str) -> tuple[str, str, dict]:
    metadata = json.loads(fetch(metadata_path))
    sheet = metadata["sheet"]
    species_id, state = str(metadata["speciesId"]), metadata["action"]
    source = str(Path(metadata_path).parent).replace("\\", "/") + "/" + sheet["file"]
    data = fetch(source)
    if sha256(data) != sheet["sha256"]:
        raise ValueError(f"Upstream atlas checksum mismatch: {source}")
    original = Image.open(io.BytesIO(data)).convert("RGBA")
    cell = 384 if state == "idle" else 192
    # Keeping the complete shared canvas preserves the same pivot/scale in every action.
    atlas = original.resize((int(sheet["columns"]) * cell, int(sheet["rows"]) * cell), Image.Resampling.LANCZOS)
    output = f"assets/animations/{species_id}_{state}.webp"
    write_bytes(output, image_bytes(atlas, "WEBP", quality=78, method=4))
    record(metadata_path, None, "Read original animation geometry, frame count, FPS, normalization and source checksum.")
    record(source, output, f"Resize full atlas spatially to {cell}x{cell} cells using Lanczos, preserving shared per-species canvas/pivot, every frame, order and original FPS; no temporal resampling/interpolation/generation. WebP quality78, original alpha retained.", source_size=list(original.size), source_cell=[sheet["cellWidth"], sheet["cellHeight"]], source_frame_count=sheet["frameCount"], source_fps=sheet["fps"])
    viewport = sheet.get("viewport", metadata.get("viewport", {}))
    scale = cell / sheet["cellWidth"]
    result = {"texture": "res://" + output, "cell_size": [cell, cell], "columns": sheet["columns"], "rows": sheet["rows"], "frame_count": sheet["frameCount"], "fps": sheet["fps"], "duration": sheet["durationSeconds"], "loop": state == "idle", "source_frame_indices": list(range(sheet["frameCount"])), "display_scale": sheet["cellWidth"] / max(1, viewport.get("width", sheet["cellWidth"])), "viewport": {key: value * scale for key, value in viewport.items() if isinstance(value, (int, float))}}
    return species_id, state, result


def import_all_animations(entries: list[dict], workers: int, selected_states: list[str] | None = None, selected_species: list[int] | None = None) -> None:
    paths = [e["path"] for e in entries if e["path"].startswith("public/sprites/arkamon/") and "/front/" in e["path"] and e["path"].endswith(".metadata.json") and not "animation-set" in e["path"]]
    if selected_states:
        paths = [path for path in paths if Path(path).name.removesuffix(".metadata.json") in selected_states]
    if selected_species:
        paths = [path for path in paths if int(path.split("/")[3]) in selected_species]
    manifest_path = ROOT / "data/animations.json"
    animations = json.loads(manifest_path.read_bytes()).get("animations", {}) if manifest_path.exists() else {}
    with ThreadPoolExecutor(max_workers=workers) as pool:
        for completed, (species, state, value) in enumerate(pool.map(import_full_animation, paths), 1):
            animations.setdefault(species, {})[state] = value
            if completed % 5 == 0 or completed == len(paths):
                write_json("data/animations.json", {"schema_version": 2, "idle": {key: values["idle"] for key, values in animations.items() if "idle" in values}, "animations": animations})
                print(f"Animation atlases {completed}/{len(paths)}", flush=True)
    print(f"Imported {len(paths)} selected action sheets; full manifest: {len(animations)} species, {sum(len(states) for states in animations.values())} action sheets", flush=True)


def import_vfx() -> None:
    catalog_path = "public/vfx/moves/ai-generated/catalog.json"
    catalog = json.loads(fetch(catalog_path))
    moves = {m["id"]: m for m in json.loads((ROOT / "data/mosse.json").read_bytes())}
    selected = {}
    for item in catalog["assets"]:
        move = moves.get(item["sourceMoveId"], {})
        move_type = move.get("tipo")
        if move_type and move_type not in selected:
            selected[move_type] = item
    manifest = {"schema_version": 1, "types": {}, "moves": {}, "transitions": {"closed": "res://assets/transitions/arkamon-d6-closed.webp", "open": "res://assets/transitions/arkamon-d6-open.webp"}}
    for move_type, item in selected.items():
        source = "public/" + item["src"]
        data = fetch(source)
        if sha256(data) != item["sha256"]:
            raise ValueError(f"VFX source checksum mismatch: {source}")
        sprite = item["sprite"]
        image = Image.open(io.BytesIO(data)).convert("RGBA")
        image = image.resize((sprite["columns"] * 192, sprite["rows"] * 192), Image.Resampling.LANCZOS)
        output = f"assets/vfx/type_{item['sourceMoveId']}.webp"
        write_bytes(output, image_bytes(image, "WEBP", quality=82, method=4))
        record(source, output, "Reuse existing Beta VFX atlas as a generic type representative; resize cells to192; preserve all frames and original timing; no regeneration.", upstream_generation_mode=catalog.get("generationMode"), representative_move_id=item["sourceMoveId"])
        manifest["types"][move_type] = {"texture": "res://" + output, "cell_size": [192, 192], "columns": sprite["columns"], "rows": sprite["rows"], "frame_count": sprite["frameCount"], "fps": sprite["fps"], "duration": item["durationMs"] / 1000.0, "loop": False, "source_move_id": item["sourceMoveId"], "anchor": item.get("anchor", "target"), "blend_mode": item.get("blendMode", "normal")}
    for move in moves.values():
        if move["tipo"] in manifest["types"]:
            manifest["moves"][str(move["id"])] = move["tipo"]
    write_json("data/vfx.json", manifest)
    record(catalog_path, None, "Read original VFX source geometry/timing/IDs/checksums; select one existing representative for each of eight original game types, record compact mapping in data/vfx.json.")


def write_full_audit() -> None:
    old_path = ROOT / "data/import_manifest.json"
    prior = json.loads(old_path.read_bytes()).get("files", []) if old_path.exists() else []
    records = {(r["source_path"], r.get("output_path")): r for r in prior}
    for row in RECORDS:
        records[(row["source_path"], row.get("output_path"))] = row
    ordered = sorted(records.values(), key=lambda row: (row["source_path"], row.get("output_path") or ""))
    generated = {}
    for path in ("data/world.json", "data/world_assets.json", "data/world/local_maps.json", "data/world/main_map_roads.json", "data/prototype.json", "data/animations.json", "data/vfx.json"):
        file = ROOT / path
        if file.exists():
            data = file.read_bytes()
            generated[path] = {"sha256": sha256(data), "bytes": len(data)}
    write_json("data/import_manifest.json", {"schema_version": 2, "source_repository": SOURCE_REPOSITORY, "source_commit": SOURCE_COMMIT, "pillow_version": PILLOW_VERSION, "generated_files": generated, "files": ordered})
    animations_path = ROOT / "data/animations.json"
    animations = json.loads(animations_path.read_bytes()).get("animations", {}) if animations_path.exists() else {}
    count = sum(len(states) for states in animations.values())
    lines = ["# Asset provenance", "", f"Imported from [{SOURCE_REPOSITORY}]({SOURCE_REPOSITORY}) at commit `{SOURCE_COMMIT}`. All requests use immutable raw URLs at that commit; the old local Beta reference is not used.", "", "## Reproducing the import", "", "Requires Python 3.10+ and Pillow. Run `python tools/import_beta_assets.py --skip-animations` to import all raw game tables, 110 portraits, world geometry/images, two player portraits and generic type VFX. Run `python tools/import_beta_assets.py --animations-only` for the complete available original character animations. With no flags both stages run. To refresh only the higher-resolution idle sheets, run `python tools/import_beta_assets.py --animations-only --animation-states idle --cache-only`; `--species 1 5 9` can further restrict the animation selection. Unselected states remain unchanged in the manifest. Network/processing concurrency defaults to four workers (`--workers 4`). Original downloads are cached outside the repository under the OS temporary directory `arkamon-beta-godot-cache/<commit>/`. No clone or ffmpeg is required.", "", f"This run used Pillow {PILLOW_VERSION}. Exact processed bytes depend on the Pillow/WebP build; upstream SHA-256 values do not. The complete machine-readable audit, including immutable source URLs, input/output SHA-256 values, byte counts and transformations, is `data/import_manifest.json`.", "", "## Coverage and transformations", "", "- Complete original data: pokemon, mosse, tipi, crescita_hp, mappe, incontri and allenatori copied byte for byte.", "- All 110 original transparent front portraits: crop nonzero-alpha bounds, Lanczos resize to fit464×464, place on512×512 transparent canvas.", "- All original backgrounds, the complete Italy map and16 local map images: aspect ratio retained, no crop; backgrounds fit1600px and maps2000px. WebP quality82.", "- All16 local-map TypeScript data literals converted without executing code. Node/road IDs, percentage coordinates, starting nodes and internal road vertices are preserved. Original main-map COORDS, starting node and connections are also preserved in JSON.", f"- Currently imported character animation coverage: {len(animations)} species, {count} action atlases. The original tree contains37 animated forms and185 sheets (idle/attack/hit/victory/ko); the remaining73 species use static portraits. Every original frame, order and original24FPS timing is retained. Idle atlases use384×384 cells for clearer creatures; attack/hit/victory/ko use192×192 cells. Logical viewports are scaled proportionally, preserving identical displayed sizes and pivots across all five actions. All sheets retain full shared canvases and use WebP quality78. Only spatial downsampling/compression occurs; no frame generation, reversal, temporal interpolation or skipping.", "- Eight existing Beta VFX sheets serve as type representatives through data/vfx.json; all game move IDs map to a type fallback. These upstream sheets were already generated in Beta, as its original catalog records; no new image generation was performed in this import. Both existing D6 transition images are reused.", "", "## Rights and credits", "", "The pinned tree has no root LICENSE and no explicit general license was found alongside the imported game data or images. Provenance does not create a license or establish public-domain status. Redistribution permissions remain those of the original rights holders and project.", "", "The hit sound selection points to `sounds/Part 1/Ichigo Mashimoro SFX rips/Hit.mp3`; no redistribution license was found. Heal uses M_H_AreaHeal_CE from Fairy magic; its available original credit notice is preserved verbatim at assets/audio/CreditToZachry.txt (Indy ‘Zachry’ Benedict). Click and capture have no verified license in the inspected tree. A credit notice alone does not establish rights. The Kenney license elsewhere in Beta is not applied to unrelated imports.", "", "## SHA-256 audit", "", "| Output / metadata source | Original source | Source SHA-256 | Output SHA-256 |", "| --- | --- | --- | --- |"]
    for row in ordered:
        lines.append(f"| `{row.get('output_path') or 'metadata read only'}` | [{row['source_path']}]({row['source_url']}) | `{row['source_sha256']}` | `{row.get('output_sha256', '—')}` |")
    write_bytes("docs/ASSET_PROVENANCE.md", ("\n".join(lines) + "\n").encode("utf-8"))


def main_full() -> None:
    global CACHE_ONLY
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--skip-animations", action="store_true")
    parser.add_argument("--animations-only", action="store_true")
    parser.add_argument("--workers", type=int, default=4)
    parser.add_argument("--animation-states", nargs="+", choices=["idle", "attack", "hit", "victory", "ko"], help="Update only these animation states, preserving other manifest entries")
    parser.add_argument("--species", nargs="+", type=int, help="Update animations only for these species IDs")
    parser.add_argument("--cache-only", action="store_true", help="Use cached originals and fail instead of making network requests")
    args = parser.parse_args()
    if args.skip_animations and args.animations_only:
        parser.error("Choose only one stage flag")
    if not 1 <= args.workers <= 4:
        parser.error("workers must be1..4 to bound memory and network concurrency")
    if args.skip_animations and (args.animation_states or args.species):
        parser.error("Animation selection requires the animation stage")
    CACHE_ONLY = args.cache_only
    entries = tree_entries()
    if not args.animations_only:
        import_world(entries)
        import_audio()
        import_full_images(entries, args.workers)
        import_vfx()
        write_full_audit()
        print("Base campaign assets complete", flush=True)
    if not args.skip_animations:
        try:
            import_all_animations(entries, args.workers, args.animation_states, args.species)
        finally:
            write_full_audit()
    total = sum(p.stat().st_size for folder in (ROOT / "assets", ROOT / "data") for p in folder.rglob("*") if p.is_file() and not p.name.endswith(".import"))
    print(f"Full import complete: assets+data {total / 1048576:.2f} MiB", flush=True)


if __name__ == "__main__":
    try:
        main_full()
    except (OSError, ValueError, KeyError) as error:
        print(f"Asset import failed: {error}", file=sys.stderr)
        sys.exit(1)
