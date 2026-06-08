#!/bin/sh
# mediamtx-watchdog.sh — restart mediamtx when the fpv stream is dead even though
# the capture device is present. Run periodically by mediamtx-watchdog.timer.
#
# Logic:
#   - device missing            → a restart can't help (USB not enumerated). Skip.
#   - stream OK (ffprobe)        → reset failure counter, exit.
#   - stream dead N times in a row (default 3, ~90s) → restart mediamtx.
#
# The N-in-a-row threshold avoids restarting on brief reconnects; the restart
# itself acts as a cooldown (counter is reset afterwards).
set -u

DEV="${FPV_DEVICE:-/dev/video0}"
STREAM="${FPV_STREAM:-rtsp://localhost:8554/fpv}"
THRESHOLD="${FPV_FAIL_THRESHOLD:-3}"
STATE="/run/mediamtx-watchdog.fails"

# Device not present yet → restarting mediamtx would not help. Reset and exit.
if [ ! -e "$DEV" ]; then
    rm -f "$STATE"
    exit 0
fi

# Probe the live stream. `timeout` caps the wall-clock so the check can never hang.
if timeout 10 ffprobe -v error -rtsp_transport tcp \
        -i "$STREAM" -show_entries stream=codec_type -of csv=p=0 >/dev/null 2>&1; then
    rm -f "$STATE"
    exit 0
fi

# Unhealthy → increment consecutive-failure counter.
n=$(cat "$STATE" 2>/dev/null || echo 0)
n=$((n + 1))
echo "$n" > "$STATE"

if [ "$n" -ge "$THRESHOLD" ]; then
    logger -t mediamtx-watchdog "fpv stream down (device $DEV present) after $n checks → restarting mediamtx"
    systemctl restart mediamtx
    rm -f "$STATE"
fi
