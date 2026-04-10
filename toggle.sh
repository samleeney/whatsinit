#!/usr/bin/env bash
# Create (or remove) the window-summary pane in a tmux window.
# Splits below the existing agent-sidebar pane. Idempotent.
# Usage: toggle.sh [session:window]

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TITLE="window-summary"
HEIGHT="${WS_PANE_HEIGHT:-6}"
TARGET="${1:-}"

target_flag=()
[ -n "$TARGET" ] && target_flag=(-t "$TARGET")

list_panes() {
    tmux list-panes "${target_flag[@]}" -F '#{pane_id}|#{pane_title}' 2>/dev/null
}

find_pane_by_title() {
    local want="$1"
    list_panes | awk -F'|' -v want="$want" '$2 == want {print $1; exit}'
}

existing=$(find_pane_by_title "$TITLE")
if [ -n "$existing" ]; then
    # Genuine toggle: kill it. Re-run the script to recreate.
    tmux kill-pane -t "$existing"
    exit 0
fi

agent_sidebar=$(find_pane_by_title "agent-sidebar")
if [ -z "$agent_sidebar" ]; then
    echo "window-summary: no agent-sidebar pane found in target; skipping." >&2
    exit 0
fi

new_pane=$(tmux split-window -v -t "$agent_sidebar" -l "$HEIGHT" \
    -PF '#{pane_id}' "$SCRIPT_DIR/pane.sh")
tmux select-pane -t "$new_pane" -T "$TITLE" 2>/dev/null || true
