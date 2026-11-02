"""Add the server-side Schuly callback without replacing the identity-provider config."""

import os
import sys
from pathlib import Path

import yaml

path = Path(sys.argv[1])
callback = "https://schuly.gamepowerx.com/auth/external/gamepowerx/callback"
original = path.read_text()
config = yaml.safe_load(original)
clients = config["identity_providers"]["oidc"]["clients"]
matches = [client for client in clients if client["client_id"] == "schuly-mobile"]
assert len(matches) == 1, "Expected exactly one Schuly OIDC client"
if callback in matches[0]["redirect_uris"]:
    print("Schuly server callback already configured.")
    sys.exit(0)

lines = original.splitlines(keepends=True)
legacy = [i for i, line in enumerate(lines) if line.strip() == "- schulytest://callback"]
assert len(legacy) == 1, "Expected exactly one legacy Schuly callback line"
line = lines[legacy[0]]
indent = line[: len(line) - len(line.lstrip())]
lines.insert(legacy[0] + 1, f"{indent}- {callback}\n")
updated = "".join(lines)
expected = yaml.safe_load(original)
next(client for client in expected["identity_providers"]["oidc"]["clients"]
     if client["client_id"] == "schuly-mobile")["redirect_uris"].append(callback)
assert yaml.safe_load(updated) == expected, "Unexpected identity-provider configuration change"
temporary = path.with_name(path.name + ".schuly-update.tmp")
temporary.write_text(updated)
os.chmod(temporary, path.stat().st_mode & 0o777)
os.chown(temporary, path.stat().st_uid, path.stat().st_gid)
os.replace(temporary, path)
print("Added Schuly server callback; retained the legacy callback for rollback.")
