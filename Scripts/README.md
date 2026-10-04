# Nexus Scripts

Run the full test suite with coverage, then enforce the 85% source line threshold:

```bash
./Scripts/generate-coverage.sh
./Scripts/check-coverage.sh
```

`generate-coverage.sh` forwards arguments to `swift test`, so `--jobs 8` can limit
build parallelism. SwiftPM refreshes coverage profiles on each test run; an
incremental build is sufficient. Use the full suite for the release gate.

`check-coverage.sh` merges every raw profile from the current SwiftPM coverage
directory and loads all test executables, including separate macOS test bundles.
It counts unique executable lines under `Sources/` from LLVM's LCOV records.
A line shared by nested Swift closures is counted once, matching HTML coverage
reports rather than LLVM JSON summaries that can count overlapping regions.
Dependencies and tests are excluded; all five Swift source targets must appear.
Missing profiles, missing targets, export failures, and coverage below 85% fail
the check. LLVM tools come from the selected Swift toolchain on both platforms.

To generate a report without enforcing the threshold:

```bash
./Scripts/coverage-report.sh
```

Both commands write:

- `.build/coverage/coverage.lcov` — line and function data for coverage tools.
- `.build/coverage/summary.txt` — source line coverage by target and overall.
- `.build/coverage/summary.json` — machine-readable counts and percentage.
- `.build/coverage/coverage.profdata` — merged profiles.
- `.build/coverage/html/index.html` — optional HTML when `genhtml` is installed.

Python 3.9 or later and the Swift toolchain are required. Install `lcov` for
optional HTML (`brew install lcov` on macOS). A filtered test run is useful for
investigation but does not represent full-suite coverage.

GitHub Actions uses the same scripts in `.github/workflows/ci.yml` and
`.github/workflows/coverage.yml`. The Coverage workflow uploads macOS and Linux
reports as artifacts.
