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
