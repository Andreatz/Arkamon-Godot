#!/usr/bin/env python3
"""Import the immutable original Beta UI without changing its SVGs or PNGs.

Python3.10+; Pillow for image inspection; fonttools[woff]==4.62.1 for Norwester
WOFF2-to-SFNT decoding. Install fontTools into an external directory and pass
--fonttools-dir PATH, or install it in the Python environment. No Godot import
is started. --cache-only forbids every network request.
"""
from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import io
import json
from pathlib import Path
import re
import sys
import tempfile
import subprocess
from urllib.parse import quote
from urllib.request import Request, urlopen
import xml.etree.ElementTree as ET

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SHA = "7ec91d1f4e3e5252317044b1ee300b8b3e4d80a7"
RAW = f"https://raw.githubusercontent.com/Andreatz/Arkamon-Beta/{SHA}/"
CACHE = Path(tempfile.gettempdir()) / "arkamon-beta-godot-cache" / SHA
REFERENCE = ROOT.parent / "tmp/beta-ui-reference"
CACHE_ONLY = False
SLICES = {"panel-wide": 163, "panel-medium": 97, "button-primary": 44,
          "button-default": 48, "card-default": 61, "card-selected-violet": 58,
          "card-selected-cyan": 56, "slot-default": 62, "slot-selected": 60,
          "slot-cyan": 62, "card-portrait": 99, "command-cancel": 42}
RECORDS = []


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def write(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)


def json_write(path: Path, value) -> None:
    write(path, (json.dumps(value, ensure_ascii=False, indent=2) + "\n").encode("utf8"))


def fetch(path: str) -> bytes:
    for local in (CACHE / path, REFERENCE / path):
        if local.is_file():
            return local.read_bytes()
    if CACHE_ONLY:
        raise ValueError("Missing cached original: " + path)
    request = Request(RAW + quote(path, safe="/"), headers={"User-Agent": "Arkamon-Godot original UI importer"})
    with urlopen(request, timeout=90) as response:
        data = response.read()
    write(CACHE / path, data)
    return data


def tree() -> list[dict]:
    path = CACHE / "tree.json"
    if not path.exists():
        if CACHE_ONLY:
            raise ValueError("Missing cached repository tree")
        request = Request(f"https://api.github.com/repos/Andreatz/Arkamon-Beta/git/trees/{SHA}?recursive=1", headers={"User-Agent": "Arkamon-Godot UI importer"})
        with urlopen(request, timeout=60) as response:
            write(path, response.read())
    return json.loads(path.read_bytes())["tree"]


def import_ui(entry: dict) -> dict:
    source = entry["path"]
    data = fetch(source)
    # Git blob SHA establishes that the cached original belongs to the pinned tree.
    blob = hashlib.sha1(b"blob " + str(len(data)).encode("ascii") + b"\0" + data).hexdigest()
    if blob != entry["sha"]:
        raise ValueError("Pinned Git blob checksum differs: " + source)
    output = "assets/ui/original/" + source.removeprefix("public/ui/")
    write(ROOT / output, data)
    write(REFERENCE / source, data)
    result = {"source_path": source, "source_url": RAW + quote(source, safe="/"), "source_sha256": digest(data), "source_git_blob": blob,
              "output_path": output, "output_sha256": digest(data), "bytes": len(data), "transform": "Unmodified byte-for-byte original"}
    if source.endswith(".svg"):
        svg = ET.fromstring(data)
        viewbox = [float(n) for n in re.split(r"[ ,]+", svg.attrib.get("viewBox", "").strip()) if n]
        result.update(view_box=viewbox, intrinsic_width=svg.attrib.get("width"), intrinsic_height=svg.attrib.get("height"),
                      embedded_bitmaps=any(node.tag.endswith("image") for node in svg.iter()), text_elements=sum(node.tag.endswith("text") for node in svg.iter()))
        if len(viewbox) == 4:
            result["size"] = viewbox[2:]
        if "/player-kit/" in source:
            result["css_border_slice"] = SLICES.get(Path(source).stem, 61)
            result["css_border_width"] = [11, 18, 11, 18] if Path(source).stem.startswith(("button-", "command-")) else [25, 25, 25, 25]
    elif source.lower().endswith((".png", ".webp")):
        image = Image.open(io.BytesIO(data))
        result.update(size=list(image.size), mode=image.mode, transparent="A" in image.getbands())
    RECORDS.append(result)
    return result


