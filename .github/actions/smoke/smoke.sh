#!/usr/bin/env bash
# Polls a freshly deployed Worker until it answers, or gives up.
#
# Cloudflare propagates a deploy across the edge in seconds, but not
# instantly and not uniformly, so the first request after `wrangler` returns
# can legitimately miss. Retrying separates "slow" from "broken"; failing on
# the first attempt would make this a flake generator and it would be
# switched off within a week.
#
# Usage: ./smoke.sh <url> [attempts] [delay]

set -euo pipefail

URL="${1:?usage: smoke.sh <url> [attempts] [delay]}"
ATTEMPTS="${2:-20}"
DELAY="${3:-5}"

for i in $(seq 1 "$ATTEMPTS"); do
  STATUS=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$URL" || echo "000")

  if [ "$STATUS" = "200" ]; then
    echo "OK — $URL answered 200 on attempt $i"
    exit 0
  fi

  echo "attempt $i/$ATTEMPTS: $STATUS"
  sleep "$DELAY"
done

echo "::error::$URL never answered 200 after $((ATTEMPTS * DELAY))s"
exit 1

# Stronger version, once the build writes a version.json holding the git SHA.
# Reaching 200 proves something is being served; it does not prove it is this
# commit, so a deploy that silently failed to replace the previous one still
# passes the check above.
#
#   EXPECTED="${GITHUB_SHA}"
#   SHA=$(curl -sf --max-time 10 "$URL/version.json" | jq -r .sha || echo "")
#   [ "$SHA" = "$EXPECTED" ] && exit 0
