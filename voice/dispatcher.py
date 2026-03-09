#!/usr/bin/env python3
# ═══════════════════════════════════════════════════════════════════════
#  TOPU OS — Voice Engine Dispatcher
#  Daemon that handles: wake word → STT → NLU → action → TTS
#  Location: /usr/local/bin/topu-voice
# ═══════════════════════════════════════════════════════════════════════

import subprocess
import signal
import sys
import os
import json
import time
import struct
import threading
from pathlib import Path

# ── Config ────────────────────────────────────────────────────────────
WHISPER_BIN    = "/usr/local/bin/whisper-cli"
WHISPER_MODEL  = "/usr/share/topu/voice/whisper-small.en.bin"
PIPER_BIN      = "/usr/local/bin/piper"
PIPER_MODEL    = "/usr/share/topu/voice/en_US-ryan-medium.onnx"
INTENTS_FILE   = Path.home() / ".config/topu/voice/intents.json"
LOG_FILE       = "/var/log/topu-voice.log"
WAKE_WORD      = "hey topu"

# ── Logging ───────────────────────────────────────────────────────────
import logging
logging.basicConfig(
    level=logging.INFO,
    format='[%(asctime)s] %(levelname)s %(message)s',
    handlers=[
        logging.FileHandler(LOG_FILE),
        logging.StreamHandler(sys.stdout),
    ]
)
log = logging.getLogger("topu-voice")

