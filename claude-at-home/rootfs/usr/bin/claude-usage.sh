#!/bin/bash
# Vendored unmodified from Infraviored/antigravity-skills (statusline tools).
# Only the token-handling and caching logic below is load-bearing here; the
# bar/line/prom output modes are unused by the app but kept intact so this
# stays a straight copy that can be re-synced.
#
# claude-usage.sh -- account-wide Claude usage, outside any Claude Code session.
#
# The statusline gets its numbers handed to it on stdin, which means they only
# exist while a session is rendering. This asks the account directly, so it
# works from cron, a wall display, Home Assistant, or anything else.
#
#   GET https://api.anthropic.com/api/oauth/usage
#   Authorization: Bearer <claudeAiOauth.accessToken from ~/.claude/.credentials.json>
#
# Verified against the live statusline: five_hour.utilization and
# seven_day.utilization are the same two numbers the bars draw, and
# `resets_at` is the same ISO timestamp. Everything here is account-scoped --
# nothing is per-session, per-chat or per-directory.
#
# TOKEN HANDLING -- the thing that decides whether this can run unattended
#
# accessToken lives ~5-12h. refreshToken lives ~11 days AND is rotated on every
# use, so each refresh pushes the 11 days out again: a process that refreshes
# even once a week never needs a manual re-login. That is what makes a
# long-running poller possible at all.
#
# Refreshing is OFF by default, because it is the one genuinely dangerous thing
# here. A refresh token is single-use: the moment the server accepts it, it is
# dead. If the new pair is not persisted -- crash, full disk, or Claude Code
# refreshing concurrently and its write landing last -- there is no going back
# and no backup that helps, because the file you would restore holds a token
# the server has already invalidated. You would have to `claude login` again.
#
# When enabled (--refresh or CLAUDE_USAGE_AUTOREFRESH=1) the risk is cut down to:
#   * refresh only inside the last hour of the token's life, so this and Claude
#     Code are rarely both trying,
#   * flock on the credentials file, so two copies of THIS script never race,
#   * write temp + fsync + rename, so the file is never half-written,
#   * the rest of the JSON (mcpOAuth etc.) is preserved, not rewritten.
# The residual race is Claude Code refreshing in the same second. Unlikely, not
# impossible. Losing it costs one `claude login`.
#
# CACHING
#
# The endpoint rate-limits aggressively -- six calls in a few seconds returns
# 429. Responses are cached for CLAUDE_USAGE_TTL seconds (default 300) and a
# 429 or network failure serves the last good response instead of a blank
# dashboard. Polling every 10 minutes is comfortably inside this.
#
# Usage: claude-usage.sh [bar|line|json|env|prom] [--refresh] [--force]
#        (default: line)

set -uo pipefail

CREDS="${CLAUDE_CREDENTIALS:-$HOME/.claude/.credentials.json}"
ENDPOINT="${CLAUDE_USAGE_ENDPOINT:-https://api.anthropic.com/api/oauth/usage}"
TOKEN_URL="${CLAUDE_TOKEN_ENDPOINT:-https://console.anthropic.com/v1/oauth/token}"
CLIENT_ID="${CLAUDE_OAUTH_CLIENT_ID:-9d1c250a-e61b-44d9-88ed-5944d1962f5e}"
CACHE="${CLAUDE_USAGE_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/claude-usage.json}"
TTL="${CLAUDE_USAGE_TTL:-300}"
REFRESH="${CLAUDE_USAGE_AUTOREFRESH:-0}"
REFRESH_MARGIN="${CLAUDE_USAGE_REFRESH_MARGIN:-3600}"   # refresh inside last hour

mode=line; force=0
for a in "$@"; do
  case "$a" in
    --refresh) REFRESH=1 ;;
    --force)   force=1 ;;
    bar|line|json|env|prom) mode=$a ;;
    -h|--help) sed -n '2,60p' "$0"; exit 0 ;;
    *) printf 'unknown argument: %s\n' "$a" >&2; exit 1 ;;
  esac
done

die() { printf '%s\n' "$*" >&2; exit "${2:-1}"; }

[ -r "$CREDS" ] || die "no readable credentials at $CREDS" 2
command -v jq   >/dev/null || die "jq is required" 2
command -v curl >/dev/null || die "curl is required" 2

mkdir -p "$(dirname "$CACHE")"

now_ms() { echo $(( $(date +%s) * 1000 )); }

