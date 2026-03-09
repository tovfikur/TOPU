#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════
#  TOPU OS — Chroot Post-Install Script
#  Runs INSIDE the chroot during ISO build (do not run directly)
# ═══════════════════════════════════════════════════════════════════════

set -e

log()  { echo "[TOPU:chroot] $1"; }
ok()   { echo "[OK] $1"; }

# ── Basic environment ─────────────────────────────────────────────────
export DEBIAN_FRONTEND=noninteractive
export LANG=en_US.UTF-8
locale-gen en_US.UTF-8

log "Setting hostname..."
echo "topu" > /etc/hostname
cat > /etc/hosts <<EOF
127.0.0.1   localhost
127.0.1.1   topu
EOF

# ── APT setup ─────────────────────────────────────────────────────────
log "Updating package lists..."
apt-get update -q

log "Installing core system packages..."
apt-get install -y --no-install-recommends \
  linux-image-generic linux-headers-generic \
  systemd systemd-sysv dbus \
  apt-utils ca-certificates gnupg2 curl wget sudo \
  network-manager network-manager-gnome \
  pipewire pipewire-audio wireplumber \
  alsa-utils pulseaudio-utils \
  flatpak \
  apparmor apparmor-utils ufw \
  btrfs-progs cryptsetup cryptsetup-initramfs \
  plymouth plymouth-themes \
  git build-essential cmake meson ninja-build pkg-config \
  python3 python3-pip python3-venv \
  xdg-user-dirs xdg-utils \
  live-boot \
  calamares calamares-settings-ubuntu

# ── Xanmod RT Kernel ──────────────────────────────────────────────────
log "Adding Xanmod PPA and installing RT kernel..."
wget -qO - https://dl.xanmod.org/archive.key | \
  gpg --dearmor -o /usr/share/keyrings/xanmod-archive-keyring.gpg
echo 'deb [signed-by=/usr/share/keyrings/xanmod-archive-keyring.gpg] \
  http://deb.xanmod.org releases main' \
  > /etc/apt/sources.list.d/xanmod-release.list
apt-get update -q
apt-get install -y linux-xanmod-rt-x64v3 || \
  warn "Xanmod RT not available — using generic kernel"
ok "Kernel installed"

# ── Wayland / Hyprland Stack ──────────────────────────────────────────
log "Installing Wayland and Hyprland dependencies..."
apt-get install -y \
  libwayland-dev wayland-protocols \
  libxkbcommon-dev libpixman-1-dev \
  libinput-dev libudev-dev libseat-dev \
  libgles2-mesa-dev libgbm-dev \
  libvulkan-dev vulkan-tools mesa-vulkan-drivers \
  libgbm1 libegl1 libgl1 \
  hyprland waybar mako-notifier foot swaylock swayidle \
  xdg-desktop-portal-hyprland xdg-desktop-portal-gtk \
  grim slurp wl-clipboard wf-recorder

ok "Wayland stack installed"

# ── GNOME / Display Manager purge ─────────────────────────────────────
log "Removing GNOME and display managers..."
apt-get remove --purge -y \
  gnome-shell gnome-session gdm3 lightdm sddm \
  gnome-control-center nautilus gnome-terminal \
  gnome-software gnome-shell-extensions \
  ubuntu-desktop ubuntu-gnome-desktop \
  xorg xserver-xorg xserver-xorg-core 2>/dev/null || true

apt-get autoremove --purge -y
ok "GNOME purged"

# ── Mask display managers permanently ─────────────────────────────────
log "Masking display managers..."
for dm in gdm3 gdm lightdm sddm xdm; do
  systemctl mask "$dm" 2>/dev/null || true
done

# ── Create TOPU user ──────────────────────────────────────────────────
log "Creating TOPU system user..."
useradd -m -s /bin/bash -G sudo,audio,video,input,plugdev topu
echo "topu:topu" | chpasswd

# ── Auto-login on TTY1 → TOPU Shell ──────────────────────────────────
log "Configuring TTY1 auto-login..."
mkdir -p /etc/systemd/system/getty@tty1.service.d/
cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin topu --noclear %I \$TERM
EOF

