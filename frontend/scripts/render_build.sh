#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ -z "${API_BASE_URL:-}" ]]; then
  echo "Error: set API_BASE_URL in Render (API service URL, no trailing slash)." >&2
  exit 1
fi

if ! command -v flutter >/dev/null 2>&1; then
  FLUTTER_HOME="${FLUTTER_HOME:-/opt/render/project/.flutter}"
  if [[ ! -x "${FLUTTER_HOME}/bin/flutter" ]]; then
    git clone https://github.com/flutter/flutter.git -b stable --depth 1 "$FLUTTER_HOME"
  fi
  export PATH="${FLUTTER_HOME}/bin:${PATH}"
  flutter config --enable-web
  flutter precache --web
fi

flutter pub get
flutter build web --release --dart-define="API_BASE_URL=${API_BASE_URL}"

# SPA routing on Render static sites
printf '%s\n' '/*    /index.html   200' > build/web/_redirects