def import_fonts() -> dict:
    from fontTools.ttLib import TTFont
    from fontTools import __version__ as fonttools_version
    fonts = {}
    for source, name in (("public/ui/studio/fonts/chela-one.ttf", "ChelaOne-Regular.ttf"), ("public/ui/studio/fonts/norwester.woff2", "Norwester.woff2")):
        data = fetch(source)
        output = "assets/fonts/" + name
        write(ROOT / output, data)
        RECORDS.append({"source_path": source, "source_url": RAW + source, "source_sha256": digest(data), "output_path": output, "output_sha256": digest(data), "bytes": len(data), "transform": "Unmodified original font"})
        font = TTFont(io.BytesIO(data), recalcTimestamp=False)
        family = font["name"].getDebugName(1)
        fonts[family] = {"original": "res://" + output, "family": family, "glyphs": font["maxp"].numGlyphs,
                         "license_description": font["name"].getDebugName(13), "license_url": font["name"].getDebugName(14)}
        if source.endswith(".woff2"):
            font.flavor = None
            converted = ROOT / "assets/fonts/Norwester.ttf"
            font.save(converted, reorderTables=False)
            decoded = converted.read_bytes()
            fonts[family]["godot_font"] = "res://assets/fonts/Norwester.ttf"
            RECORDS.append({"source_path": source, "source_url": RAW + source, "source_sha256": digest(data), "output_path": "assets/fonts/Norwester.ttf", "output_sha256": digest(decoded), "bytes": len(decoded), "transform": "Decode WOFF2 into SFNT/TTF; preserve outlines, metrics, names and embedded license metadata", "fonttools_version": fonttools_version})
        else:
            fonts[family]["godot_font"] = "res://" + output
    return fonts


def import_site_data() -> None:
    for source, output in (("src/theme/arkamon-theme.json", "data/site_theme.json"), ("src/player-ui/portraitMetadata.json", "data/portrait_metadata.json")):
        data = fetch(source)
        json.loads(data)
        write(ROOT / output, data)
        write(REFERENCE / source, data)
        RECORDS.append({"source_path": source, "source_url": RAW + source, "source_sha256": digest(data), "output_path": output, "output_sha256": digest(data), "bytes": len(data), "transform": "Byte-for-byte original authored site theme / portrait framing metadata"})


def import_title(ffmpeg: Path) -> None:
    source = "public/assets/Sfondo Titolo.mp4"
    data = fetch(source)
    cached = REFERENCE / source
    write(cached, data)
    ffmpeg = ffmpeg.resolve()
    version = subprocess.run([str(ffmpeg), "-version"], check=True, capture_output=True, text=True).stdout.splitlines()[0]
    destination = ROOT / "assets/backgrounds"
    destination.mkdir(parents=True, exist_ok=True)
    still = destination / "title.webp"
    subprocess.run([str(ffmpeg), "-hide_banner", "-loglevel", "error", "-y", "-i", str(cached), "-frames:v", "1", "-vf", "scale=1280:-2", "-c:v", "libwebp", "-quality", "90", str(still)], check=True)
    video = destination / "title.ogv"
    subprocess.run([str(ffmpeg), "-hide_banner", "-loglevel", "error", "-y", "-i", str(cached), "-an", "-vf", "scale=1280:-2,fps=24", "-c:v", "libtheora", "-q:v", "8", "-pix_fmt", "yuv420p", "-threads", "4", str(video)], check=True)
    for path, transform in ((still, "Decode original first frame, Preserve original1280px width, encode WebP quality90"), (video, "Transcode original footage to1280px width,24FPS OggTheora quality8,yuv420p,no audio; no generated frames or new artwork")):
        output = path.relative_to(ROOT).as_posix()
        result = path.read_bytes()
        RECORDS.append({"source_path": source, "source_url": RAW + quote(source, safe="/"), "source_sha256": digest(data), "output_path": output, "output_sha256": digest(result), "bytes": len(result), "transform": transform, "ffmpeg_version": version})


