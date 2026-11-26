#!/usr/bin/env python3
"""Compile the official Goose graphics samples into a static Pages artifact."""

import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
UPSTREAM_REPO = "https://github.com/aardappel/goose"
UPSTREAM_REV = "1838de45b8823cac6c3e02a431f0134012212d39"
LARGE_DEMOS = {"31_mini_doom", "30_mini_minecraft", "28_physics_boxes"}
WAD = "freedoom1-e1m1.wad"


def gpu(id, title, tags, width, height, args, controls, description, **extra):
    return dict(id=id, title=title, mode="gpu", tags=tags,
                canvas=dict(width=width, height=height), defaultArgs=args,
                controls=controls, description=description, **extra)


def software(id, title, tags, renderer, description, **extra):
    return dict(id=id, title=title, mode="software", tags=tags,
                renderer=renderer, description=description,
                defaultArgs=[id.split("_", 1)[1]], **extra)


EXAMPLES = [
    gpu(
        "30_mini_minecraft", "Mini Minecraft", ["gfx", "WebGL2", "3D Voxel"],
        1280, 800, ["mini_minecraft"],
        "WASD walk · Space jump/swim · Shift run · Ctrl sneak · Click canvas for mouse look · "
        "Left hold mine · Right/E place · 1-8/wheel slot · C craft · H help · Esc pause · F5/F9 save/load",
        "Explore, mine and build in a procedural voxel world with caves, crafting and a day–night cycle.",
        pointerLock=True,
    ),
    gpu(
        "31_mini_doom", "Mini Doom (Freedoom E1M1)", ["gfx", "audio", "WebGL2", "Web Audio"],
        960, 600, ["mini_doom", "--wad", f"/data/{WAD}"],
        "WASD walk · Shift run · Click canvas for mouse turn (or Left/Right) · "
        "Left click / Ctrl fire · E / Space use doors · 1-4 weapons · Tab automap · H help · Esc pause · R restart",
        "Explore Freedoom’s E1M1 with textures, sprites and sound effects read from a WAD.",
        dataFiles=[dict(url=f"./data/{WAD}", path=f"/data/{WAD}")], pointerLock=True,
    ),
    gpu(
        "28_physics_boxes", "Physics Boxes", ["gfx", "physics", "WebGL2", "Shadows"],
        1280, 720, ["physics_boxes", "--boxes", "400", "--rate", "8"],
        "Drag left mouse to orbit · Scroll wheel to zoom · Space explosion! · Up/Down change pour rate · Esc stop",
        "Instanced boxes rain into a walled arena with real-time shadows and rigid-body physics.",
    ),
    gpu(
        "29_ui_todo", "Immediate-Mode UI To-Do & Color Mixer",
        ["gfx", "ui", "Immediate-Mode GUI"], 760, 520, ["ui_todo"],
        "Click text field + type + Enter to add tasks · Drag window title bars & resize corners · "
        "Try Tasks menu · Pick backdrop color & drag RGB properties · +/- scales the whole UI",
        "Edit a task list and mix the backdrop color with Goose’s immediate-mode widgets.",
    ),
    gpu(
        "27_gfx_cube", "Spinning Lit 3D Cube", ["gfx", "WebGL2", "3D"],
        640, 480, ["gfx_cube"], "Arrow keys rotate the cube · Esc stops & saves gfx_cube.png to VFS",
        "Rotate a shaded cube drawn with Goose’s graphics API and embedded shaders.",
    ),
    software(
        "21_raytrace", "Ray Tracer", ["Software 3D", "PPM → Canvas"], "ppm",
        "Spheres, checkered floor, hard shadows, and mirror reflections computed in pure Goose Wasm "
        "and rendered directly from raytrace.ppm onto HTML5 Canvas.",
        vfsImage="/raytrace.ppm", canvas=dict(width=320, height=200),
    ),
    software(
        "22_image_filters", "Image Filters (Blur & Sobel)", ["Image Processing", "PGM → Canvas"], "pgm-grid",
        "Procedural test pattern passed through bounds-check-free 3×3 box blur and Sobel edge detection; "
        "displays all generated .pgm files side-by-side on Canvas.",
    ),
    software(
        "20_life", "Conway's Game of Life", ["Cellular Automaton", "Canvas"], "life-ascii",
        "Conway's Life on a torus parsed from the Goose program's stdout frames and animated crisply "
        "on HTML5 Canvas with play/pause and generation scrubber.",
        controls="Pause or play the animation · Scrub to inspect any generation",
    ),
    software(
        "11_maze", "Maze BFS & Dijkstra Solver", ["Graph Search", "Canvas"], "maze-ascii",
        "BFS and Dijkstra shortest paths rendered directly from the Goose program's stdout grid "
        "onto a color-coded HTML5 Canvas.",
    ),
]


