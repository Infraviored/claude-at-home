#!/usr/bin/env bash
# ==============================================================================
# Shared by the services: where Claude lives, and how its main session starts.
# Sourced, never run. Needs bashio (the services' interpreter) for the options.
# ==============================================================================

# /data is the add-on's persistent volume. Pointing HOME at it directly is
# what makes credentials, conversation history, background sessions and
# claude's own self-updates survive container rebuilds.
export HOME=/data
export PATH="/data/.local/bin:${PATH}"
# claude refuses --dangerously-skip-permissions as root without this. Every
# process that starts a session needs it: the daemon, and whatever asks it.
export IS_SANDBOX=1

# The main session's job, as the claude-main service last started it:
# {short, sessionId, flags}. The short id is what attach, logs and stop take.
readonly MAIN_STATE=/data/claude-at-home-main.json
# Present while bypass permissions is chosen but not yet accepted (below).
readonly BYPASS_PENDING=/data/claude-at-home-bypass-pending

session_name() {
    local s
    s="$(bashio::config 'session_name' 'claude-at-home')"
    [ -n "${s}" ] && [ "${s}" != "null" ] || s="claude-at-home"
    printf '%s' "${s}"
}

# Depending on Supervisor version the config map lands on one or the other
# of these; whichever exists is where Claude works.
workdir() {
    local candidate
    for candidate in /config /homeassistant; do
        [ -d "${candidate}" ] && { printf '%s' "${candidate}"; return; }
    done
    printf '/data'
}

# The permission_mode option in claude's own words. "auto" is the default: it
# runs unattended but still screens each tool call for risky actions and
# prompt injection, which is what you want for something living in your
# smart home.
permission_mode() {
    local mode
    mode="$(bashio::config 'permission_mode' 'auto')"
    case "${mode}" in
        "auto"|""|"null")     printf 'auto' ;;
        "bypass permissions") printf 'bypassPermissions' ;;
        "accept edits")       printf 'acceptEdits' ;;
        "plan")               printf 'plan' ;;
        "manual")             printf 'manual' ;;
        "never ask")          printf 'dontAsk' ;;
        *)
            bashio::log.warning "Unknown permission_mode '${mode}' — falling back to auto."
            printf 'auto'
            ;;
    esac
}

# Bypass permissions in a background session needs Claude Code's disclaimer
# accepted first, and only an interactive claude can show it. Until then the
# main session runs in auto mode, and the web terminal offers the disclaimer.
bypass_accepted() {
    jq -e '.skipDangerousModePermissionPrompt == true' /data/.claude/settings.json >/dev/null 2>&1 \
        || jq -e '.bypassPermissionsModeAccepted == true' /data/.claude.json >/dev/null 2>&1
}

# The short id of the main session's job, or nothing.
main_short() {
    [ -s "${MAIN_STATE}" ] && jq -r '.short // empty' "${MAIN_STATE}" 2>/dev/null
}
