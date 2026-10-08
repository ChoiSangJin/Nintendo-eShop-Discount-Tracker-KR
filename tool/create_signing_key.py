#!/usr/bin/env python3
"""Create a private, persistent signing key outside the checkout (once)."""
import os
from pathlib import Path
import secrets
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
signing_dir = Path(sys.argv[1] if len(sys.argv) > 1 else root.parent / "signing" / "switch-tracker")
signing_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
key = signing_dir / "release.jks"
password_file = signing_dir / "password"
if key.exists() != password_file.exists():
    raise SystemExit("Signing key/password state is incomplete. Preserve existing files and restore the missing part.")
if not key.exists():
    password = secrets.token_urlsafe(36)
    password_file.write_text(password)
    password_file.chmod(0o600)
    subprocess.run([
        "keytool", "-genkeypair", "-noprompt", "-keystore", str(key),
        "-storetype", "PKCS12", "-alias", "switch-tracker", "-keyalg", "RSA",
        "-keysize", "3072", "-validity", "10000", "-storepass:env", "SIGNING_PASSWORD",
        "-keypass:env", "SIGNING_PASSWORD", "-dname", "CN=Switch Sale Tracker KR",
    ], env=dict(os.environ, SIGNING_PASSWORD=password), check=True)
    key.chmod(0o600)
else:
    password = password_file.read_text().strip()
properties = root / "android" / "key.properties"
if properties.exists():
    print("Existing android/key.properties preserved. Use the existing signing configuration.")
    raise SystemExit(0)
properties.write_text(f"storeFile={key}\nstorePassword={password}\nkeyAlias=switch-tracker\nkeyPassword={password}\n")
properties.chmod(0o600)
print(f"Signing configured. Keep the key and password private: {signing_dir}")