# Exchange the rotating refresh token for a new pair and persist both.
# Single-use: once the server answers 200 the old token is already dead, so the
# write-back is not optional and must not be interrupted.
do_refresh() {
  local rt new at_new rt_new exp_new tmp
  rt=$(jq -r '.claudeAiOauth.refreshToken // empty' "$CREDS")
  [ -n "$rt" ] || return 1
  new=$(curl -sS --fail-with-body -m 30 "$TOKEN_URL" \
        -H 'Content-Type: application/json' \
        -d "$(jq -nc --arg t "$rt" --arg c "$CLIENT_ID" \
              '{grant_type:"refresh_token",refresh_token:$t,client_id:$c}')") || {
    printf 'refresh request failed: %s\n' "$(head -c 300 <<<"$new")" >&2; return 1; }
  at_new=$(jq -r '.access_token  // empty' <<<"$new")
  rt_new=$(jq -r '.refresh_token // empty' <<<"$new")
  [ -n "$at_new" ] && [ -n "$rt_new" ] || {
    printf 'refresh returned no token pair: %s\n' "$(head -c 300 <<<"$new")" >&2; return 1; }
  exp_new=$(( $(now_ms) + $(jq -r '.expires_in // 28800' <<<"$new") * 1000 ))

  # Merge into the existing file -- mcpOAuth and anything else must survive.
  tmp="$CREDS.tmp.$$"
  jq --arg at "$at_new" --arg rt "$rt_new" --argjson ex "$exp_new" \
     '.claudeAiOauth.accessToken=$at
      | .claudeAiOauth.refreshToken=$rt
      | .claudeAiOauth.expiresAt=$ex' "$CREDS" > "$tmp" || { rm -f "$tmp"; return 1; }
  jq -e '.claudeAiOauth.accessToken' "$tmp" >/dev/null || { rm -f "$tmp"; return 1; }
  chmod 600 "$tmp"
  sync "$tmp" 2>/dev/null || true
  mv -f "$tmp" "$CREDS" || return 1
  tok=$at_new
  return 0
}

tok=$(jq -r '.claudeAiOauth.accessToken // empty' "$CREDS")
exp=$(jq -r '.claudeAiOauth.expiresAt // 0' "$CREDS")
[ -n "$tok" ] || die "no claudeAiOauth.accessToken in $CREDS" 2

left_ms=$(( exp - $(now_ms) ))
if [ "$REFRESH" = 1 ] && [ "$exp" -gt 0 ] && [ "$left_ms" -lt $(( REFRESH_MARGIN * 1000 )) ]; then
  # Serialise against other copies of this script. 200 held under flock so a
  # concurrent instance re-reads the freshly written file instead of reusing
  # the token that was just invalidated.
  exec 9>"$CREDS.lock"
  if flock -w 30 9; then
    exp=$(jq -r '.claudeAiOauth.expiresAt // 0' "$CREDS")
    if [ $(( exp - $(now_ms) )) -lt $(( REFRESH_MARGIN * 1000 )) ]; then
      do_refresh || printf 'warning: token refresh failed, using existing token\n' >&2
    else
      tok=$(jq -r '.claudeAiOauth.accessToken' "$CREDS")
    fi
  fi
  exec 9>&-
fi

if [ "$exp" -gt 0 ] && [ "$(now_ms)" -ge "$exp" ]; then
  die "access token expired. Run any Claude Code command, or re-run with --refresh." 3
fi

# Serve from cache unless it is stale. Keeps a 10-minute cron and an
# every-second `watch` equally safe against the endpoint's rate limit.
resp=""
if [ "$force" = 0 ] && [ -s "$CACHE" ]; then
  age=$(( $(date +%s) - $(stat -c %Y "$CACHE" 2>/dev/null || echo 0) ))
  [ "$age" -lt "$TTL" ] && resp=$(cat "$CACHE")
fi