# ── Intent definitions ────────────────────────────────────────────────
INTENTS = {
    # App launch
    "open terminal":    lambda: launch("foot"),
    "open browser":     lambda: launch("firefox"),
    "open steam":       lambda: launch("steam"),
    "open settings":    lambda: launch("topu-settings"),
    "open files":       lambda: launch("foot", ["yazi"]),
    "open discord":     lambda: flatpak("com.discordapp.Discord"),
    "open spotify":     lambda: flatpak("com.spotify.Client"),
    "open obs":         lambda: flatpak("com.obsproject.Studio"),

    # Gaming
    "enable game mode": lambda: run_cmd(["gamemoded", "-r"]),
    "disable game mode":lambda: run_cmd(["pkill", "gamemoded"]),
    "show fps":         lambda: run_cmd(["mangohud", "--toggle"]),
    "take screenshot":  lambda: screenshot(),
    "start recording":  lambda: run_cmd(["wf-recorder", "-f",
                         f"/home/{os.getenv('USER')}/Videos/recording_{int(time.time())}.mp4"]),
    "stop recording":   lambda: run_cmd(["pkill", "wf-recorder"]),

    # System
    "lock screen":      lambda: run_cmd(["swaylock", "-f"]),
    "shutdown":         lambda: run_cmd(["systemctl", "poweroff"]),
    "restart":          lambda: run_cmd(["systemctl", "reboot"]),
    "close everything": lambda: hyprctl("dispatch killactive"),
    "volume up":        lambda: run_cmd(["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", "10%+"]),
    "volume down":      lambda: run_cmd(["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", "10%-"]),
    "mute":             lambda: run_cmd(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"]),
    "hide dock":        lambda: run_cmd(["pkill", "waybar"]),
    "show dock":        lambda: subprocess.Popen(["waybar"]),
    "update system":    lambda: update_system(),
}

# ── Action helpers ────────────────────────────────────────────────────
def launch(app, args=None):
    """Launch an app as a Wayland window in Hyprland."""
    cmd = [app] + (args or [])
    log.info(f"Launching: {' '.join(cmd)}")
    subprocess.Popen(cmd, env={**os.environ, "WAYLAND_DISPLAY": "wayland-1"})

def flatpak(app_id):
    """Launch a Flatpak app."""
    log.info(f"Flatpak launch: {app_id}")
    subprocess.Popen(["flatpak", "run", app_id])

def run_cmd(cmd):
    log.info(f"Running: {' '.join(cmd)}")
    subprocess.run(cmd, check=False)

def hyprctl(command):
    run_cmd(["hyprctl", command])

def screenshot():
    path = f"/home/{os.getenv('USER')}/Pictures/Screenshots/{int(time.time())}.png"
    os.makedirs(os.path.dirname(path), exist_ok=True)
    run_cmd(["grim", path])
    speak(f"Screenshot saved")

def update_system():
    speak("Updating system, please wait")
    subprocess.run(["apt-get", "update", "-q"], check=False)
    subprocess.run(["apt-get", "upgrade", "-y", "-q"], check=False)
    subprocess.run(["flatpak", "update", "-y"], check=False)
    speak("System updated")

# ── TTS ───────────────────────────────────────────────────────────────
def speak(text: str):
    """Speak text using Piper TTS → aplay."""
    log.info(f"TTS: {text}")
    try:
        piper = subprocess.Popen(
            [PIPER_BIN, "--model", PIPER_MODEL, "--output-raw"],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
        )
        aplay = subprocess.Popen(
            ["aplay", "-r", "22050", "-f", "S16_LE", "-t", "raw", "-"],
            stdin=piper.stdout,
        )
        piper.stdin.write(text.encode())
        piper.stdin.close()
        aplay.wait()
    except Exception as e:
        log.error(f"TTS error: {e}")

# ── STT ───────────────────────────────────────────────────────────────
def transcribe(audio_file: str) -> str:
    """Run Whisper STT on an audio file, return text."""
    try:
        result = subprocess.run(
            [WHISPER_BIN, "-m", WHISPER_MODEL, "-f", audio_file, "--no-timestamps", "-otxt"],
            capture_output=True, text=True, timeout=15
        )
        return result.stdout.strip().lower()
    except Exception as e:
        log.error(f"STT error: {e}")
        return ""

# ── Intent Dispatch ───────────────────────────────────────────────────
def dispatch(text: str):
    """Match text to an intent and execute it."""
    text = text.strip().lower()
    log.info(f"Dispatching: '{text}'")

    # Exact match
    if text in INTENTS:
        speak("OK")
        INTENTS[text]()
        return

    # Fuzzy match — find best intent key that is contained in utterance
    for key, action in INTENTS.items():
        if key in text:
            speak("OK")
            action()
            return

    # Volume set: "set volume to 60"
    import re
    m = re.search(r'(?:set volume|volume)\s+(?:to\s+)?(\d+)', text)
    if m:
        vol = m.group(1)
        run_cmd(["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", f"{vol}%"])
        speak(f"Volume set to {vol} percent")
        return

    speak(f"Sorry, I didn't understand: {text}")
    log.warning(f"No intent matched for: '{text}'")

# ── Wake Word + Pipeline ──────────────────────────────────────────────
def run_pipeline():
    """Main voice pipeline using pvporcupine for wake word detection."""
    try:
        import pvporcupine
        import pvrecorder

        api_key = os.getenv("PICOVOICE_API_KEY", "")
        if not api_key:
            log.warning("PICOVOICE_API_KEY not set — wake word disabled, using dev mode")
            dev_mode()
            return

        porcupine = pvporcupine.create(
            access_key=api_key,
            keywords=["hey google"],  # placeholder — replace with custom "Hey TOPU" model
        )
        recorder = pvrecorder.PvRecorder(device_index=-1, frame_length=porcupine.frame_length)
        recorder.start()
        log.info("TOPU Voice: listening for 'Hey TOPU'...")

        while True:
            pcm = recorder.read()
            result = porcupine.process(pcm)
            if result >= 0:
                log.info("Wake word detected!")
                speak("Yes?")
                # Record utterance (2.5 seconds)
                audio_file = "/tmp/topu_utterance.wav"
                record_utterance(audio_file, recorder, porcupine.sample_rate, duration=2.5)
                text = transcribe(audio_file)
                if text:
                    dispatch(text)

    except ImportError:
        log.error("pvporcupine/pvrecorder not installed. Run: pip install pvporcupine pvrecorder")
        dev_mode()
    except Exception as e:
        log.error(f"Voice pipeline error: {e}")

def record_utterance(path: str, recorder, sample_rate: int, duration: float):
    """Record audio for a fixed duration and save to WAV."""
    import wave
    frames = []
    n_frames = int(duration * sample_rate / recorder.frame_length)
    for _ in range(n_frames):
        frames.append(recorder.read())
    flat = [s for frame in frames for s in frame]
    with wave.open(path, 'wb') as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(sample_rate)
        wf.writeframes(struct.pack(f'{len(flat)}h', *flat))

def dev_mode():
    """Fallback dev mode — reads commands from stdin."""
    log.info("TOPU Voice: DEV MODE — type commands and press Enter")
    while True:
        try:
            text = input("topu> ").strip()
            if text:
                dispatch(text)
        except (EOFError, KeyboardInterrupt):
            break

# ── Signal handling ───────────────────────────────────────────────────
def handle_signal(signum, frame):
    log.info("TOPU voice daemon stopping...")
    sys.exit(0)

signal.signal(signal.SIGTERM, handle_signal)
signal.signal(signal.SIGINT, handle_signal)

# ── Entry point ───────────────────────────────────────────────────────
if __name__ == "__main__":
    log.info("TOPU Voice Engine starting...")
    speak("TOPU is ready")
    run_pipeline()
