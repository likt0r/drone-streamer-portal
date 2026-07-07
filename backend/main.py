from fastapi import FastAPI, BackgroundTasks, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from collections import deque
import asyncio
import psutil
import subprocess
import time
import socket
import ipaddress
from typing import List

import fan

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
        cpu_temp = get_cpu_temp()
        # Run the fan control policy (thermostatic on/off) before sampling RPM.
        fan.tick(cpu_temp)
        data = {
            "timestamp": int(time.time() * 1000), # JS expects ms
            "cpu_temp": cpu_temp,
            "gpu_temp": get_gpu_temp(),
            "cpu_load": get_cpu_load(),
            "gpu_load": get_gpu_load(),
            "fan_rpm": fan.get_rpm(),
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
            "fan_rpm": 0,
        })

    # Warmup psutil logic (first call returns 0.0)
    psutil.cpu_percent()
    # Set up the fan GPIO (no-op / graceful fallback off a Raspberry Pi).
    fan.init()
    asyncio.create_task(collect_stats())


@app.on_event("shutdown")
async def shutdown_event():
    fan.cleanup()

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
from typing import Optional
import json
import os
import re


class FanSettings(BaseModel):
    mode: Optional[str] = None          # "auto" | "manual"
    manual_on: Optional[bool] = None    # used when mode == "manual"
    temp_on: Optional[float] = None     # auto: turn ON at/above this CPU temp (°C)
    temp_off: Optional[float] = None    # auto: turn OFF at/below this CPU temp (°C)


@app.get("/api/fan-settings")
async def get_fan_settings():
    """Current fan mode/thresholds plus live state (on/off, rpm, gpio available)."""
    return fan.get_settings()


@app.post("/api/fan-settings")
async def save_fan_settings(settings: FanSettings):
    """Update fan mode / manual state / hysteresis thresholds."""
    return fan.set_settings(settings.model_dump(exclude_none=True))


SETTINGS_FILE = "stream_settings.json"

# The fpv path's runOnInit is wrapped by this guard so ffmpeg waits for the USB
# capture device to be ready on boot. It MUST be preserved when we rewrite the
# command, otherwise saving stream settings would re-introduce the boot-race.
WAIT_FOR_VIDEO_WRAPPER = "sh /opt/mediamtx/wait-for-video.sh "

# mediamtx.yml is the single source of truth. Production uses /opt, a dev
# checkout uses the repo copy.
MEDIAMTX_YAML_PATHS = [
    "/opt/mediamtx/mediamtx.yml",
    "../mediamtx/mediamtx.yml",
]

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
    rtsp_transport: str = "tcp"

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
        tune="",
        bf="0",
        pix_fmt="yuv420p",
        f="rtsp",
        rtsp_transport="tcp",
    )

def _target_yaml() -> str | None:
    for path in MEDIAMTX_YAML_PATHS:
        if os.path.exists(path):
            return path
    return None

# Matches the fpv path's runOnInit and captures (1) everything up to and
# including "runOnInit: " and (2) the command value (rest of the line).
_FPV_RUNONINIT_RE = r"(fpv:\s+source:\s*publisher\s+runOnInit:\s*)(.+)"

def parse_settings_from_yaml() -> StreamSettings | None:
    """Read the current stream settings from the live mediamtx.yml runOnInit."""
    path = _target_yaml()
    if not path:
        return None
    try:
        with open(path, "r") as f:
            content = f.read()
    except Exception:
        return None

    m = re.search(_FPV_RUNONINIT_RE, content)
    if not m:
        return None
    cmd = m.group(2).strip()

    def first(flag: str, default: str) -> str:
        mm = re.search(rf"{re.escape(flag)}\s+(\S+)", cmd)
        return mm.group(1) if mm else default

    size = re.search(r"-video_size\s+(\d+)x(\d+)", cmd)
    width = int(size.group(1)) if size else 1280
    height = int(size.group(2)) if size else 720

    # -f appears twice: input "-f v4l2" and the output format at the end.
    out_formats = re.findall(r"-f\s+(\S+)", cmd)
    out_f = out_formats[-1] if out_formats else "rtsp"

    tune_m = re.search(r"-tune\s+(\S+)", cmd)

    try:
        return StreamSettings(
            device=first("-i", "/dev/video0"),
            width=width,
            height=height,
            fps=int(first("-framerate", "30")),
            bitrate=first("-b:v", "8000k"),
            maxrate=first("-maxrate", "10000k"),
            bufsize=first("-bufsize", "8000k"),
            g=first("-g", "15"),
            tune=tune_m.group(1) if tune_m else "",
            bf=first("-bf", "0"),
            pix_fmt=first("-pix_fmt", "yuv420p"),
            f=out_f,
            rtsp_transport=first("-rtsp_transport", "tcp"),
        )
    except Exception:
        return None

