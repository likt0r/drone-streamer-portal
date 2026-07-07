"""Fan control + tachometer for a 3-pin Noctua NF-A4x10 5V on a Raspberry Pi 4.

A 3-pin fan has no PWM control wire, so stepless speed control is not possible.
Control is therefore a **thermostatic on/off switch**: a GPIO drives a BC547
low-side transistor (GPIO high -> base current -> fan on). The tachometer (green
wire, open-collector) is read on a second GPIO using the internal 3.3V pull-up;
RPM is derived from falling-edge counts over the sampling window (2 pulses/rev).

Wiring (BCM):
  GPIO17 (pin 11) --1k--> BC547 base      (fan switched via low-side transistor)
  GPIO16 (pin 36) <--1k-- fan green/tach  (internal pull-up to 3.3V)

On a non-Pi machine (no GPIO / gpiozero unavailable) everything degrades
gracefully: get_rpm() returns None and tick()/set_settings() become no-ops.
This mirrors the hardware-read fallbacks in main.py.
"""
from __future__ import annotations

import json
import os
import threading
import time

# --- Pin assignment (BCM numbering) ---
FAN_CONTROL_PIN = 17  # -> 1k -> BC547 base (physical pin 11)
FAN_TACH_PIN = 16     # <- 1k <- fan tach/green, internal pull-up (physical pin 36)

TACH_PULSES_PER_REV = 2  # standard for PC/Noctua fans

SETTINGS_FILE = "fan_settings.json"

DEFAULT_SETTINGS = {
    "mode": "auto",      # "auto" (temperature hysteresis) | "manual"
    "manual_on": False,  # used when mode == "manual"
    "temp_on": 60.0,     # auto: turn ON at/above this CPU temp (°C)
    "temp_off": 50.0,    # auto: turn OFF at/below this CPU temp (°C)
}

# --- Module state ---
_lock = threading.Lock()          # guards _settings / _fan_on / _control
_pulse_lock = threading.Lock()    # guards _pulse_count (tach ISR vs sampler)

_settings = dict(DEFAULT_SETTINGS)
_fan_on = False                   # current physical fan state
_available = False                # GPIO usable?

_control = None                   # gpiozero OutputDevice
_tach = None                      # gpiozero DigitalInputDevice

_pulse_count = 0
_last_rpm = 0.0
_last_sample_time = None          # time.monotonic() of last get_rpm()


def _load_settings() -> None:
    global _settings
    if os.path.exists(SETTINGS_FILE):
        try:
            with open(SETTINGS_FILE) as f:
                data = json.load(f)
            merged = dict(DEFAULT_SETTINGS)
            merged.update({k: data[k] for k in DEFAULT_SETTINGS if k in data})
            _settings = merged
        except Exception:
            _settings = dict(DEFAULT_SETTINGS)


def _save_settings() -> None:
    try:
        with open(SETTINGS_FILE, "w") as f:
            json.dump(_settings, f, indent=2)
    except Exception as e:
        print(f"[fan] could not save settings: {e}")


def _on_tach_edge() -> None:
    """Called by gpiozero on each falling tach edge (open-collector pulse)."""
    global _pulse_count
    with _pulse_lock:
        _pulse_count += 1


def init() -> None:
    """Set up GPIO. Safe to call once at startup; no-ops on non-Pi hardware."""
    global _control, _tach, _available, _last_sample_time
    _load_settings()
    try:
        from gpiozero import OutputDevice, DigitalInputDevice

        _control = OutputDevice(FAN_CONTROL_PIN, active_high=True, initial_value=False)
        # pull_up=True -> line idles high, tach pulses pull it low; "activated" =
        # active state = LOW, so when_activated fires on each falling edge.
        _tach = DigitalInputDevice(FAN_TACH_PIN, pull_up=True)
        _tach.when_activated = _on_tach_edge
        _available = True
        _last_sample_time = time.monotonic()
        print("[fan] GPIO initialised (control=GPIO%d, tach=GPIO%d)"
              % (FAN_CONTROL_PIN, FAN_TACH_PIN))
    except Exception as e:
        _available = False
        _control = None
        _tach = None
        print(f"[fan] GPIO unavailable, running in no-op mode: {e}")


def cleanup() -> None:
    """Release GPIO resources (turn the fan off first)."""
    global _control, _tach
    try:
        if _control is not None:
            _control.off()
            _control.close()
        if _tach is not None:
            _tach.close()
    except Exception:
        pass
    _control = None
    _tach = None


def _apply(desired: bool) -> None:
    """Drive the transistor to the desired state (caller holds _lock)."""
    global _fan_on
    if desired == _fan_on:
        return
    if _control is not None:
        _control.on() if desired else _control.off()
    _fan_on = desired


def tick(cpu_temp) -> None:
    """Evaluate the control policy once (call ~1 Hz). No-op without GPIO."""
    if not _available:
        return
    with _lock:
        if _settings["mode"] == "manual":
            desired = bool(_settings["manual_on"])
        else:  # auto: hysteresis on CPU temperature
            if cpu_temp is None:
                desired = _fan_on  # no reading -> hold current state
            elif cpu_temp >= _settings["temp_on"]:
                desired = True
            elif cpu_temp <= _settings["temp_off"]:
                desired = False
            else:
                desired = _fan_on  # inside the hysteresis band -> hold
        _apply(desired)


def get_rpm():
    """Return current fan RPM, or None on non-Pi hardware. Call ~1 Hz.

    Consumes the pulses counted since the previous call and scales by the actual
    elapsed time, so the value is correct even if the interval drifts from 1 s.
    """
    global _pulse_count, _last_sample_time, _last_rpm
    if not _available:
        return None
    now = time.monotonic()
    with _pulse_lock:
        pulses = _pulse_count
        _pulse_count = 0
    elapsed = now - (_last_sample_time or now)
    _last_sample_time = now
    # Tach is only meaningful while the fan is powered.
    if not _fan_on or elapsed <= 0:
        _last_rpm = 0.0
        return 0.0
    revs_per_sec = (pulses / TACH_PULSES_PER_REV) / elapsed
    _last_rpm = round(revs_per_sec * 60.0)
    return _last_rpm


def get_settings() -> dict:
    """Current settings plus live state, for GET /api/fan-settings."""
    with _lock:
        return {
            **_settings,
            "state": "on" if _fan_on else "off",
            "available": _available,
            "rpm": _last_rpm,
        }


def set_settings(new: dict) -> dict:
    """Update + persist settings; apply immediately in manual mode."""
    with _lock:
        for key in DEFAULT_SETTINGS:
            if key in new and new[key] is not None:
                _settings[key] = new[key]
        # Validate / normalise.
        if _settings["mode"] not in ("auto", "manual"):
            _settings["mode"] = "auto"
        _settings["manual_on"] = bool(_settings["manual_on"])
        try:
            _settings["temp_on"] = float(_settings["temp_on"])
            _settings["temp_off"] = float(_settings["temp_off"])
        except (TypeError, ValueError):
            _settings["temp_on"] = DEFAULT_SETTINGS["temp_on"]
            _settings["temp_off"] = DEFAULT_SETTINGS["temp_off"]
        # Keep a real hysteresis band (off threshold below on threshold).
        if _settings["temp_off"] >= _settings["temp_on"]:
            _settings["temp_off"] = _settings["temp_on"] - 1.0
        _save_settings()
        # Manual changes take effect at once; auto waits for the next tick().
        if _available and _settings["mode"] == "manual":
            _apply(bool(_settings["manual_on"]))
        return {
            **_settings,
            "state": "on" if _fan_on else "off",
            "available": _available,
            "rpm": _last_rpm,
        }
