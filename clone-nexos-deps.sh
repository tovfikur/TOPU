#!/bin/bash
# ═══════════════════════════════════════════════════════════════════
#  TOPU OS — Dependency Clone Script
#  Run this on: Pop!_OS 24.04 VM (recommended) or WSL2 Ubuntu 24.04
#  Usage:  bash clone-nexos-deps.sh
# ═══════════════════════════════════════════════════════════════════

set -e
warn() { echo "  [WARN] $1 — continuing anyway"; }

TOPU_DEV="$HOME/topu-dev"
mkdir -p "$TOPU_DEV"
cd "$TOPU_DEV"

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║          TOPU OS — Dev Setup & Clone Repos           ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

# ── Helper ──────────────────────────────────────────────────────────
clone_repo() {
  local name="$1"
  local url="$2"
  local flags="${3:-}"
  if [ -d "$name" ]; then
    echo "  [SKIP]  $name already exists"
  else
    echo "  [CLONE] $name"
    git clone $flags "$url" "$name"
  fi
}

# ─────────────────────────────────────────────────────────────────────
echo "▸ [1/5] Core Shell (Hyprland + Wayland)"
echo "─────────────────────────────────────────"
clone_repo "Hyprland"  "https://github.com/hyprwm/Hyprland.git"  "--recursive"
clone_repo "Waybar"    "https://github.com/Alexays/Waybar.git"
clone_repo "mako"      "https://github.com/emersion/mako.git"
clone_repo "swaylock"  "https://github.com/swaywm/swaylock.git"
clone_repo "swayidle"  "https://github.com/swaywm/swayidle.git"
clone_repo "yazi"      "https://github.com/sxyazi/yazi.git"
clone_repo "foot"      "https://codeberg.org/dnkl/foot.git"

echo ""
echo "▸ [2/5] Voice Engine"
echo "─────────────────────────────────────────"
clone_repo "whisper.cpp"  "https://github.com/ggerganov/whisper.cpp.git"
clone_repo "piper"        "https://github.com/rhasspy/piper.git"
clone_repo "rhasspy3"     "https://github.com/rhasspy/rhasspy3.git"
cd "$TOPU_DEV"

echo ""
echo "▸ [3/5] Gaming Stack"
echo "─────────────────────────────────────────"
clone_repo "proton-ge-custom"  "https://github.com/GloriousEggroll/proton-ge-custom.git"
clone_repo "dxvk"              "https://github.com/doitsujin/dxvk.git"
clone_repo "vkd3d-proton"      "https://github.com/HansKristian-Work/vkd3d-proton.git"   "--recursive"
clone_repo "MangoHud"          "https://github.com/flightlessmango/MangoHud.git"
clone_repo "gamemode"          "https://github.com/FeralInteractive/gamemode.git"

echo ""
echo "▸ [4/5] Screen Capture & Utilities"
echo "─────────────────────────────────────────"
clone_repo "wf-recorder"  "https://github.com/ammen99/wf-recorder.git"

echo ""
echo "▸ [5/5] Installing Build Dependencies (APT)"
echo "─────────────────────────────────────────"

# ── Add Hyprland PPA (needed for xdg-desktop-portal-hyprland) ────────
echo "  Adding Hyprland PPA..."
sudo add-apt-repository -y ppa:hyprwm/hyprland 2>/dev/null || \
  warn "Hyprland PPA unavailable — portal will be built from source"

sudo apt update -qq

# ── Core build tools ──────────────────────────────────────────────────
sudo apt install -y \
  build-essential cmake meson ninja-build pkg-config \
  git curl wget python3 python3-pip python3-venv \
  cargo golang \
  libwayland-dev wayland-protocols \
  libxkbcommon-dev libpixman-1-dev \
  libinput-dev libudev-dev libseat-dev \
  libgles2-mesa-dev libgbm-dev \
  libvulkan-dev vulkan-tools mesa-vulkan-drivers \
  libpipewire-0.3-dev pipewire wireplumber \
  libportaudio2 portaudio19-dev \
  ffmpeg libavcodec-dev libavformat-dev

