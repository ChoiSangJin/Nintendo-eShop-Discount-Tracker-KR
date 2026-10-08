#!/usr/bin/env python3
"""Fail if an APK contains anything other than the requested ARM64 native ABI."""
from pathlib import Path
import hashlib
import sys
import zipfile

apk = Path(sys.argv[1])
with zipfile.ZipFile(apk) as archive:
    bad = archive.testzip()
    if bad:
        raise SystemExit(f"Corrupt APK member: {bad}")
    libs = [entry for entry in archive.namelist() if entry.startswith("lib/") and entry.endswith(".so")]
    abis = {entry.split("/")[1] for entry in libs}
    assert abis == {"arm64-v8a"}, f"Unexpected native ABIs: {abis}"
    assert "lib/arm64-v8a/libapp.so" in libs, "Release Dart app missing"
    assert "lib/arm64-v8a/libflutter.so" in libs, "Flutter engine missing"
    assert "AndroidManifest.xml" in archive.namelist(), "Android manifest missing"
digest = hashlib.sha256(apk.read_bytes()).hexdigest()
apk.with_suffix(".apk.sha256").write_text(f"{digest}  {apk.name}\n")
print(f"ARM64-only APK verified: {apk.stat().st_size / 1048576:.2f} MiB; SHA-256 {digest}")
