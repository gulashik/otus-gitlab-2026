#!/usr/bin/env bash
# Start the local-only browser control panel for the GitLab learning lab.
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repository_root"

command -v python3 >/dev/null 2>&1 || {
  printf 'python3 is required to run the local dashboard.\n' >&2
  exit 1
}

# The Python server binds only to 127.0.0.1 and creates a fresh browser token
# for each run. It never accepts arbitrary shell commands from the browser.
exec python3 scripts/lab-dashboard-server.py

