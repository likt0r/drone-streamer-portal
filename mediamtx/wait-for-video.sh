#!/bin/sh
# wait-for-video.sh — wait for the USB capture device to be READY, then exec the
# given command.
#
# Called from mediamtx.yml `runOnInit`, e.g.:
#   runOnInit: sh /opt/mediamtx/wait-for-video.sh ffmpeg -f v4l2 ... -f rtsp rtsp://localhost:$RTSP_PORT/$RTSP_PATH
#
# Why: on boot the USB capture adapter (/dev/video0) is sometimes not enumerated
# yet when MediaMTX starts, so ffmpeg fails with "Cannot open video device".
# The node can also appear a few seconds BEFORE the UVC driver has finished
# registering the device — so we wait until the node exists AND it advertises a
# usable MJPEG capture format, not just until the node is present. This prevents
# ffmpeg from starting against a half-initialised device on slower boots.
# With `runOnInitRestart: yes`, MediaMTX re-runs this if the command exits, so it
# re-waits for the device automatically.
set -eu

DEV="${FPV_DEVICE:-/dev/video0}"
WAIT="${FPV_WAIT_SECS:-60}"

i=0
while ! { [ -e "$DEV" ] && v4l2-ctl -d "$DEV" --list-formats 2>/dev/null | grep -qiE 'mjpg|mjpeg'; }; do
    i=$((i + 1))
    if [ "$i" -ge "$WAIT" ]; then
        echo "wait-for-video: $DEV not ready (node + MJPEG format) after ${WAIT}s — giving up (will be retried)" >&2
        exit 1
    fi
    sleep 1
done

echo "wait-for-video: $DEV ready after ${i}s — starting capture" >&2
exec "$@"
