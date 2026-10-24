#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../frontend/libre_ecad_app"
flutter build web --release --no-web-resources-cdn "$@"
