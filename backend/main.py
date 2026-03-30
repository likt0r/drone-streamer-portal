from fastapi import FastAPI, BackgroundTasks, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from collections import deque
import asyncio
import psutil
import subprocess
import time
from typing import List

app = FastAPI()

# Allow frontend to access REST endpoints if needed
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# 30 minutes = 1800 seconds (sampling every 1 second)
history = deque(maxlen=1800)

class ConnectionManager:
    def __init__(self):
        self.active_connections: List[WebSocket] = []

    async def connect(self, websocket: WebSocket):
        await websocket.accept()
        self.active_connections.append(websocket)

    def disconnect(self, websocket: WebSocket):
        self.active_connections.remove(websocket)

    async def broadcast(self, message: dict):
        for connection in self.active_connections:
            try:
                await connection.send_json(message)
            except WebSocketDisconnect:
                self.disconnect(connection)

manager = ConnectionManager()

def get_cpu_temp() -> float | None:
    try:
        with open("/sys/class/thermal/thermal_zone0/temp", "r") as f:
            temp = float(f.read()) / 1000.0
        return round(temp, 1)
    except Exception:
        # Fallback for local testing when not on a Raspberry pi
        return 45.0 + (psutil.cpu_percent() * 0.1)

def get_gpu_temp() -> float | None:
    try:
        res = subprocess.run(['vcgencmd', 'measure_temp'], capture_output=True, text=True)
        temp_str = res.stdout.replace("temp=", "").replace("'C", "").strip()
        return float(temp_str)
    except Exception:
        # Fallback for local testing
        return 50.0 + (psutil.cpu_percent() * 0.15)

def get_gpu_load() -> float:
    try:
        # Some Pi models/kernels expose it here:
        with open("/sys/devices/gpu.0/load", "r") as f:
            load = float(f.read().strip())
        return round(load, 1)
    except Exception:
        # Fallback simulated GPU load for local testing/missing permissions
        return min(100.0, max(0.0, psutil.cpu_percent() * 0.8 + 5.0))

def get_cpu_load() -> float:
    return psutil.cpu_percent()


async def collect_stats():
    """Background task to continuously collect hardware stats every 1 second"""
    while True:
        data = {
            "timestamp": int(time.time() * 1000), # JS expects ms
            "cpu_temp": get_cpu_temp(),
            "gpu_temp": get_gpu_temp(),
            "cpu_load": get_cpu_load(),
            "gpu_load": get_gpu_load(),
        }
        history.append(data)
        await manager.broadcast(data)
        await asyncio.sleep(1)


@app.on_event("startup")
async def startup_event():
    # Pre-fill history with 1800 seconds (30 mins) of 0-values so the 
    # frontend chart always shows a full 30-minute x-axis scale on boot.
    now_ms = int(time.time() * 1000)
    for i in range(1800, 0, -1):
        history.append({
            "timestamp": now_ms - (i * 1000),
            "cpu_temp": 0,
            "gpu_temp": 0,
            "cpu_load": 0,
            "gpu_load": 0,
        })
    
    # Warmup psutil logic (first call returns 0.0)
    psutil.cpu_percent()
    asyncio.create_task(collect_stats())

@app.get("/api/stats/history")
async def get_history():
    """Returns the up to 30 mins rolling history"""
    return list(history)

@app.websocket("/ws/stats")
async def websocket_endpoint(websocket: WebSocket):
    await manager.connect(websocket)
    try:
        while True:
            # Keep connection open, backend pushes data via the collect_stats broadcast
            await websocket.receive_text()
    except WebSocketDisconnect:
        manager.disconnect(websocket)

from pydantic import BaseModel
import json
import os
import re

SETTINGS_FILE = "stream_settings.json"

class StreamSettings(BaseModel):
    device: str
    width: int
    height: int
    fps: int
    bitrate: str
    maxrate: str
    bufsize: str
    g: str
    tune: str
    bf: str
    pix_fmt: str
    f: str

def get_default_settings() -> StreamSettings:
    return StreamSettings(
        device="/dev/video0",
        width=1280,
        height=720,
        fps=30,
        bitrate="8000k",
        maxrate="10000k",
        bufsize="8000k",
        g="15",
        tune="zerolatency",
        bf="0",
        pix_fmt="yuv420p",
        f="rtsp"
    )

@app.get("/api/stream-settings", response_model=StreamSettings)
async def get_stream_settings():
    if not os.path.exists(SETTINGS_FILE):
        return get_default_settings()
    try:
        with open(SETTINGS_FILE, "r") as f:
            data = json.load(f)
            return StreamSettings(**data)
    except Exception:
        return get_default_settings()

@app.post("/api/stream-settings")
async def save_stream_settings(settings: StreamSettings):
    # Save to JSON
    with open(SETTINGS_FILE, "w") as f:
        json.dump(settings.model_dump(), f, indent=2)
    
    # Rebuild mediamtx.yml
    # Typically production uses /opt/mediamtx/mediamtx.yml
    # Dev uses ../mediamtx/mediamtx.yml
    yaml_paths = [
        "/opt/mediamtx/mediamtx.yml",
        "../mediamtx/mediamtx.yml"
    ]
    
    target_yaml = None
    for path in yaml_paths:
        if os.path.exists(path):
            target_yaml = path
            break
            
    if target_yaml:
        try:
            with open(target_yaml, "r") as f:
                content = f.read()
                
            # ffmpeg command template
            new_cmd = (
                f"ffmpeg -f v4l2 -input_format mjpeg -framerate {settings.fps} "
                f"-video_size {settings.width}x{settings.height} -i {settings.device} "
                f"-c:v h264_v4l2m2m -b:v {settings.bitrate} -maxrate {settings.maxrate} -bufsize {settings.bufsize} "
                f"-g {settings.g} -tune {settings.tune} -bf {settings.bf} -pix_fmt {settings.pix_fmt} -f {settings.f} rtsp://localhost:$RTSP_PORT/$RTSP_PATH"
            )
            
            # Use regex to find and replace the runOnInit line under fpv:
            # We look for something like:
            # fpv:
            #   source: publisher
            #   runOnInit: ffmpeg ...
            pattern = r"(fpv:\s+source:\s+publisher\s+runOnInit:\s+).*?(?=\n\s*runOnInitRestart:)"
            replacement = r"\g<1>" + new_cmd
            
            updated_content = re.sub(pattern, replacement, content, flags=re.DOTALL)
            
            # If the regex didn't match (maybe formatting is different), let's try a simpler line replacement
            if updated_content == content:
                # Just replace the runOnInit line starting with ffmpeg
                line_pattern = r"(runOnInit:\s+ffmpeg\s+).*?(?=\n)"
                line_replacement = r"runOnInit: " + new_cmd
                updated_content = re.sub(line_pattern, line_replacement, content)
                
            with open(target_yaml, "w") as f:
                f.write(updated_content)
                
            # Restart mediamtx
            try:
                subprocess.run(["sudo", "systemctl", "restart", "mediamtx"], check=True)
            except Exception as e:
                # Might fail in dev without sudo
                print(f"Failed to restart mediamtx (expected in dev): {e}")
                
        except Exception as e:
            print(f"Error updating config: {e}")
            return {"status": "error", "message": str(e)}

    return {"status": "success"}