# Start Hyprland from bash_profile on TTY1
cat >> /home/topu/.bash_profile <<'EOF'
# TOPU Shell — Auto-start Hyprland on TTY1
[[ -z $DISPLAY && $XDG_VTNR -eq 1 ]] && exec Hyprland
EOF
chown topu:topu /home/topu/.bash_profile

# ── Install TOPU Shell Configs ─────────────────────────────────────────
log "Installing TOPU shell configuration..."
CONFIG_SRC="/tmp/topu-config"
TOPU_HOME="/home/topu"

mkdir -p "$TOPU_HOME/.config/hypr"
mkdir -p "$TOPU_HOME/.config/waybar"
mkdir -p "$TOPU_HOME/.config/mako"
mkdir -p "$TOPU_HOME/.config/foot"

cp -r "$CONFIG_SRC/hyprland/"*   "$TOPU_HOME/.config/hypr/"
cp -r "$CONFIG_SRC/waybar/"*     "$TOPU_HOME/.config/waybar/"
cp -r "$CONFIG_SRC/mako/"*       "$TOPU_HOME/.config/mako/"
cp -r "$CONFIG_SRC/foot/"*       "$TOPU_HOME/.config/foot/"
chown -R topu:topu "$TOPU_HOME/.config"

# ── Install Voice Engine ──────────────────────────────────────────────
log "Installing voice engine dependencies..."
apt-get install -y \
  portaudio19-dev libportaudio2 libportaudiocpp0 \
  ffmpeg libavcodec-dev libavformat-dev \
  python3-dev python3-pip

# Rhasspy / Whisper / Piper via pip
pip3 install --break-system-packages \
  pvporcupine pvrecorder \
  openai-whisper \
  piper-tts

# Copy voice configs
mkdir -p "$TOPU_HOME/.config/topu/voice"
cp -r /tmp/topu-voice/* "$TOPU_HOME/.config/topu/voice/"
chown -R topu:topu "$TOPU_HOME/.config/topu"

# Install voice daemon systemd service
cp /tmp/topu-voice/topu-voice.service /etc/systemd/system/
systemctl enable topu-voice.service

ok "Voice engine installed"

# ── Gaming Stack ──────────────────────────────────────────────────────
log "Installing gaming stack..."
apt-get install -y \
  gamemode libgamemode0 \
  mangohud \
  mesa-vulkan-drivers libvulkan1 \
  steam-devices  # udev rules for controllers

# Flatpak + Steam
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

ok "Gaming stack installed"

# ── Calamares Installer ───────────────────────────────────────────────
log "Configuring TOPU installer (Calamares)..."
mkdir -p /etc/calamares
cp -r /tmp/topu-installer/* /etc/calamares/
ok "Calamares configured"

# ── Plymouth boot splash ──────────────────────────────────────────────
log "Installing TOPU Plymouth theme..."
if [ -d "/tmp/topu-branding/plymouth" ]; then
  cp -r /tmp/topu-branding/plymouth /usr/share/plymouth/themes/topu
  update-alternatives --install \
    /usr/share/plymouth/themes/default.plymouth default.plymouth \
    /usr/share/plymouth/themes/topu/topu.plymouth 100
  update-alternatives --set default.plymouth \
    /usr/share/plymouth/themes/topu/topu.plymouth
  update-initramfs -u 2>/dev/null || true
fi
ok "Plymouth theme set"

# ── Security baseline ──────────────────────────────────────────────────
log "Applying security baseline..."
ufw enable 2>/dev/null || true
ufw default deny incoming 2>/dev/null || true
ufw default allow outgoing 2>/dev/null || true
systemctl disable ssh 2>/dev/null || true
ok "Security baseline applied"

# ── Enable services ────────────────────────────────────────────────────
log "Enabling system services..."
systemctl enable NetworkManager
systemctl enable pipewire
systemctl enable pipewire-pulse

# ── Final cleanup ──────────────────────────────────────────────────────
log "Final cleanup..."
apt-get autoremove --purge -y
apt-get clean
rm -rf /var/lib/apt/lists/*
rm -rf /tmp/*

echo ""
echo "[TOPU:chroot] ✅ Post-install complete — TOPU OS layers configured"