def main() -> None:
    global CACHE_ONLY
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cache-only", action="store_true")
    parser.add_argument("--fonttools-dir", type=Path)
    parser.add_argument("--ffmpeg", type=Path, help="Optionally import the original title footage as Godot OggTheora and a first-frame WebP")
    args = parser.parse_args()
    CACHE_ONLY = args.cache_only
    if args.fonttools_dir:
        sys.path.insert(0, str(args.fonttools_dir.resolve()))
    entries = tree()
    ui = [entry for entry in entries if entry["type"] == "blob" and entry["path"].startswith("public/ui/")]
    with ThreadPoolExecutor(max_workers=4) as pool:
        results = list(pool.map(import_ui, ui))
    fonts = import_fonts()
    import_site_data()
    if args.ffmpeg:
        import_title(args.ffmpeg)
    references = [entry["path"] for entry in entries if entry["type"] == "blob" and entry["path"].startswith("src/") and entry["path"].endswith((".ts", ".tsx", ".css", ".json")) and
                  (entry["path"].startswith(("src/player-ui/", "src/ui-studio/", "src/theme/")) or entry["path"] in ("src/index.css", "src/components/ui/GameButton.tsx", "src/components/ui/gameButton.css"))]
    with ThreadPoolExecutor(max_workers=4) as pool:
        list(pool.map(lambda path: write(REFERENCE / path, fetch(path)), references))
    kit = {}
    for row in results:
        if row["source_path"].startswith("public/ui/player-kit/") and row["source_path"].endswith(".svg"):
            kit[Path(row["source_path"]).stem] = {"texture": "res://" + row["output_path"], "size": row["size"], "source_slice": row["css_border_slice"], "css_border_width": row["css_border_width"]}
    index = {"schema_version": 1, "source_commit": SHA, "kit": kit, "fonts": fonts,
             "active_site_font": "res://assets/fonts/Norwester.ttf", "original_ui_root": "res://assets/ui/original/",
             "site_palette": {"background": "#111827", "surface": "#24193d", "text": "#f8fafc", "muted": "#c4b5fd", "primary": "#c084fc", "border": "#7c3aed"},
             "frame_usage": {"panel": {"source_slice_default": 61, "draw_border_width": [25, 25, 25, 25]}, "button": {"draw_border_width": [11, 18, 11, 18], "hover_brightness": 1.12, "disabled_opacity": 0.45, "pressed_scale": 0.95}},
             "notes": ["SVGs are individual scalable components, not full-screen 1920x1080 screen images.", "Use original source_slice when sampling the texture; draw borders at the CSS border widths, allowing the center to stretch.", "Original PNG and SVG bytes, alpha channels and canvas dimensions are unchanged."]}
    json_write(ROOT / "data/ui_original.json", index)
    ordered = sorted(RECORDS, key=lambda row: (row["source_path"], row["output_path"]))
    json_write(ROOT / "data/ui_import_manifest.json", {"schema_version": 1, "source_repository": "https://github.com/Andreatz/Arkamon-Beta", "source_commit": SHA, "files": ordered})
    write_provenance(index, ordered, len(references))
    print(f"Imported {len(ui)} original UI files; {len(kit)} player-kit SVGs; {len(fonts)} fonts; {len(references)} source reference files.")
    print(f"Original UI totals {sum(row['bytes'] for row in ordered)/1048576:.2f} MiB; no Godot import started.")


