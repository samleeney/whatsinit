#!/usr/bin/env bash
# Shared helpers for the window-summary sidebar feature.

WS_CACHE_DIR="${WS_CACHE_DIR:-$HOME/.cache/tmux-window-summary}"
WS_MODEL="${WS_MODEL:-gpt-5.3-codex-spark}"
WS_REFRESH_AGE="${WS_REFRESH_AGE:-600}"   # seconds
WS_CAPTURE_LINES="${WS_CAPTURE_LINES:-80}"
WS_MAX_CONTEXT_BYTES="${WS_MAX_CONTEXT_BYTES:-12000}"

ws_cache_path() {
    local target="$1"          # "session_name:@window_id"
    local sanitized
    sanitized="${target//[^a-zA-Z0-9_:@-]/_}"
    sanitized="${sanitized//:/__}"
    sanitized="${sanitized//@/win}"
    printf '%s/%s.txt\n' "$WS_CACHE_DIR" "$sanitized"
}

ws_is_excluded_title() {
    case "$1" in
        agent-sidebar|window-summary|file-tree) return 0 ;;
        *) return 1 ;;
    esac
}

# Grounding info for one pane: cwd, git branch, last commit subject.
# These are stable signals about *what project this is*, independent of
# whatever noisy text happens to be in the scrollback.
ws_pane_grounding() {
    local pid="$1"
    local cwd branch last_commit
    cwd=$(tmux display-message -p -t "$pid" '#{pane_current_path}' 2>/dev/null || echo "")
    [ -z "$cwd" ] && { echo "cwd: (unknown)"; return; }
    echo "cwd: $cwd"
    if command -v git >/dev/null 2>&1; then
        branch=$(git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null || true)
        last_commit=$(git -C "$cwd" log -1 --format='%s' 2>/dev/null || true)
        [ -n "$branch" ] && echo "git branch: $branch"
        [ -n "$last_commit" ] && echo "last commit: $last_commit"
    fi
}

# Build a multi-pane context blob for a window target.
ws_capture_window_context() {
    local target="$1"
    local pane_list pid title cmd active active_tag cap grounding
    pane_list=$(tmux list-panes -t "$target" \
        -F '#{pane_id}|#{pane_title}|#{pane_current_command}|#{pane_active}' 2>/dev/null) || return 1

    local out=""
    while IFS='|' read -r pid title cmd active; do
        [ -z "$pid" ] && continue
        ws_is_excluded_title "$title" && continue
        active_tag=""
        [ "$active" = "1" ] && active_tag=" (active)"
        grounding=$(ws_pane_grounding "$pid")
        cap=$(tmux capture-pane -p -t "$pid" -S "-$WS_CAPTURE_LINES" -J 2>/dev/null || true)
        out+="=== pane $pid — ${cmd:-?}${active_tag} ==="$'\n'
        out+="${grounding}"$'\n'
        out+="--- scrollback (most recent $WS_CAPTURE_LINES lines) ---"$'\n'
        out+="${cap}"$'\n\n'
    done <<< "$pane_list"

    # Trim from the front if oversized, keeping the most recent content.
    if (( ${#out} > WS_MAX_CONTEXT_BYTES )); then
        out="…(truncated)…"$'\n'"${out: -WS_MAX_CONTEXT_BYTES}"
    fi
    printf '%s' "$out"
}

# True if window has at least one non-excluded pane with non-empty content.
ws_has_work_content() {
    local target="$1"
    local pane_list pid title cap
    pane_list=$(tmux list-panes -t "$target" \
        -F '#{pane_id}|#{pane_title}' 2>/dev/null) || return 1
    while IFS='|' read -r pid title; do
        [ -z "$pid" ] && continue
        ws_is_excluded_title "$title" && continue
        cap=$(tmux capture-pane -p -t "$pid" -S -40 -J 2>/dev/null | tr -d '[:space:]')
        if [ -n "$cap" ]; then
            return 0
        fi
    done <<< "$pane_list"
    return 1
}

# List "session_name<TAB>@window_id" for every window that contains a
# window-summary pane (i.e. where the feature is active).
ws_list_active_windows() {
    tmux list-panes -a -F '#{session_name}|#{window_id}|#{pane_title}' 2>/dev/null \
        | awk -F'|' '$3 == "window-summary" { print $1"\t"$2 }' \
        | sort -u
}
