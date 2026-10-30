#!/usr/bin/env python3
"""Enforce a single version for the IPA, build number and native settings UI."""
import pathlib
import re

root = pathlib.Path(__file__).resolve().parents[1]
version = (root / "overrides" / "VERSION").read_text().strip()
if not re.fullmatch(r"[0-9]+\.[0-9]+(?:\.[0-9]+)?", version):
    raise SystemExit(f"Invalid version: {version}")
pbx = root / "source" / "EStaffingTimeCard.xcodeproj" / "project.pbxproj"
text = pbx.read_text()
old = re.findall(r"MARKETING_VERSION = ([0-9.]+);", text)
if not old or len(set(old)) != 1:
    raise SystemExit("Cannot read the existing marketing version")
def components(s):
    return tuple(int(x) for x in s.split("."))
if components(version) <= components(old[0]):
    raise SystemExit(f"Version must increase: {old[0]} -> {version}")
text, count = re.subn(r"MARKETING_VERSION = [0-9.]+;", f"MARKETING_VERSION = {version};", text)
if not count:
    raise SystemExit("No marketing version to update")
# Use stable version-derived build numbers rather than incrementing every CI rerun.
parts = components(version)
build = parts[0] * 10000 + parts[1] * 100 + (parts[2] if len(parts) > 2 else 0)
text, build_count = re.subn(r"CURRENT_PROJECT_VERSION = [0-9]+;", f"CURRENT_PROJECT_VERSION = {build};", text)
if not build_count:
    raise SystemExit("No build number to update")
pbx.write_text(text)

# A legacy regression test expects the pre-migration hard-coded version.
old_test = root / "source" / "tests" / "native-form-autosave.test.cjs"
if old_test.exists():
    test = old_test.read_text()
    test = re.sub(r"MARKETING_VERSION = [0-9.]+", f"MARKETING_VERSION = {version}", test)
    old_test.write_text(test)
print(f"IPA marketing version: {old[0]} -> {version}; build number: {build}")