def write_provenance(index: dict, rows: list[dict], source_count: int) -> None:
    lines = ["# Original Beta UI assets", "", f"Pinned source: Andreatz/Arkamon-Beta commit `{SHA}`. `tools/import_beta_ui.py` imports every original `public/ui/` file without rewriting images or SVG paths. No AI generation occurs.", "", "## Reproduce", "", "Requires Python3.10+, Pillow, and `fonttools[woff]==4.62.1`. Run `python tools/import_beta_ui.py --fonttools-dir <external-python-dependency-directory>`. Cached originals can be reproduced without network using `--cache-only`. Source copies are kept outside the repo at `../tmp/beta-ui-reference`; downloads also use the commit-specific OS temporary cache. No Godot editor/import is launched. Pass `--ffmpeg <external-ffmpeg.exe>` to decode the original title first frame and transcode the original8second1280×720/24FPS footage to Godot OggTheora. The sourceMP4 remains outside the repo; no new frames or artwork are generated. `data/site_theme.json` and `data/portrait_metadata.json` preserve the original authored theme geometry and portrait framing byte for byte.", "", "## Layout findings", "", "The48 player-kit SVG files are individual UI components, not1920×1080 screen designs. Their original viewBox and intrinsic dimensions are in data/ui_original.json. For example panel-wide is2026×709, panel-medium1161×423, card-portrait433×458. The website uses them as CSS border-image with center fill and stretch, preserving borders while resizing panels.", "", "The original player-ui/kit.tsx specifies source slices: panel-wide163, panel-medium97, button-primary44, button-default48, card-default61, card-selected-violet58, card-selected-cyan56, slot-default62, slot-selected60, slot-cyan62, card-portrait99. Generic panels draw25px borders; buttons draw11px top/bottom and18px left/right. GameButton danger uses command-cancel with slice42. Hover brightness1.12, disabled opacity.45 and pressed scale.95 come directly from CSS.", "", "The active site font is Arkamon Norwester for body/headings/buttons, defined in src/index.css from the original studio WOFF2. Chela One is also shipped but is not the active global font in the pinned source. assets/fonts/Norwester.ttf is a deterministic SFNT decode of that WOFF2 for Godot; no glyphs, metrics or styling are redesigned. Original Norwester.woff2 and ChelaOne-Regular.ttf are retained.", "", f"{source_count} original TSX/TS/CSS/JSON reference files are copied outside the repository under ../tmp/beta-ui-reference. The studio Blu/Scuro/Comuni SVGs and original battle PNG widgets are retained alongside the48 player-kit assets, preserving all original layers/alpha/canvas sizes.", "", "## Rights", "", "This records original provenance and does not grant a new license. No root UI redistribution license was found in the pinned tree. Original SVG descriptions and catalog claims are preserved as supplied; importing them does not verify or change those claims. Font license metadata is recorded below exactly as embedded in the font files.", ""]
    for family, font in index["fonts"].items():
        lines += [f"- {family}: {font.get('license_description') or 'No license text embedded.'} URL: {font.get('license_url') or 'None embedded.'}"]
    lines += ["", "## Checksums", "", "data/ui_import_manifest.json contains original source Git blob IDs, SHA-256 and output hashes. Unmodified image output hashes match their originals.", "", "| File | Source SHA-256 | Output SHA-256 |", "| --- | --- | --- |"]
    for row in rows:
        lines.append(f"| [{row['output_path']}]({row['source_url']}) | `{row['source_sha256']}` | `{row['output_sha256']}` |")
    write(ROOT / "docs/UI_ASSET_PROVENANCE.md", ("\n".join(lines) + "\n").encode("utf8"))


if __name__ == "__main__":
    main()