def build_runoninit(settings: StreamSettings) -> str:
    """Build the runOnInit command: wait-for-video wrapper + ffmpeg.

    Always keeps the boot guard wrapper and -rtsp_transport tcp; -tune is only
    emitted when set (h264_v4l2m2m ignores it, but we honour an explicit value).
    """
    tune_part = f"-tune {settings.tune} " if settings.tune else ""
    transport = settings.rtsp_transport if settings.rtsp_transport in ("tcp", "udp") else "tcp"
    ffmpeg_cmd = (
        f"ffmpeg -f v4l2 -input_format mjpeg -framerate {settings.fps} "
        f"-video_size {settings.width}x{settings.height} -i {settings.device} "
        f"-c:v h264_v4l2m2m -b:v {settings.bitrate} -maxrate {settings.maxrate} -bufsize {settings.bufsize} "
        f"-g {settings.g} {tune_part}-bf {settings.bf} -pix_fmt {settings.pix_fmt} "
        f"-rtsp_transport {transport} -f {settings.f} rtsp://localhost:$RTSP_PORT/$RTSP_PATH"
    )
    return WAIT_FOR_VIDEO_WRAPPER + ffmpeg_cmd


def _v4l2_ctl_bin() -> str:
    # The systemd unit runs us with PATH=venv/bin only, so resolve the absolute
    # path to v4l2-ctl ourselves.
    for p in ("/usr/bin/v4l2-ctl", "/usr/local/bin/v4l2-ctl", "/bin/v4l2-ctl"):
        if os.path.exists(p):
            return p
    return "v4l2-ctl"


def _parse_v4l2_formats(device: str):
    """Parse `v4l2-ctl --list-formats-ext` for one device into
    [{pixelformat, resolutions:[{width,height,framerates:[..]}]}]. Returns
    (formats, error)."""
    try:
        res = subprocess.run(
            [_v4l2_ctl_bin(), "-d", device, "--list-formats-ext"],
            capture_output=True, text=True, timeout=10,
        )
    except Exception as e:
        return [], str(e)
    if res.returncode != 0:
        return [], (res.stderr.strip() or "v4l2-ctl failed")

    formats: list = []
    cur_fmt = None
    cur_res = None
    for line in res.stdout.splitlines():
        s = line.strip()
        m = re.match(r"\[\d+\]:\s*'(\w+)'", s)
        if m:
            cur_fmt = {"pixelformat": m.group(1), "resolutions": []}
            formats.append(cur_fmt)
            cur_res = None
            continue
        m = re.match(r"Size:\s*Discrete\s+(\d+)x(\d+)", s)
        if m and cur_fmt is not None:
            cur_res = {"width": int(m.group(1)), "height": int(m.group(2)), "framerates": []}
            cur_fmt["resolutions"].append(cur_res)
            continue
        m = re.search(r"\(([\d.]+)\s*fps\)", s)
        if m and cur_res is not None:
            fps = round(float(m.group(1)))
            if fps not in cur_res["framerates"]:
                cur_res["framerates"].append(fps)
    return formats, None


def _list_video_nodes() -> list:
    try:
        nodes = [f"/dev/{n}" for n in os.listdir("/dev") if re.fullmatch(r"video\d+", n)]
    except Exception:
        return []
    return sorted(nodes, key=lambda p: int(re.sub(r"\D", "", p) or 0))


def _device_card_name(device: str) -> str:
    try:
        res = subprocess.run(
            [_v4l2_ctl_bin(), "-d", device, "--info"],
            capture_output=True, text=True, timeout=5,
        )
    except Exception:
        return ""
    m = re.search(r"Card type\s*:\s*(.+)", res.stdout)
    return m.group(1).strip() if m else ""