# ── Wayland shell packages (correct Ubuntu/Pop!_OS package names) ─────
# Note: 'mako' = mako-notifier | 'foot' = build from source (not in apt)
#       'xdg-desktop-portal-hyprland' requires Hyprland PPA
sudo apt install -y \
  swaylock swayidle mako-notifier waybar \
  grim slurp wl-clipboard wf-recorder \
  gamemode mangohud flatpak || \
  warn "Some optional packages unavailable — check apt errors above"

# xdg-desktop-portal-hyprland — try from PPA, skip if unavailable
sudo apt install -y xdg-desktop-portal-hyprland 2>/dev/null || \
  warn "xdg-desktop-portal-hyprland not found — will build from source"

# Install rustup if cargo not already present
if ! command -v rustup &>/dev/null; then
  echo "  Installing Rust toolchain..."
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path
  source "$HOME/.cargo/env"
fi

echo ""
echo "▸ Installing Porcupine (Wake Word)"
echo "─────────────────────────────────────────"
pip3 install --break-system-packages pvporcupine pvrecorder 2>/dev/null || \
  pip3 install pvporcupine pvrecorder || \
  warn "Porcupine install failed — add API key later"

echo ""
echo "▸ Building whisper.cpp"
echo "─────────────────────────────────────────"
cd "$TOPU_DEV/whisper.cpp"
make -j$(nproc)
echo "  Downloading Whisper 'small.en' model for dev (fast)..."
bash ./models/download-ggml-model.sh small.en
cd "$TOPU_DEV"

echo ""
echo "▸ Installing Rhasspy 3 Python deps"
echo "─────────────────────────────────────────"
cd "$TOPU_DEV/rhasspy3"
python3 -m venv .venv
source .venv/bin/activate
# rhasspy3 uses pyproject.toml, not requirements.txt
if [ -f "requirements.txt" ]; then
  pip install -r requirements.txt
elif [ -f "pyproject.toml" ] || [ -f "setup.py" ]; then
  pip install -e .
else
  # Install core rhasspy3 deps manually
  pip install \
    flask flask-cors \
    requests aiohttp \
    pyyaml pysilero-vad
  warn "rhasspy3 requirements not found — installed core deps manually"
fi
deactivate
cd "$TOPU_DEV"

echo ""
echo "▸ Installing Piper TTS"
echo "─────────────────────────────────────────"
# Pop!_OS 24.04 / Ubuntu 24.04 blocks system-wide pip installs (PEP 668).
# Install piper-tts inside a dedicated venv instead.
PIPER_VENV="$TOPU_DEV/piper-venv"
python3 -m venv "$PIPER_VENV"
"$PIPER_VENV/bin/pip" install --upgrade pip -q
"$PIPER_VENV/bin/pip" install piper-tts
echo "  Piper installed in: $PIPER_VENV"
echo "  Run it with: $PIPER_VENV/bin/piper"
# Symlink to /usr/local/bin so voice daemon can find it
sudo ln -sf "$PIPER_VENV/bin/piper" /usr/local/bin/piper 2>/dev/null || \
  warn "Could not symlink piper to /usr/local/bin (run manually if needed)"
cd "$TOPU_DEV"

echo ""
echo "▸ Installing yazi (Rust TUI file manager)"
echo "─────────────────────────────────────────"
cargo install yazi-fm yazi-cli

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  ✅  TOPU OS dependencies cloned & built!            ║"
echo "║                                                      ║"
echo "║  Repos at: ~/topu-dev/                              ║"
echo "║                                                      ║"
echo "║  NEXT STEPS:                                         ║"
echo "║  1. Get Picovoice API key: console.picovoice.ai      ║"
echo "║     → Train 'Hey TOPU' wake word model               ║"
echo "║  2. Build Hyprland: cd ~/topu-dev/Hyprland           ║"
echo "║     → make all && sudo make install                  ║"
echo "║  3. Download Piper voice model (en_US-ryan):         ║"
echo "║     https://github.com/rhasspy/piper/releases        ║"
echo "║  4. Build TOPU ISO: cd ~/TOPU                        ║"
echo "║     sudo bash build/build.sh                         ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""
