#!/usr/bin/env bash
# Reads the URL Cloudflare just wired up out of wrangler's ND-JSON output and
# writes it to $GITHUB_OUTPUT as `url`.
#
# Why bother, when the URL is a constant today: because it stops being one.
# `targets` holds the custom domain when the Worker has routes and the
# workers.dev URL when it does not, so the link on the Environments page and
# the host the smoke test hits both follow the Worker to its own domain
# without an edit here.
#
# The ND-JSON schema is meant for CI but is not a frozen public contract, so a
# fallback is passed in and used whenever the parse comes back empty. A change
# in wrangler's output format should cost an out-of-date link, not a red
# deploy that actually succeeded.
#
# Usage: ./worker-url.sh <ndjson-path> <fallback-url>

set -euo pipefail

NDJSON="${1:?usage: worker-url.sh <ndjson-path> <fallback-url>}"
FALLBACK="${2:?usage: worker-url.sh <ndjson-path> <fallback-url>}"

URL=""

if [ -f "$NDJSON" ]; then
  # -s slurps the newline-delimited objects into an array. `last` picks the
  # most recent operation, since a single command can emit several records.
  URL=$(jq -rs '
    [ .[] | select(.type == "deploy" or .type == "version-upload") ]
    | last
    | (.targets // [])[0] // empty
  ' "$NDJSON" 2>/dev/null || echo "")
fi

if [ -z "$URL" ]; then
  echo "::warning::No URL in wrangler output, falling back to $FALLBACK"
  URL="$FALLBACK"
fi

# A malformed value would be passed straight to curl and to the Environments
# page, so it is worth one check rather than a confusing failure downstream.
case "$URL" in
  https://*) ;;
  *) echo "::error::Not a usable URL: $URL"; exit 1 ;;
esac

echo "url=$URL" >> "$GITHUB_OUTPUT"
echo "Resolved: $URL"

# Worth doing once, on the first run: add a `cat "$NDJSON"` step and confirm
# the field names above match what your wrangler version actually emits. The
# fallback hides a mismatch by design, which also means it hides it from you.
