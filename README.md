# Drone Streamer Portal FPV - Local Linux Test Setup

## 1. Prerequisites (Debian/Ubuntu/PiOS)

Before running the Vue frontend, your environment needs the "Drone Streamer Portal" engine components (MediaMTX and v4l-utils) to simulate or capture a camera feed and stream it via WebRTC.

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

Navigate to `http://localhost:5173`. Ensure your browser allows auto-play for the local IP. When you click "Launch Drone Streamer Portal VR", the web app will connect to MediaMTX on `:8889` and render the incoming WebRTC feed onto a dual canvas for VR viewing.

## 5. Backend API Development

For the new Stream Settings or Hardware monitoring features, you'll need the Python FastAPI backend running locally alongside the frontend.

1. Ensure Python 3 and pip are installed on your machine.
2. Initialize and activate a virtual environment in the `backend/` directory:

```bash
cd backend
python3 -m venv venv
source venv/bin/activate
```

3. Install the dependencies:

```bash
pip install -r requirements.txt
```

4. Start the backend DEV server on port 5002 using uvicorn:

```bash
uvicorn main:app --host 0.0.0.0 --port 5002 --reload
```

The FastAPI backend logic (like the websocket history streaming and `/api/stream-settings` endpoints) will now be available for the Vue frontend locally!

## 6. Dev mode on the Raspberry Pi

On the deployed Pi you can switch the whole portal between the production build and
a live dev environment (Vite HMR + backend auto-reload) with one script. Both modes
use port 80 and `:5002`, so they are mutually exclusive; the choice persists across
reboots.

```bash
# from the repo checkout on the Pi (run as your normal user, NOT root):
scripts/dev-mode.sh dev      # nginx proxies / → Vite dev server (HMR); backend = uvicorn --reload from ./backend
scripts/dev-mode.sh prod     # nginx serves the built dist/; backend = drone-stats
scripts/dev-mode.sh status   # show the current mode
```

In **dev** mode:
- The Vite dev server runs as the `drone-dev-web` systemd service; nginx
  (`nginx/dev-pi.conf`) reverse-proxies `/` to it, so HMR works over `http://<pi-ip>/`.
- The backend runs as `drone-dev-api` (`uvicorn --reload`) directly from
  `backend/main.py` in the repo, so backend edits hot-reload.
- The MediaMTX streaming routes (`/{stream}/whep`, `/hls/`, `/webrtc/`) are identical
  to prod, so the live stream keeps working.

`dev-mode.sh dev` detects the active Node (e.g. Zed's bundled Node) and bakes its path
into the `drone-dev-web` unit; after a Node version upgrade just run `dev-mode.sh dev`
again to refresh it.
