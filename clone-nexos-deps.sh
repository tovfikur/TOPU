#!/bin/bash
# ═══════════════════════════════════════════════════════════════════
#  NexOS — Dependency Clone Script
#  Run this on: WSL2 (Ubuntu 24.04) or your Linux VM (Pop!_OS 24.04)
#  Usage:  bash clone-nexos-deps.sh
# ═══════════════════════════════════════════════════════════════════

set -e  # Exit on any error

NEXOS_DEV="$HOME/nexos-dev"
mkdir -p "$NEXOS_DEV"
cd "$NEXOS_DEV"

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║         NexOS Dev Setup — Cloning Repos              ║"
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

# foot terminal is on Codeberg
if [ -d "foot" ]; then
  echo "  [SKIP]  foot already exists"
else
  echo "  [CLONE] foot"
  git clone https://codeberg.org/dnkl/foot.git foot
fi

echo ""
echo "▸ [2/5] Voice Engine"
echo "─────────────────────────────────────────"
clone_repo "whisper.cpp"  "https://github.com/ggerganov/whisper.cpp.git"
clone_repo "piper"        "https://github.com/rhasspy/piper.git"
clone_repo "rhasspy3"     "https://github.com/rhasspy/rhasspy3.git"

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
sudo apt update -qq
sudo apt install -y \
  build-essential cmake meson ninja-build pkg-config \
  git curl wget python3 python3-pip python3-venv \
  rustup cargo golang \
  libwayland-dev wayland-protocols \
  libxkbcommon-dev libpixman-1-dev \
  libinput-dev libudev-dev libseat-dev \
  libgles2-mesa-dev libgbm-dev \
  libvulkan-dev vulkan-tools mesa-vulkan-drivers \
  libpipewire-0.3-dev pipewire wireplumber \
  libportaudio2 portaudio19-dev \
  ffmpeg libavcodec-dev libavformat-dev \
  swaylock swayidle mako waybar foot \
  grim slurp wl-clipboard wf-recorder \
  xdg-desktop-portal-hyprland \
  gamemode mangohud flatpak

echo ""
echo "▸ Installing Porcupine (Wake Word)"
echo "─────────────────────────────────────────"
pip3 install pvporcupine pvrecorder

echo ""
echo "▸ Building whisper.cpp"
echo "─────────────────────────────────────────"
cd "$NEXOS_DEV/whisper.cpp"
make -j$(nproc)
echo "  Downloading Whisper 'small.en' model for dev (fast)..."
bash ./models/download-ggml-model.sh small.en
cd "$NEXOS_DEV"

echo ""
echo "▸ Installing Rhasspy 3 Python deps"
echo "─────────────────────────────────────────"
cd "$NEXOS_DEV/rhasspy3"
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
deactivate
cd "$NEXOS_DEV"

echo ""
echo "▸ Installing Piper TTS"
echo "─────────────────────────────────────────"
cd "$NEXOS_DEV/piper"
pip3 install -e .
cd "$NEXOS_DEV"

echo ""
echo "▸ Installing yazi (Rust TUI file manager)"
echo "─────────────────────────────────────────"
cargo install yazi-fm yazi-cli

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  ✅  All NexOS dependencies cloned & built!          ║"
echo "║                                                      ║"
echo "║  Repos at: ~/nexos-dev/                             ║"
echo "║                                                      ║"
echo "║  NEXT STEPS:                                         ║"
echo "║  1. Get Picovoice API key: console.picovoice.ai      ║"
echo "║     → Train 'Hey Nex' wake word model                ║"
echo "║  2. Build Hyprland: cd ~/nexos-dev/Hyprland          ║"
echo "║     → make all && sudo make install                  ║"
echo "║  3. Download Piper voice model (en_US-ryan):         ║"
echo "║     https://github.com/rhasspy/piper/releases        ║"
echo "║  4. On VM only: install Xanmod-RT kernel             ║"
echo "║     (see nexos_dev_setup_guide.md for command)       ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""
