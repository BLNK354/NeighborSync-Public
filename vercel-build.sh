#!/usr/bin/env bash
#
# Vercel build script for NeighborSync (Flutter Web).
#
# Vercel's build image has Node and git but NO Flutter SDK, and the repo
# contains only Dart source -- `build/` is gitignored. So a git-triggered
# deploy has nothing to serve unless this script fetches the SDK and
# produces `build/web` itself. That is the whole reason this file exists.
#
# It also compiles in the Supabase URL and anon key with --dart-define
# (lib/core/app_config.dart). They used to be written to a `.env` file
# shipped as a Flutter asset, which the live site then served publicly at
# /assets/.env (expert test HO-10). No file is written now. The values
# come from the Vercel project's Environment Variables.
#
# Required environment variables (Vercel -> Settings -> Environment
# Variables, set for Production AND Preview):
#
#   SUPABASE_URL        https://agroqojaqztufdjaefel.supabase.co
#   SUPABASE_ANON_KEY   the publishable/anon key (not secret by design)
#
# Optional:
#   FLUTTER_CHANNEL     defaults to "stable"
#
set -euo pipefail

FLUTTER_CHANNEL="${FLUTTER_CHANNEL:-stable}"

# Vercel preserves `.vercel/cache` between builds. Keeping the SDK and the
# pub cache there turns a ~4 minute cold build into ~1 minute warm. If the
# cache is empty (or Vercel drops it) the clone branch below just runs
# again, so this is an optimisation, never a dependency.
CACHE_DIR="${PWD}/.vercel/cache"
FLUTTER_DIR="${CACHE_DIR}/flutter"

echo "==> Checking Vercel environment variables"

# Fail loudly and immediately. A missing key here would otherwise surface
# much later as a blank white page in production with no console error
# worth reading.
: "${SUPABASE_URL:?not set -- add it under Vercel > Settings > Environment Variables}"
: "${SUPABASE_ANON_KEY:?not set -- add it under Vercel > Settings > Environment Variables}"


mkdir -p "${CACHE_DIR}"

if [ -x "${FLUTTER_DIR}/bin/flutter" ]; then
  echo "==> Reusing cached Flutter SDK"
  # Best-effort refresh. A network hiccup here must not fail the deploy --
  # the cached SDK is perfectly capable of building the app on its own.
  git -C "${FLUTTER_DIR}" fetch --depth 1 origin "${FLUTTER_CHANNEL}" || true
  git -C "${FLUTTER_DIR}" reset --hard "origin/${FLUTTER_CHANNEL}" || true
else
  echo "==> Cloning Flutter SDK (${FLUTTER_CHANNEL})"
  rm -rf "${FLUTTER_DIR}"
  git clone --depth 1 -b "${FLUTTER_CHANNEL}" \
    https://github.com/flutter/flutter.git "${FLUTTER_DIR}"
fi

export PATH="${FLUTTER_DIR}/bin:${PATH}"
export PUB_CACHE="${CACHE_DIR}/pub"

# The build runs as root and the SDK is a git checkout owned by a
# different uid than git expects. Without this, git refuses with
# "detected dubious ownership" and every flutter command fails.
git config --global --add safe.directory "${FLUTTER_DIR}" || true

flutter --version
flutter config --no-analytics > /dev/null 2>&1 || true

echo "==> flutter pub get"
flutter pub get

echo "==> flutter build web --release"
flutter build web --release \
  --dart-define=SUPABASE_URL="${SUPABASE_URL}" \
  --dart-define=SUPABASE_ANON_KEY="${SUPABASE_ANON_KEY}"

# The old .env asset must never come back into the site.
if [ -e build/web/assets/.env ]; then
  echo "ERROR: build/web/assets/.env exists -- it would be served publicly." >&2
  exit 1
fi

# Prove the artifact exists rather than trusting the exit code. If this
# is missing, Vercel would deploy an empty directory and serve 404s.
if [ ! -f build/web/index.html ]; then
  echo "ERROR: build/web/index.html was not produced." >&2
  exit 1
fi

echo "==> Build complete"
ls -la build/web
