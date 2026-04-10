#!/usr/bin/env bash
# Display loop for the window-summary tmux pane.
# Shows the cached summary for the window this pane lives in.

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

TITLE="window-summary"

cleanup() {
    printf '\033[?25h\n' 2>/dev/null
    tput cnorm 2>/dev/null
    stty echo 2>/dev/null
}
trap cleanup EXIT INT TERM HUP

tput civis 2>/dev/null
stty -echo 2>/dev/null
printf '\033[?25l'

tmux select-pane -T "$TITLE" 2>/dev/null || true

# Pin every tmux query to OUR pane, not the currently-active one.
# Without -t, tmux display-message returns info about whichever pane
# is active — which for a passive sidebar is almost never us.
SELF_PANE="${TMUX_PANE:-}"
if [ -z "$SELF_PANE" ]; then
    SELF_PANE=$(tmux display-message -p '#{pane_id}' 2>/dev/null || echo "")
fi

MY_SESSION=$(tmux display-message -p -t "$SELF_PANE" '#S' 2>/dev/null || echo "?")
MY_WINDOW_ID=$(tmux display-message -p -t "$SELF_PANE" '#{window_id}' 2>/dev/null || echo "")
TARGET="${MY_SESSION}:${MY_WINDOW_ID}"
CACHE_FILE=$(ws_cache_path "$TARGET")

# Colors
C_ACCENT=$'\033[38;5;81m'
C_DIM=$'\033[2m'
C_BOLD=$'\033[1m'
C_RESET=$'\033[0m'

last_content=""
last_dims=""
last_name=""

render() {
    local content="$1"
    local cols rows win_name
    cols=$(tmux display-message -p -t "$SELF_PANE" '#{pane_width}' 2>/dev/null || echo 40)
    rows=$(tmux display-message -p -t "$SELF_PANE" '#{pane_height}' 2>/dev/null || echo 6)
    win_name=$(tmux display-message -t "$TARGET" -p '#W' 2>/dev/null || echo "?")

    local dims="${cols}x${rows}"
    if [ "$content" = "$last_content" ] && [ "$dims" = "$last_dims" ] && [ "$win_name" = "$last_name" ]; then
        return
    fi
    last_content="$content"
    last_dims="$dims"
    last_name="$win_name"

    local header_budget=2
    local body_rows=$(( rows - header_budget ))
    (( body_rows < 1 )) && body_rows=1
    local wrap_width=$(( cols - 2 ))
    (( wrap_width < 8 )) && wrap_width=8

    # Clear and position.
    printf '\033[2J\033[H'
    printf '%s▎%s %s%s%s\n' "$C_ACCENT" "$C_RESET" "$C_BOLD" "$win_name" "$C_RESET"
    printf '%s%s%s\n' "$C_DIM" "$(printf '─%.0s' $(seq 1 "$wrap_width"))" "$C_RESET"
    printf '%s\n' "$content" | fold -s -w "$wrap_width" | head -n "$body_rows"
}

while true; do
    if [ -f "$CACHE_FILE" ]; then
        content=$(cat "$CACHE_FILE" 2>/dev/null)
        [ -z "$content" ] && content="…"
    else
        content="… (waiting for first summary)"
    fi
    render "$content"
    sleep 1
done
