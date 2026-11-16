import argparse
import colorsys
import itertools
import json
import os
import socket
import subprocess
import time
from collections import deque
import numpy as np

CONF_DIR = os.path.expanduser("~/.config/victus-sync")
CONFIG_PATH = f"{CONF_DIR}/config.json"
STATE_PATH = f"{CONF_DIR}/state.json"
DEFAULTS = {
    "bands": {"bass": [20, 150], "mid": [150, 2000], "treble": [2000, 12000]},
    "mode": "bands",             # music style: bands | pulse | rainbow
    "brightness": 200,
    "sensitivity": 1.7,
    "every": 2,
    "attack": 0.6,
    "decay": 0.12,
    "music": "auto",             # auto | on | off
    "base": "colour",            # colour | effect
    "colour": [255, 255, 255],
    "effect": {"colours": [[255, 0, 0], [0, 0, 255], [0, 255, 0]], "hold": 2.0, "fade": 3.0},
}

p = argparse.ArgumentParser()
p.add_argument("--seconds", type=int, default=0, help="0 = run until Ctrl+C")
args = p.parse_args()


def clamp(v, lo, hi):
    return min(max(v, lo), hi)


def load_json(path):
    try:
        with open(path) as f:
            d = json.load(f)
        return d if isinstance(d, dict) else None
    except (OSError, ValueError):
        return None


def load_config():
    """Validated config, or None if the file is unreadable (caller keeps the old one)."""
    raw = load_json(CONFIG_PATH)
    if raw is None:
        return None
    cfg = json.loads(json.dumps(DEFAULTS))
    try:
        if raw.get("mode") in ("bands", "pulse", "rainbow"):
            cfg["mode"] = raw["mode"]
        if raw.get("music") in ("auto", "on", "off"):
            cfg["music"] = raw["music"]
        if raw.get("base") in ("colour", "effect"):
            cfg["base"] = raw["base"]
        cfg["brightness"] = int(clamp(float(raw.get("brightness", 200)), 0, 255))
        cfg["every"] = int(clamp(float(raw.get("every", 2)), 1, 8))
        cfg["sensitivity"] = clamp(float(raw.get("sensitivity", 1.7)), 1.1, 4.0)
        cfg["attack"] = clamp(float(raw.get("attack", 0.6)), 0.05, 1.0)
        cfg["decay"] = clamp(float(raw.get("decay", 0.12)), 0.02, 1.0)

        for name in ("bass", "mid", "treble"):
            try:
                lo, hi = (float(x) for x in raw["bands"][name])
                if 20 <= lo < hi <= 20000:
                    cfg["bands"][name] = [lo, hi]
            except (KeyError, TypeError, ValueError):
                pass

        try:
            c = [int(clamp(float(x), 0, 255)) for x in raw["colour"]]
            if len(c) == 3:
                cfg["colour"] = c
        except (KeyError, TypeError, ValueError):
            pass

        try:
            e = raw["effect"]
            cols = [[int(clamp(float(x), 0, 255)) for x in c] for c in e["colours"]]
            cols = [c for c in cols if len(c) == 3]
            if len(cols) >= 2:
                cfg["effect"]["colours"] = cols
            cfg["effect"]["hold"] = clamp(float(e.get("hold", 2.0)), 0.0, 60.0)
            cfg["effect"]["fade"] = clamp(float(e.get("fade", 3.0)), 0.2, 60.0)
        except (KeyError, TypeError, ValueError):
            pass
    except (TypeError, ValueError):
        return None
    return cfg


def load_power():
    s = load_json(STATE_PATH)
    return None if s is None else bool(s.get("power", True))


def mtime(path):
    try:
        return os.stat(path).st_mtime
    except OSError:
        return 0.0


os.makedirs(CONF_DIR, exist_ok=True)
if not os.path.exists(CONFIG_PATH):
    with open(CONFIG_PATH, "w") as f:
        json.dump(DEFAULTS, f, indent=2)
if not os.path.exists(STATE_PATH):
    with open(STATE_PATH, "w") as f:
        json.dump({"power": True}, f)

cfg = load_config() or json.loads(json.dumps(DEFAULTS))
power = load_power()
power = True if power is None else power
cfg_mtime, state_mtime = mtime(CONFIG_PATH), mtime(STATE_PATH)

SOURCE = "combined_audio.monitor"
LED = "/sys/class/leds/hp::kbd_backlight"
RATE, HOP, WIN = 48000, 1024, 2048
FPS = RATE / HOP
MIN_GAP, FLOOR, FLASH_DECAY = 0.40, 1e-6, 0.85
MUSIC_START, MUSIC_STOP, STOP_AFTER = 0.010, 0.004, 3.0   # level thresholds; seconds of quiet
GUI_ADDR = ("127.0.0.1", 45454)

window = np.hanning(WIN)
freqs = np.fft.rfftfreq(WIN, 1 / RATE)


def make_masks(bands):
    return [(freqs >= bands[n][0]) & (freqs < bands[n][1]) for n in ("bass", "mid", "treble")]


masks = make_masks(cfg["bands"])
peaks = np.full(3, FLOOR)
smooth = np.zeros(3)
flash, hue = 0.0, 0.0
history = deque(maxlen=43)
last_beat = -1.0
last_sent, last_bri, last_source = None, None, None
level_ema, music_active, quiet_frames = 0.0, False, 0

udp = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)

proc = subprocess.Popen(
    ["parec", "-d", SOURCE, "--format=float32le",
     f"--rate={RATE}", "--channels=2", "--latency-msec=20"],
    stdout=subprocess.PIPE,
)