@app.get("/api/video-devices")
async def get_video_devices(device: str = "/dev/video0"):
    """Return the capture formats / resolutions / framerates a V4L2 device offers.

    The frontend uses this so resolution & fps can only be set to values the
    device actually supports.
    """
    formats, error = _parse_v4l2_formats(device)
    if error:
        return {"device": device, "formats": [], "error": error}
    return {"device": device, "formats": formats}


@app.get("/api/capture-devices")
async def get_capture_devices():
    """List attached V4L2 *capture* devices (cameras / USB capture sticks),
    filtering out the Pi's internal codec/ISP m2m nodes. A node qualifies if it
    advertises at least one discrete capture resolution with framerates."""
    devices = []
    for node in _list_video_nodes():
        formats, error = _parse_v4l2_formats(node)
        if error:
            continue
        has_capture = any(r["framerates"] for f in formats for r in f["resolutions"])
        if has_capture:
            devices.append({"path": node, "name": _device_card_name(node) or node})
    return {"devices": devices}


@app.get("/api/stream-settings", response_model=StreamSettings)
async def get_stream_settings():
    # Source of truth is the live mediamtx.yml; fall back to cached JSON, then defaults.
    parsed = parse_settings_from_yaml()
    if parsed:
        return parsed
    if os.path.exists(SETTINGS_FILE):
        try:
            with open(SETTINGS_FILE, "r") as f:
                return StreamSettings(**json.load(f))
        except Exception:
            pass
    return get_default_settings()

@app.post("/api/stream-settings")
async def save_stream_settings(settings: StreamSettings):
    # Cache to JSON (audit / fallback)
    with open(SETTINGS_FILE, "w") as f:
        json.dump(settings.model_dump(), f, indent=2)

    target_yaml = _target_yaml()
    if not target_yaml:
        return {"status": "error", "message": "mediamtx.yml not found"}

    try:
        with open(target_yaml, "r") as f:
            content = f.read()

        new_cmd = build_runoninit(settings)
        # Replace ONLY the runOnInit value of the fpv block; keep everything else
        # (indentation, comments, the whole rest of the config) untouched.
        updated_content, n = re.subn(
            _FPV_RUNONINIT_RE,
            lambda m: m.group(1) + new_cmd,
            content,
            count=1,
        )
        if n == 0:
            return {"status": "error", "message": "Could not locate fpv runOnInit in mediamtx.yml"}

        with open(target_yaml, "w") as f:
            f.write(updated_content)

        # Backend runs as root -> no sudo needed. New ffmpeg params take effect on restart.
        # systemctl is resolved by absolute path because the unit's PATH is venv-only.
        systemctl = next(
            (p for p in ("/usr/bin/systemctl", "/bin/systemctl") if os.path.exists(p)),
            "systemctl",
        )
        try:
            subprocess.run([systemctl, "restart", "mediamtx"], check=True)
        except Exception as e:
            print(f"Failed to restart mediamtx: {e}")
            return {"status": "error", "message": f"Settings saved but mediamtx restart failed: {e}"}

    except Exception as e:
        print(f"Error updating config: {e}")
        return {"status": "error", "message": str(e)}

    return {"status": "success"}


# ─────────────────────────────────────────────────────────────────────────────
# Network settings: hostname + WiFi hotspot (the "AccessPopup" NM connection).
# The service runs as root, so nmcli/hostnamectl and config writes work directly.
# ─────────────────────────────────────────────────────────────────────────────
AP_PROFILE = "AccessPopup"
ACCESSPOPUP_SCRIPT = "/usr/bin/accesspopup"
DNSMASQ_DIR = "/etc/NetworkManager/dnsmasq-shared.d"
DNSMASQ_HOSTNAME_CONF = f"{DNSMASQ_DIR}/hostname.conf"
HOSTNAME_RE = re.compile(r"^[a-z0-9][a-z0-9-]{0,62}$")


def _bin(name: str) -> str:
    for d in ("/usr/bin", "/bin", "/usr/sbin", "/sbin", "/usr/local/bin"):
        p = f"{d}/{name}"
        if os.path.exists(p):
            return p
    return name


