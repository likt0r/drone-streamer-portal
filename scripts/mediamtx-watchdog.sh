#!/bin/sh
# mediamtx-watchdog.sh — restart mediamtx when the fpv stream is dead even though
# the capture device is present. Run periodically by mediamtx-watchdog.timer.
#
# Logic:
#   - device missing             → a restart can't help (USB not enumerated). Skip.
#   - a video frame flows         → stream healthy, reset failure counter, exit.
#   - no frame N times in a row (default 3, ~90s) → restart mediamtx.
#
# The health check decodes a real frame (not just stream metadata) so it also
# catches a stream that is published but FROZEN — the boot-time case where ffmpeg
# latched onto the not-yet-ready hardware encoder. See the probe below.
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

# Probe the live stream. We must verify that FRAMES ACTUALLY FLOW, not merely that
# the path advertises a codec.
#
# Why this matters on boot: ffmpeg can start before the Pi's hardware H.264 encoder
# (h264_v4l2m2m) is ready and latch onto a STALLED pipeline — it stays connected and
# "publishes" the fpv path, but no frames ever flow, and it never exits (so
# runOnInitRestart can't help either). The RTSP SDP still advertises the H264 codec,
# so a metadata-only check (`ffprobe -show_entries stream=codec_type`, which derives
# codec_type from the SDP without reading a single media packet) returns exit 0 and
# wrongly reports "healthy" — the frozen stream is then never auto-restarted, and only
# a manual `systemctl restart mediamtx` (e.g. saving stream settings) recovers it.
#
# Decoding one real video frame (capped by `timeout` so the check can never hang)
# succeeds on a healthy stream within a fraction of a second but fails on a
# frozen/empty stream, so the boot-time stall is finally detected and recovered.
if timeout 15 ffmpeg -nostdin -rtsp_transport tcp \
        -i "$STREAM" -frames:v 1 -f null - >/dev/null 2>&1; then
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
