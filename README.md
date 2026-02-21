# Antigravity FPV - Local Linux Test Setup

## 1. Prerequisites (Debian/Ubuntu/PiOS)

Before running the Vue frontend, your environment needs the "Antigravity" engine components (MediaMTX and v4l-utils) to simulate or capture a camera feed and stream it via WebRTC.

```bash
# debian based
sudo apt update && sudo apt install -y v4l-utils ffmpeg

# fedora based
sudo dnf update && sudo dnf install -y v4l-utils ffmpeg
```

## 2. Locate Your Webcam

You don't need to simulate a framegrabber if you just want to use your laptop webcam. Most Linux laptops expose the webcam as `/dev/video0`. Wait to verify this by running:

```bash
v4l2-ctl --list-devices
```

Identify the `Integrated Camera` and note its path (typically `/dev/video0`).

## 3. Launch MediaMTX

Download MediaMTX from [GitHub](https://github.com/bluenviron/mediamtx/releases).

1. Extract the downloaded `mediamtx_linux_amd64.tar.gz`.
2. Configure `mediamtx.yml` with the following:

```yaml
paths:
  fpv:
    # Use your laptop's integrated webcam:
    source: v4l2
    v4l2Device: /dev/video0
    # Add width and height specific to your camera to avoid framerate drops, or leave commented
    # v4l2Width: 1280
    # v4l2Height: 720
webrtc: yes
webrtcAddress: :8889
webrtcICEUDP: yes
```

3. Run `./mediamtx`

## 4. Nuxt UI / Vue Development

Start the frontend portal to view the stream.

```bash
bun install
bun run dev
```

Navigate to `http://localhost:5173`. Ensure your browser allows auto-play for the local IP. When you click "Launch Antigravity VR", the web app will connect to MediaMTX on `:8889` and render the incoming WebRTC feed onto a dual canvas for VR viewing.
