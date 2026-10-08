#!/usr/bin/env python3
"""Build the public libraries' DocC documentation without changing Package.swift."""

import argparse
import hashlib
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parent.parent
# NexusVapor is included: `swift build` compiles every library target, so the default
# Vapor trait's dependency is built whether or not its documentation is.
MODULES = ("Nexus", "NexusRouter", "NexusHummingbird", "NexusVapor", "NexusTest")


def run(arguments, **kwargs):
    print("+ " + shlex.join(str(argument) for argument in arguments), flush=True)
    return subprocess.run([str(argument) for argument in arguments], check=True, **kwargs)


def main():
    cache_base = Path.home() / "Library/Caches" if sys.platform == "darwin" else Path(
        os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")
    )
    checkout = hashlib.sha256(str(ROOT).encode()).hexdigest()[:16]
    cache = cache_base / "nexus-documentation" / checkout
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scratch-path", type=Path, default=cache / "build",
                        help="SwiftPM build directory (defaults outside the source checkout)")
    parser.add_argument("--output", type=Path, default=cache / "Nexus.doccarchive",
                        help="combined documentation archive and static website directory")
    parser.add_argument("--allow-warnings", action="store_true",
                        help="do not fail on DocC warnings, for releases that predate the link fixes")
    parser.add_argument("--hosting-base-path", default="/",
                        help="URL prefix when hosting under a subdirectory, such as /Nexus")
    args = parser.parse_args()
    scratch = args.scratch_path.expanduser().resolve()
    output = args.output.expanduser().resolve()
    if output.suffix != ".doccarchive":
        parser.error("--output must end in .doccarchive")
    if output.exists() and not (output / "metadata.json").is_file():
        parser.error("--output exists but is not a DocC archive")
    docc = shutil.which("docc")
    if docc is None and shutil.which("xcrun"):
        docc = subprocess.check_output(["xcrun", "--find", "docc"], text=True).strip()
    if not docc:
        parser.error("DocC is required; select an Xcode or Swift toolchain that includes docc")

    # Extract current declarations and documentation comments. A dedicated scratch
    # path also keeps signed SwiftPM resource bundles outside synced source folders.
    # The compiler writes the graphs, because `swift package dump-symbol-graph` fails here
    # on Swift 6.4: Swift Build also extracts swift-system's Linux-only C headers, and the
    # native build system tries to extract the synthesized test module. Graphs persist in
    # the scratch path, since an incremental build only rewrites those of changed modules.
    graphs = scratch / "symbol-graphs"
    graphs.mkdir(parents=True, exist_ok=True)
    flags = ["-emit-symbol-graph", "-emit-symbol-graph-dir", graphs,
             "-symbol-graph-minimum-access-level", "public", "-symbol-graph-skip-synthesized-members"]
    run(["swift", "build", "--package-path", ROOT, "--scratch-path", scratch,
         *[option for flag in flags for option in ("-Xswiftc", flag)]])
    output.parent.mkdir(parents=True, exist_ok=True)

    # Each catalog receives only its own module's graphs. Keep conversion outputs
    # temporary so a failed link check cannot replace a previously built website.
    with tempfile.TemporaryDirectory(prefix="nexus-docc-", dir=output.parent) as temporary:
        workspace = Path(temporary)
        archives = []
        for module in MODULES:
            module_graphs = workspace / module
            module_graphs.mkdir()
            graph = graphs / f"{module}.symbols.json"
            if not graph.is_file():
                raise RuntimeError(f"Missing symbol graph for {module}: {graph}")
            for source in [graph, *graphs.glob(f"{module}@*.symbols.json")]:
                shutil.copy2(source, module_graphs / source.name)
            # Only Nexus has a catalog; the others are documented from their symbol graphs.
            catalog = ROOT / "Sources" / module / f"{module}.docc"
            # The other modules link to Nexus symbols such as ``Connection``, which a
            # per-module conversion cannot resolve, so only Nexus fails on warnings.
            strict = ["--warnings-as-errors"] if module == "Nexus" and not args.allow_warnings else []
            archive = workspace / f"{module}.doccarchive"
            run([docc, "convert", *([catalog] if catalog.is_dir() else []),
                 "--additional-symbol-graph-dir", module_graphs,
                 "--output-path", archive,
                 "--fallback-display-name", module,
                 "--fallback-bundle-identifier", f"org.spectro.nexus.{module}",
                 "--fallback-default-module-kind", "Library",
                 "--hosting-base-path", args.hosting_base_path,
                 *strict, "--analyze"])
            archives.append(archive)
        combined = workspace / "Combined.doccarchive"
        run([docc, "merge", *archives, "--output-path", combined,
             "--synthesized-landing-page-name", "Nexus Libraries"])
        previous = workspace / "Previous.doccarchive"
        if output.exists():
            output.rename(previous)
        try:
            combined.rename(output)
        except OSError:
            if previous.exists():
                previous.rename(output)
            raise

    print(f"\nDocumentation: {output}")
    prefix = args.hosting_base_path.strip("/")
    if prefix:
        print(f"Mount this archive at /{prefix}/ on your static host.")
    else:
        serve = ["python3", "-m", "http.server", "8000", "--bind", "127.0.0.1", "--directory", str(output)]
        print("Serve locally: " + shlex.join(serve))
        print("Open: http://127.0.0.1:8000/documentation/")


if __name__ == "__main__":
    try:
        main()
    except (subprocess.CalledProcessError, RuntimeError, OSError) as error:
        print(f"Documentation build failed: {error}", file=sys.stderr)
        sys.exit(1)
