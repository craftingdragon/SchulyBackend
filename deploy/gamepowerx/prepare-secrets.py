"""Add stable production keys required by the upgraded Schuly backend."""

import base64
import os
import secrets
from pathlib import Path


env_path = Path(__file__).with_name(".env")
lines = env_path.read_text().splitlines()
present = {line.split("=", 1)[0] for line in lines if "=" in line and not line.lstrip().startswith("#")}

for name in (
    "VAULT_MASTER_KEY", "DOCUMENTS_ENCRYPTION_KEY", "AVATAR_SIGNING_KEY",
    "LOCAL_LOGIN_SIGNING_KEY", "TWO_FACTOR_ENCRYPTION_KEY",
):
    if name not in present:
        lines.append(f"{name}={base64.b64encode(secrets.token_bytes(32)).decode('ascii')}")

temporary = env_path.with_name(".env.tmp")
temporary.write_text("\n".join(lines) + "\n")
os.chmod(temporary, 0o600)
os.replace(temporary, env_path)
print("Required Schuly key names are present; values were not displayed.")