def _nmcli_get(field: str) -> str:
    try:
        res = subprocess.run(
            [_bin("nmcli"), "-s", "-t", "-f", field, "connection", "show", AP_PROFILE],
            capture_output=True, text=True, timeout=10,
        )
    except Exception:
        return ""
    if res.returncode != 0 or not res.stdout.strip():
        return ""
    line = res.stdout.strip().splitlines()[0]
    return line.split(":", 1)[1] if ":" in line else ""


class NetworkSettings(BaseModel):
    hostname: str
    ap_ssid: str
    ap_psk: str
    ap_ip: str
    ap_open: bool = False


@app.get("/api/network-settings")
async def get_network_settings():
    addr = _nmcli_get("ipv4.addresses")  # e.g. "192.168.50.5/24"
    ip, _, prefix = addr.partition("/")
    key_mgmt = _nmcli_get("802-11-wireless-security.key-mgmt")
    is_open = key_mgmt in ("", "none")
    return {
        "hostname": socket.gethostname(),
        "ap_ssid": _nmcli_get("802-11-wireless.ssid"),
        "ap_psk": "" if is_open else _nmcli_get("802-11-wireless-security.psk"),
        "ap_open": is_open,
        "ap_ip": ip or "192.168.50.5",
        "ap_prefix": prefix or "24",
        "band": _nmcli_get("802-11-wireless.band"),
        "channel": _nmcli_get("802-11-wireless.channel"),
    }


def _update_etc_hosts(hostname: str) -> None:
    try:
        with open("/etc/hosts") as f:
            lines = f.readlines()
        out, replaced = [], False
        for ln in lines:
            if re.match(r"^127\.0\.1\.1\s", ln):
                out.append(f"127.0.1.1\t{hostname}\n")
                replaced = True
            else:
                out.append(ln)
        if not replaced:
            out.append(f"127.0.1.1\t{hostname}\n")
        with open("/etc/hosts", "w") as f:
            f.writelines(out)
    except Exception as e:
        print(f"/etc/hosts update failed: {e}")


def _sync_accesspopup_script(ssid: str, psk, ip: str, gateway: str) -> None:
    """Keep the AccessPopup tool's hardcoded vars in sync, so a profile re-create
    doesn't revert our changes. psk=None leaves the stored password untouched
    (open mode: AccessPopup's create path needs a password, so we keep the last
    one as a fallback)."""
    try:
        with open(ACCESSPOPUP_SCRIPT) as f:
            c = f.read()
        c = re.sub(r"^ap_ssid=.*$", f"ap_ssid='{ssid}'", c, flags=re.M)
        if psk is not None:
            c = re.sub(r"^ap_pw=.*$", f"ap_pw='{psk}'", c, flags=re.M)
        c = re.sub(r"^ap_ip=.*$", f"ap_ip='{ip}/24'", c, flags=re.M)
        c = re.sub(r"^ap_gate=.*$", f"ap_gate='{gateway}'", c, flags=re.M)
        with open(ACCESSPOPUP_SCRIPT, "w") as f:
            f.write(c)
    except Exception as e:
        print(f"accesspopup sync failed: {e}")


def _write_dnsmasq_hostname_conf(hostname: str, ip: str) -> None:
    content = (
        "# Auto-generated by the portal Network settings.\n"
        "# Resolve the hostname to the AP address for any client using the AP's DNS\n"
        "# (works on iOS and Android, unlike mDNS/.local).\n"
        f"address=/{hostname}.local/{ip}\n"
        f"address=/{hostname}.box/{ip}\n"
        f"address=/{hostname}/{ip}\n"
    )
    try:
        os.makedirs(DNSMASQ_DIR, exist_ok=True)
        with open(DNSMASQ_HOSTNAME_CONF, "w") as f:
            f.write(content)
        legacy = f"{DNSMASQ_DIR}/pi-caster.conf"
        if os.path.exists(legacy):
            os.remove(legacy)
    except Exception as e:
        print(f"dnsmasq hostname conf write failed: {e}")