def build(args, scratch):
    output = args.output_dir.resolve()
    compiler = args.compiler.resolve(strict=True)
    samples = args.samples_dir.resolve(strict=True)
    web_library = args.stdlib_web.resolve(strict=True)
    upstream_library = args.upstream_stdlib
    if upstream_library is None and (samples.parent / "stdlib").is_dir():
        upstream_library = samples.parent / "stdlib"

    site = ROOT / "site"
    host = ROOT / "host" / "web"
    filter_library = web_library
    if upstream_library is not None:
        # Use upstream std.goose for copy_from while keeping the browser's math and OS bindings.
        filter_library = scratch / "stdlib-web-filters"
        shutil.copytree(web_library, filter_library)
        shutil.copyfile(upstream_library / "std.goose", filter_library / "std.goose")

    inputs = [site, host, samples, compiler, web_library, ROOT / "scripts"]
    if upstream_library is not None:
        inputs.append(upstream_library.resolve())
    if any(path.is_relative_to(output) or output.is_relative_to(path) for path in inputs):
        raise ValueError("The output directory must be separate from build inputs")
    if output.exists():
        shutil.rmtree(output)

    for directory in ("host/web", "wasm", "samples", "data", "assets"):
        (output / directory).mkdir(parents=True)
    for name in ("index.html", "styles.css", "app.js"):
        shutil.copyfile(site / name, output / name)
    for source in [*sorted(host.glob("*.js")), host / "package.json"]:
        shutil.copyfile(source, output / "host/web" / source.name)
    logo_dir = samples.parent / "docs" / "logo"
    for src_name, dst_name in (
        ("logo_black_fg_trans_bg.png", "goose-logo.png"),
        ("logo_black_fg_white_bg_square.png", "goose-favicon.png"),
    ):
        logo_src = logo_dir / src_name
        if logo_src.is_file():
            shutil.copyfile(logo_src, output / "assets" / dst_name)
    (output / ".nojekyll").touch()
    shutil.copyfile(samples / "data" / WAD, output / "data" / WAD)

    examples = []
    for example in EXAMPLES:
        id = example["id"]
        file = f"{id}.goose"
        wasm = output / "wasm" / f"{id}.wasm"
        library = filter_library if id == "22_image_filters" else web_library
        command = [compiler, samples / file, "--target", "wasm-direct", "-O2",
                   "--stdlib", library, "-o", wasm]
        if id in LARGE_DEMOS:
            # 2 GiB virtual ceiling (0 bytes committed until grown); Mini Doom needs
            # generous Direct Wasm region space while loading the WAD and 32 MiB atlas.
            command += ["--wasm-max-pages", "32767"]
        print(f"Compiling {file}", flush=True)
        subprocess.run(command, check=True)
        shutil.copyfile(samples / file, output / "samples" / file)
        examples.append(dict(example, file=file, sourceUrl=f"./samples/{file}",
                             wasmUrl=f"./wasm/{wasm.name}", wasmBytes=wasm.stat().st_size))

    manifest = dict(upstreamRepo=UPSTREAM_REPO, upstreamRev=args.upstream_rev,
                    builtAt=datetime.now(timezone.utc).isoformat(timespec="seconds"),
                    examples=examples)
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n",
                                          encoding="utf-8")
    print(f"\n{'Example':<24} {'Wasm bytes':>12}")
    for example in examples:
        print(f"{example['id']:<24} {example['wasmBytes']:>12,}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compiler", type=Path, default=ROOT / "build/bin/goosew")
    parser.add_argument("--stdlib-web", type=Path, default=ROOT / "stdlib-web")
    parser.add_argument("--samples-dir", type=Path, default=ROOT / "build/upstream-head/samples")
    parser.add_argument("--upstream-stdlib", type=Path, help="upstream standard library for 22_image_filters")
    parser.add_argument("--output-dir", type=Path, default=ROOT / "build/pages")
    parser.add_argument("--upstream-rev", default=UPSTREAM_REV)
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="goose-pages-") as scratch:
        try:
            build(args, Path(scratch))
        except (OSError, ValueError, subprocess.CalledProcessError) as error:
            parser.exit(1, f"Pages build failed: {error}\n")


if __name__ == "__main__":
    main()
