#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ -f package.json ]] && grep -q '"next"' package.json 2>/dev/null; then
  echo "Error: this folder looks like Next.js. Use the Flutter frontend (pubspec.yaml), not npm/Next." >&2
  exit 1
fi

if [[ ! -f pubspec.yaml ]]; then
  echo "Error: pubspec.yaml not found. Set Vercel Root Directory to the Flutter frontend folder." >&2
  exit 1
fi

if [[ -z "${API_BASE_URL:-}" ]]; then
  echo "Error: set API_BASE_URL (Render API URL, no trailing slash)." >&2
  exit 1
fi

if ! command -v flutter >/dev/null 2>&1; then
  FLUTTER_HOME="${FLUTTER_HOME:-/tmp/flutter}"
  if [[ ! -x "${FLUTTER_HOME}/bin/flutter" ]]; then
    git clone https://github.com/flutter/flutter.git -b stable --depth 1 "$FLUTTER_HOME"
  fi
  export PATH="${FLUTTER_HOME}/bin:${PATH}"
  flutter config --enable-web
  flutter precache --web
fi

flutter pub get
flutter build web --release --dart-define="API_BASE_URL=${API_BASE_URL}"

if [[ "${WRITE_RENDER_REDIRECTS:-}" == "true" ]]; then
  printf '%s\n' '/*    /index.html   200' > build/web/_redirects
fi
