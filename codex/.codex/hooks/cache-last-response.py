#!/usr/bin/env python3

import json
import os
from pathlib import Path
import sys
import tempfile


payload = json.load(sys.stdin)
session_id = payload.get("session_id")
message = payload.get("last_assistant_message")

if not isinstance(session_id, str) or not isinstance(message, str) or not message:
    raise SystemExit(0)

cache_home = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache"))
cache_dir = cache_home / "codex" / "responses"
cache_dir.mkdir(parents=True, exist_ok=True)

with tempfile.NamedTemporaryFile(
    mode="w",
    encoding="utf-8",
    dir=cache_dir,
    delete=False,
) as temporary:
    temporary.write(message)
    temporary_path = Path(temporary.name)

temporary_path.chmod(0o600)
temporary_path.replace(cache_dir / f"{session_id}.md")