def _restart_ap_delayed() -> None:
    # Give the HTTP response time to reach the client before the AP drops, then
    # reactivate the connection (this also respawns the AP dnsmasq with the new
    # hostname records).
    time.sleep(2)
    try:
        subprocess.run([_bin("nmcli"), "connection", "up", AP_PROFILE],
                       capture_output=True, text=True, timeout=40)
    except Exception as e:
        print(f"AP reactivation failed: {e}")


@app.post("/api/network-settings")
async def save_network_settings(settings: NetworkSettings, background: BackgroundTasks):
    hn = settings.hostname.strip().lower()
    if not HOSTNAME_RE.match(hn):
        return {"status": "error", "message": "Invalid hostname (a–z, 0–9, '-', max 63 chars)."}
    ssid = settings.ap_ssid
    if not (1 <= len(ssid) <= 32):
        return {"status": "error", "message": "Hotspot name (SSID) must be 1–32 characters."}
    open_ = bool(settings.ap_open)
    psk = settings.ap_psk
    if not open_ and not (8 <= len(psk) <= 63):
        return {"status": "error", "message": "Wi-Fi password must be 8–63 characters (or enable the open network option)."}
    try:
        ip = str(ipaddress.IPv4Address(settings.ap_ip))
    except Exception:
        return {"status": "error", "message": "Invalid hotspot IP address."}
    gateway = re.sub(r"\.\d+$", ".254", ip)

    cur = await get_network_settings()
    changed_host = hn != cur["hostname"]
    changed_ap = (
        ssid != cur["ap_ssid"]
        or ip != cur["ap_ip"]
        or open_ != cur["ap_open"]
        or (not open_ and psk != cur["ap_psk"])
    )

    errors = []
    if changed_host:
        r = subprocess.run([_bin("hostnamectl"), "set-hostname", hn],
                           capture_output=True, text=True, timeout=10)
        if r.returncode != 0:
            errors.append(f"hostname: {r.stderr.strip()}")
        else:
            _update_etc_hosts(hn)

    if changed_ap:
        # 1) SSID + IPv4 (always)
        r = subprocess.run(
            [_bin("nmcli"), "connection", "modify", AP_PROFILE,
             "802-11-wireless.ssid", ssid,
             "ipv4.addresses", f"{ip}/24",
             "ipv4.gateway", gateway],
            capture_output=True, text=True, timeout=15,
        )
        if r.returncode != 0:
            errors.append(f"nmcli: {r.stderr.strip()}")
        # 2) Security: open => drop the whole security setting; else set wpa-psk + psk
        if not errors:
            if open_:
                if not cur["ap_open"]:
                    r2 = subprocess.run(
                        [_bin("nmcli"), "connection", "modify", AP_PROFILE,
                         "remove", "802-11-wireless-security"],
                        capture_output=True, text=True, timeout=15,
                    )
                    if r2.returncode != 0:
                        errors.append(f"nmcli(open): {r2.stderr.strip()}")
            else:
                r2 = subprocess.run(
                    [_bin("nmcli"), "connection", "modify", AP_PROFILE,
                     "802-11-wireless-security.key-mgmt", "wpa-psk",
                     "802-11-wireless-security.psk", psk],
                    capture_output=True, text=True, timeout=15,
                )
                if r2.returncode != 0:
                    errors.append(f"nmcli(psk): {r2.stderr.strip()}")
        if not errors:
            _sync_accesspopup_script(ssid, None if open_ else psk, ip, gateway)

    if changed_host or changed_ap:
        _write_dnsmasq_hostname_conf(hn, ip)

    if errors:
        return {"status": "error", "message": "; ".join(errors)}

    if changed_host or changed_ap:
        # Reactivate the AP so nmcli/ipv4 changes + the new dnsmasq records take effect.
        background.add_task(_restart_ap_delayed)

    if changed_ap:
        msg = (f"Saved. The hotspot is restarting — reconnect to '{ssid}', then open "
               f"http://{hn}.local/ or http://{ip}/.")
    elif changed_host:
        msg = (f"Saved. Hostname is now '{hn}' — reachable at http://{hn}.local/. "
               f"The hotspot briefly reloads its DNS.")
    else:
        msg = "No changes."
    return {"status": "success", "message": msg, "requiresReconnect": changed_ap}