if [ -z "$resp" ]; then
  body=$(curl -sS -m 20 -w '\n%{http_code}' "$ENDPOINT" \
    -H "Authorization: Bearer $tok" \
    -H "anthropic-beta: oauth-2025-04-20" \
    -H "Accept: application/json" 2>&1)
  code=${body##*$'\n'}; body=${body%$'\n'*}
  if [ "$code" = 200 ] && jq -e . >/dev/null 2>&1 <<<"$body"; then
    printf '%s' "$body" > "$CACHE.tmp.$$" && mv -f "$CACHE.tmp.$$" "$CACHE"
    resp=$body
  elif [ -s "$CACHE" ]; then
    # 429, 5xx or a dead link: a slightly old number beats an empty panel.
    printf 'warning: fetch failed (HTTP %s), serving cache from %s\n' \
      "$code" "$(date -d "@$(stat -c %Y "$CACHE")" '+%H:%M:%S')" >&2
    resp=$(cat "$CACHE")
  else
    die "request failed (HTTP $code): $(head -c 300 <<<"$body")" 4
  fi
fi

# five_hour / seven_day are the canonical pair. `limits[]` carries the same
# numbers plus per-model weekly scopes, which are null on most plans.
read -r p5 r5 p7 r7 extra_pct <<<"$(jq -r '
  [ (.five_hour.utilization // 0)
  , (.five_hour.resets_at   // "")
  , (.seven_day.utilization // 0)
  , (.seven_day.resets_at   // "")
  , (.extra_usage.utilization // 0)
  ] | @tsv' <<<"$resp" | tr '\t' ' ')"

secs_until() { # ISO8601 -> seconds from now, 0 if empty/past
  [ -n "${1:-}" ] || { echo 0; return; }
  local t; t=$(date -d "$1" +%s 2>/dev/null) || { echo 0; return; }
  local d=$(( t - $(date +%s) )); [ "$d" -lt 0 ] && d=0; echo "$d"
}

fmt_until() {
  local l=$1 d h m
  [ "$l" -le 0 ] && { printf 'now'; return; }
  d=$(( l / 86400 )); h=$(( (l % 86400) / 3600 )); m=$(( (l % 3600) / 60 ))
  if   [ "$d" -gt 0 ]; then printf '%dd%02dh' "$d" "$h"
  elif [ "$h" -gt 0 ]; then printf '%dh%02dm' "$h" "$m"
  else                      printf '%dm' "$m"; fi
}

s5=$(secs_until "$r5"); s7=$(secs_until "$r7")

case "$mode" in
  json) printf '%s\n' "$resp" | jq . ;;

  env)
    printf 'CLAUDE_5H_PCT=%s\nCLAUDE_5H_RESETS_AT=%s\nCLAUDE_5H_RESETS_IN=%s\n' "${p5%.*}" "$r5" "$s5"
    printf 'CLAUDE_7D_PCT=%s\nCLAUDE_7D_RESETS_AT=%s\nCLAUDE_7D_RESETS_IN=%s\n' "${p7%.*}" "$r7" "$s7"
    printf 'CLAUDE_EXTRA_PCT=%s\n' "${extra_pct%.*}" ;;

  prom)
    echo '# HELP claude_usage_ratio Fraction of the plan limit consumed.'
    echo '# TYPE claude_usage_ratio gauge'
    awk -v a="$p5" -v b="$p7" 'BEGIN{printf "claude_usage_ratio{window=\"5h\"} %.4f\nclaude_usage_ratio{window=\"7d\"} %.4f\n", a/100, b/100}'
    echo '# HELP claude_usage_reset_seconds Seconds until the window resets.'
    echo '# TYPE claude_usage_reset_seconds gauge'
    printf 'claude_usage_reset_seconds{window="5h"} %s\nclaude_usage_reset_seconds{window="7d"} %s\n' "$s5" "$s7" ;;

  line)
    printf '5h %3s%%  resets in %-7s   7d %3s%%  resets in %s\n' \
      "${p5%.*}" "$(fmt_until "$s5")" "${p7%.*}" "$(fmt_until "$s7")" ;;

  bar)
    # Same two-tone encoding as the statusline: how much you spent (█) against
    # how much of the window has already elapsed. ▒ = unspent slack, orange █ =
    # spent ahead of pace. Colour is only emitted to a terminal.
    if [ -t 1 ]; then C_SPENT=$'\033[38;5;250m'; C_RES=$'\033[38;5;39m'
                      C_CRED=$'\033[38;5;208m'; C_LOCK=$'\033[38;5;237m'
                      C_DIM=$'\033[38;5;244m';  C_OFF=$'\033[0m'
    else              C_SPENT=; C_RES=; C_CRED=; C_LOCK=; C_DIM=; C_OFF=; fi
    rep() { local s= i; for ((i=0;i<$2;i++)); do s+=$1; done; printf '%s' "$s"; }
    draw() { # label  used%  secs-left  window-secs
      local u=${2%.*} el n=24 lo hi g col
      el=$(( ( (($4 - $3) * 100) + $4/2 ) / $4 ))
      [ "$el" -lt 0 ] && el=0; [ "$el" -gt 100 ] && el=100
      [ "$u" -gt 100 ] && u=100
      if [ "$u" -le "$el" ]; then lo=$u; hi=$el; g="▒"; col=$C_RES
      else                        lo=$el; hi=$u;  g="█"; col=$C_CRED; fi
      lo=$(( (lo*n+50)/100 )); hi=$(( (hi*n+50)/100 ))
      [ "$hi" -gt "$n" ] && hi=$n; [ "$lo" -gt "$hi" ] && lo=$hi
      printf '%s%s %3s%% %s%s%s%s%s%s%s  %s%s%s\n' \
        "$C_DIM" "$1" "$u" "$C_SPENT" "$(rep █ $lo)" \
        "$col" "$(rep "$g" $((hi-lo)))" "$C_LOCK" "$(rep ░ $((n-hi)))" "$C_OFF" \
        "$C_DIM" "$(fmt_until "$3") left" "$C_OFF"
    }
    LC_ALL=C.UTF-8 draw 5h "$p5" "$s5" 18000
    LC_ALL=C.UTF-8 draw 7d "$p7" "$s7" 604800 ;;

esac
