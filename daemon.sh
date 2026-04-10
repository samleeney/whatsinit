#!/usr/bin/env bash
# Background daemon that regenerates window summaries.
# Single-instance via flock. Walk every window that has a window-summary pane,
# refresh when missing (and has content) or older than WS_REFRESH_AGE.

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

LOCK="/tmp/tmux-window-summary-daemon.$UID.lock"
exec 200>"$LOCK"
if ! flock -n 200; then
    exit 0
fi

# Make sure child generations can find the scripts.
export PATH="$SCRIPT_DIR:$PATH"

TICK="${WS_DAEMON_TICK:-15}"     # seconds between polls
MAX_PARALLEL="${WS_MAX_PARALLEL:-2}"

now_epoch() { date +%s; }
file_age()  {
    local mtime
    mtime=$(stat -c %Y "$1" 2>/dev/null || echo 0)
    echo $(( $(now_epoch) - mtime ))
}

throttle() {
    # Wait until the number of background jobs drops below MAX_PARALLEL.
    while (( $(jobs -rp | wc -l) >= MAX_PARALLEL )); do
        sleep 0.2
    done
}

while true; do
    # Exit if tmux server is gone (don't spin forever after shutdown).
    if ! tmux list-sessions >/dev/null 2>&1; then
        sleep "$TICK"
        continue
    fi

    while IFS=$'\t' read -r session window_id; do
        [ -z "$session" ] && continue
        target="${session}:${window_id}"
        cache_file=$(ws_cache_path "$target")

        should_gen=0
        if [ ! -f "$cache_file" ]; then
            if ws_has_work_content "$target"; then
                should_gen=1
            fi
        else
            age=$(file_age "$cache_file")
            if (( age > WS_REFRESH_AGE )); then
                should_gen=1
            fi
        fi

        if (( should_gen )); then
            throttle
            "$SCRIPT_DIR/generate.sh" "$target" >/dev/null 2>&1 &
        fi
    done < <(ws_list_active_windows)

    wait
    sleep "$TICK"
done
