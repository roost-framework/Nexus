#!/usr/bin/env python3
"""Report source coverage across all SwiftPM test executables on macOS and Linux."""

import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys


def tool(name):
    if sys.platform == "darwin":
        return subprocess.check_output(["xcrun", "--find", name], text=True).strip()
    swift = shutil.which("swift")
    if swift:
        sibling = Path(swift).resolve().parent / name
        if sibling.is_file():
            return str(sibling)
    raise RuntimeError(f"Cannot find {name} in the Swift toolchain")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Enforce source line coverage")
    parser.add_argument("--threshold", type=float, default=85.0)
    args = parser.parse_args()
    if not 0 <= args.threshold <= 100:
        parser.error("threshold must be between 0 and 100")

    root = Path(__file__).resolve().parent.parent
    os.chdir(root)
    exported = Path(subprocess.check_output(["swift", "test", "--show-codecov-path"], text=True).strip())
    products = exported.parent.parent
    profiles = sorted(exported.parent.glob("*.profraw"))
    binaries = []
    for bundle in sorted(products.glob("*.xctest")):
        binary = bundle / "Contents" / "MacOS" / bundle.stem if bundle.is_dir() else bundle
        if binary.is_file():
            binaries.append(binary)
    if not profiles or not binaries:
        raise RuntimeError("Missing coverage profiles or test executables; run swift test --enable-code-coverage")

    output = root / ".build" / "coverage"
    output.mkdir(parents=True, exist_ok=True)
    profile = output / "coverage.profdata"
    subprocess.run([tool("llvm-profdata"), "merge", "-sparse", *map(str, profiles), "-o", str(profile)], check=True)
    command = [tool("llvm-cov"), "export", str(binaries[0]), f"-instr-profile={profile}"]
    for binary in binaries[1:]:
        command.extend(["-object", str(binary)])
    command.append("--ignore-filename-regex=/Tests/|/\\.build/|/Checkouts/")
    lcov = output / "coverage.lcov"
    with lcov.open("w") as stream:
        subprocess.run([*command, "--format=lcov"], stdout=stream, check=True)

    # Count each source line once, using the same LCOV records as the HTML report.
    # LLVM's JSON summary can count overlapping Swift closure regions repeatedly.
    source_root = root / "Sources"
    files = {}
    filename = None
    for record in lcov.read_text().splitlines():
        if record.startswith("SF:"):
            candidate = Path(record[3:]).resolve()
            filename = candidate if candidate.is_relative_to(source_root) else None
            if filename is not None:
                files.setdefault(filename, {})
        elif record.startswith("DA:") and filename is not None:
            line, hits = map(int, record[3:].split(",")[:2])
            if line <= 0 or hits < 0:
                raise RuntimeError(f"Invalid line coverage in {filename}: {record}")
            files[filename][line] = files[filename].get(line, 0) + hits
        elif record == "end_of_record":
            filename = None

    totals = {}
    for filename, lines in files.items():
        target = filename.relative_to(source_root).parts[0]
        covered, count = totals.get(target, (0, 0))
        totals[target] = (covered + sum(hits > 0 for hits in lines.values()), count + len(lines))

    expected = {path.name for path in source_root.iterdir() if path.is_dir() and any(path.rglob("*.swift"))}
    missing = expected - totals.keys()
    if missing:
        raise RuntimeError(f"Coverage is missing source targets: {', '.join(sorted(missing))}")
    covered = sum(value[0] for value in totals.values())
    count = sum(value[1] for value in totals.values())
    if count == 0:
        raise RuntimeError("Coverage contains no executable source lines")
    percentage = 100 * covered / count
    rows = ["Target                     Covered / Lines     Line coverage"]
    for name, (hit, total) in sorted(totals.items()):
        rows.append(f"{name:26} {hit:7} / {total:<7} {100 * hit / total if total else 0:8.2f}%")
    rows.append(f"{'TOTAL':26} {covered:7} / {count:<7} {percentage:8.2f}%")
    summary = "\n".join(rows) + "\n"
    (output / "summary.txt").write_text(summary)
    (output / "summary.json").write_text(json.dumps({
        "lines": {"covered": covered, "count": count, "percent": percentage},
        "targets": totals,
    }, indent=2) + "\n")
    print(summary, end="")
    if shutil.which("genhtml"):
        subprocess.run(["genhtml", str(lcov), "--output-directory", str(output / "html"),
                        "--title", "Nexus Coverage"], check=True, stdout=subprocess.DEVNULL)
    if args.check and percentage < args.threshold:
        raise RuntimeError(f"Source line coverage {percentage:.2f}% is below {args.threshold:g}%")


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, OSError, ValueError, KeyError, subprocess.CalledProcessError) as error:
        print(f"Coverage failed: {error}", file=sys.stderr)
        sys.exit(1)