bri = open(f"{LED}/brightness", "w")
col = open(f"{LED}/multi_intensity", "w")


def put(f, text):
    f.write(text)
    f.flush()


def set_brightness(v):
    global last_bri
    if v != last_bri:
        put(bri, str(v))
        last_bri = v


def music_rgb(mode):
    global hue
    if mode == "bands":
        return smooth + (1 - smooth) * flash * 0.6
    if mode == "pulse":
        v = 0.25 + 0.75 * max(smooth[0], flash)
        return np.array(colorsys.hsv_to_rgb(hue, 1.0, min(v, 1.0)))
    hue = (hue + 0.002 + 0.01 * smooth.mean()) % 1.0
    v = 0.4 + 0.6 * min(smooth.mean() + flash * 0.3, 1.0)
    return np.array(colorsys.hsv_to_rgb(hue, 1.0, v))


def effect_rgb(now):
    cols, hold, fade = cfg["effect"]["colours"], cfg["effect"]["hold"], cfg["effect"]["fade"]
    seg = hold + fade
    pos = now % (seg * len(cols))
    i = int(pos // seg)
    phase = pos - i * seg
    a = np.array(cols[i], dtype=float)
    if phase < hold:
        return a / 255
    b = np.array(cols[(i + 1) % len(cols)], dtype=float)
    return (a + (b - a) * (phase - hold) / fade) / 255


buf = np.zeros(WIN, dtype=np.float32)
limit = f"{args.seconds} seconds" if args.seconds else "until Ctrl+C"
print(f"Running {limit}. Config: {CONFIG_PATH}")
try:
    for step in itertools.count():
        # --- live reload of config and power state (about 4 times per second) ---
        if step % 12 == 0:
            m = mtime(CONFIG_PATH)
            if m != cfg_mtime:
                cfg_mtime = m
                new = load_config()
                if new:
                    cfg, masks = new, make_masks(new["bands"])
                    print("Config reloaded.")
            m = mtime(STATE_PATH)
            if m != state_mtime:
                state_mtime = m
                new_power = load_power()
                if new_power is not None:
                    power = new_power
                    print(f"Power: {'on' if power else 'off'}")

        raw = proc.stdout.read(HOP * 2 * 4)
        mono = np.frombuffer(raw, dtype=np.float32).reshape(-1, 2).mean(axis=1)
        buf = np.concatenate([buf[len(mono):], mono])
        mag = np.abs(np.fft.rfft(buf * window)) / WIN
        t = step * HOP / RATE
        if args.seconds and t > args.seconds:
            break

        # --- is music playing? (level with a start threshold and a delayed stop) ---
        rms = float(np.sqrt(np.mean(mono ** 2)))
        level_ema += 0.04 * (rms - level_ema)
        if not music_active:
            if level_ema > MUSIC_START:
                music_active, quiet_frames = True, 0
        elif level_ema < MUSIC_STOP:
            quiet_frames += 1
            if quiet_frames > STOP_AFTER * FPS:
                music_active = False
        else:
            quiet_frames = 0

        # --- band levels, smoothing, beats ---
        e = np.array([np.sqrt(np.mean(mag[mk] ** 2)) if mk.any() else 0.0 for mk in masks])
        peaks = np.maximum(peaks * 0.995, e)
        levels = e / peaks
        rate = np.where(levels > smooth, cfg["attack"], cfg["decay"])
        smooth += rate * (levels - smooth)

        beat = False
        bass_e = float(np.mean(mag[masks[0]] ** 2)) if masks[0].any() else 0.0
        if len(history) >= 20 and bass_e > FLOOR:
            if bass_e > cfg["sensitivity"] * (sum(history) / len(history)) and t - last_beat >= MIN_GAP:
                last_beat, flash, beat = t, 1.0, True
                hue = (hue + 0.12) % 1.0
        history.append(bass_e)
        flash *= FLASH_DECAY

        # --- decision table: what should the keyboard show? ---
        lit = power and cfg["music"] != "off"
        if not lit:
            source = "dark"
        elif cfg["music"] == "auto" and music_active:
            source = "music"
        else:
            source = cfg["base"]
        if source != last_source:
            print(f"Source: {source}")
            last_source = source

        if step < 50:        # skip warm-up
            continue
        set_brightness(cfg["brightness"] if lit else 0)

        if step % cfg["every"] == 0:
            if lit:
                if source == "music":
                    rgb = music_rgb(cfg["mode"])
                elif source == "effect":
                    rgb = effect_rgb(time.monotonic())
                else:
                    rgb = np.array(cfg["colour"], dtype=float) / 255
                r, g, b = (int(c * 255) for c in rgb)
                value = f"{r} {g} {b}"
                if value != last_sent:
                    put(col, value)
                    last_sent = value
            try:   # live data for the GUI; ignored if nobody is listening
                udp.sendto(json.dumps({
                    "bass": round(float(smooth[0]), 3), "mid": round(float(smooth[1]), 3),
                    "treble": round(float(smooth[2]), 3), "beat": beat,
                    "source": source, "music_active": music_active, "power": power,
                }).encode(), GUI_ADDR)
            except OSError:
                pass
except KeyboardInterrupt:
    pass
finally:
    proc.terminate()
    try:
        put(col, "255 255 255")   # original colour
        put(bri, "0")             # original brightness (off)
    except OSError:
        pass
    print("Stopped. Keyboard restored.")
