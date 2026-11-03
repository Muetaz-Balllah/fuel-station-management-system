#!/usr/bin/env bash
set -euo pipefail
export WRITE_RENDER_REDIRECTS=false
exec bash "$(dirname "$0")/build_web.sh"
