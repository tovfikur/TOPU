#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════
#  TOPU OS — Chroot Post-Install Script
#  Runs INSIDE the chroot during ISO build (do not run directly)
# ═══════════════════════════════════════════════════════════════════════

set -e

log()  { echo "[TOPU:chroot] $1"; }
ok()   { echo "[OK] $1"; }
warn() { echo "[WARN] $1 — continuing"; }

# ── Basic environment ─────────────────────────────────────────────────
export DEBIAN_FRONTEND=noninteractive

log "Setting hostname..."
echo "topu" > /etc/hostname
cat > /etc/hosts <<EOF
127.0.0.1   localhost
127.0.1.1   topu
EOF

# ── APT setup ─────────────────────────────────────────────────────────
log "Updating package lists..."
apt-get update -q

# ── Install locales FIRST (locale-gen needs this) ─────────────────────
log "Installing locales..."
apt-get install -y --no-install-recommends locales
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen en_US.UTF-8
update-locale LANG=en_US.UTF-8
export LANG=en_US.UTF-8

# ── Core system packages ───────────────────────────────────────────────
log "Installing core system packages..."
apt-get install -y --no-install-recommends \
  linux-image-generic linux-headers-generic \
  systemd systemd-sysv dbus \
  apt-utils ca-certificates gnupg2 curl wget sudo \
  network-manager \
  pipewire pipewire-audio wireplumber \
  alsa-utils \
  flatpak \
  apparmor apparmor-utils ufw \
  btrfs-progs cryptsetup cryptsetup-initramfs \
  plymouth plymouth-themes \
  git build-essential cmake meson ninja-build pkg-config \
  python3 python3-pip python3-venv \
  xdg-user-dirs xdg-utils \
  live-boot live-config \
  unzip wget curl

# ── Calamares installer ────────────────────────────────────────────────
log "Installing Calamares installer..."
apt-get install -y calamares 2>/dev/null || \
  warn "calamares not in default repos — skipping (install manually post-build)"

# ── Xanmod RT Kernel ──────────────────────────────────────────────────
log "Adding Xanmod PPA and installing RT kernel..."
wget -qO - https://dl.xanmod.org/archive.key | \
  gpg --dearmor -o /usr/share/keyrings/xanmod-archive-keyring.gpg
echo 'deb [signed-by=/usr/share/keyrings/xanmod-archive-keyring.gpg] http://deb.xanmod.org releases main' \
  > /etc/apt/sources.list.d/xanmod-release.list
apt-get update -q
apt-get install -y linux-xanmod-rt-x64v3 2>/dev/null || \
  warn "Xanmod RT not available — using generic kernel"
ok "Kernel installed"

# ── Hyprland PPA + Wayland stack ─────────────────────────────────────
log "Adding Hyprland PPA..."
apt-get install -y software-properties-common 2>/dev/null || true
add-apt-repository -y ppa:hyprwm/hyprland 2>/dev/null || \
  warn "Hyprland PPA unavailable"
apt-get update -q

log "Installing Wayland and Hyprland stack..."
apt-get install -y \
  libwayland-dev wayland-protocols \
  libxkbcommon-dev libpixman-1-dev \
  libinput-dev libudev-dev libseat-dev \
  libgles2-mesa-dev libgbm-dev \
  libvulkan-dev mesa-vulkan-drivers \
  libgbm1 libegl1 libgl1 || warn "Some Wayland libs unavailable"

# Install each shell component with fallback
for pkg in hyprland waybar mako-notifier foot swaylock swayidle \
           xdg-desktop-portal-hyprland xdg-desktop-portal-gtk \
           grim slurp wl-clipboard wf-recorder; do
  apt-get install -y "$pkg" 2>/dev/null || warn "$pkg not found — skipping"
done
ok "Wayland stack installed"

# ── GNOME / Display Manager purge ─────────────────────────────────────
log "Removing GNOME and display managers..."
apt-get remove --purge -y \
  gnome-shell gnome-session gdm3 lightdm sddm \
  gnome-control-center nautilus gnome-terminal \
  gnome-software gnome-shell-extensions \
  ubuntu-desktop ubuntu-gnome-desktop \
  xorg xserver-xorg xserver-xorg-core 2>/dev/null || true
apt-get autoremove --purge -y 2>/dev/null || true
ok "GNOME purged"

# ── Mask display managers permanently ─────────────────────────────────
log "Masking display managers..."
for dm in gdm3 gdm lightdm sddm xdm; do
  systemctl mask "$dm" 2>/dev/null || true
done

# ── Create TOPU user ──────────────────────────────────────────────────
log "Creating TOPU system user..."
useradd -m -s /bin/bash topu 2>/dev/null || true
usermod -aG sudo,audio,video,input,plugdev topu 2>/dev/null || true
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

if [ -d "$CONFIG_SRC" ]; then
  mkdir -p "$TOPU_HOME/.config/hypr"
  mkdir -p "$TOPU_HOME/.config/waybar"
  mkdir -p "$TOPU_HOME/.config/mako"
  mkdir -p "$TOPU_HOME/.config/foot"

  [ -d "$CONFIG_SRC/hyprland" ] && cp -r "$CONFIG_SRC/hyprland/"* "$TOPU_HOME/.config/hypr/"
  [ -d "$CONFIG_SRC/waybar"   ] && cp -r "$CONFIG_SRC/waybar/"*   "$TOPU_HOME/.config/waybar/"
  [ -d "$CONFIG_SRC/mako"     ] && cp -r "$CONFIG_SRC/mako/"*     "$TOPU_HOME/.config/mako/"
  [ -d "$CONFIG_SRC/foot"     ] && cp -r "$CONFIG_SRC/foot/"*     "$TOPU_HOME/.config/foot/"
  chown -R topu:topu "$TOPU_HOME/.config"
fi

# ── Install Voice Engine ──────────────────────────────────────────────
log "Installing voice engine dependencies..."
apt-get install -y \
  portaudio19-dev libportaudio2 \
  ffmpeg python3-dev python3-pip 2>/dev/null || true

# Install piper-tts in a venv (PEP 668 safe)
PIPER_VENV="/opt/topu/piper-venv"
mkdir -p /opt/topu
python3 -m venv "$PIPER_VENV"
"$PIPER_VENV/bin/pip" install --upgrade pip -q
"$PIPER_VENV/bin/pip" install piper-tts pvporcupine pvrecorder 2>/dev/null || \
  warn "Some voice packages failed — install manually post-boot"
ln -sf "$PIPER_VENV/bin/piper" /usr/local/bin/piper 2>/dev/null || true

# Copy voice configs
if [ -d "/tmp/topu-voice" ]; then
  mkdir -p "$TOPU_HOME/.config/topu/voice"
  cp -r /tmp/topu-voice/* "$TOPU_HOME/.config/topu/voice/" 2>/dev/null || true
  chown -R topu:topu "$TOPU_HOME/.config/topu"
  # Install voice daemon systemd service
  [ -f "/tmp/topu-voice/topu-voice.service" ] && \
    cp /tmp/topu-voice/topu-voice.service /etc/systemd/system/ && \
    systemctl enable topu-voice.service 2>/dev/null || true
fi
ok "Voice engine installed"

# ── Gaming Stack ──────────────────────────────────────────────────────
log "Installing gaming stack..."
for pkg in gamemode libgamemode0 mangohud mesa-vulkan-drivers libvulkan1 steam-devices; do
  apt-get install -y "$pkg" 2>/dev/null || warn "$pkg not found — skipping"
done
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo 2>/dev/null || true
ok "Gaming stack installed"

# ── Calamares config ──────────────────────────────────────────────────
log "Configuring TOPU installer..."
if [ -d "/tmp/topu-installer" ]; then
  mkdir -p /etc/calamares
  cp -r /tmp/topu-installer/* /etc/calamares/ 2>/dev/null || true
fi
ok "Installer configured"

# ── Plymouth boot splash ──────────────────────────────────────────────
log "Installing TOPU Plymouth theme..."
if [ -d "/tmp/topu-branding/plymouth" ]; then
  cp -r /tmp/topu-branding/plymouth /usr/share/plymouth/themes/topu
  update-alternatives --install \
    /usr/share/plymouth/themes/default.plymouth default.plymouth \
    /usr/share/plymouth/themes/topu/topu.plymouth 100 2>/dev/null || true
  update-alternatives --set default.plymouth \
    /usr/share/plymouth/themes/topu/topu.plymouth 2>/dev/null || true
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
systemctl enable NetworkManager  2>/dev/null || true
systemctl enable pipewire        2>/dev/null || true
systemctl enable pipewire-pulse  2>/dev/null || true

# ── Final cleanup ──────────────────────────────────────────────────────
log "Final cleanup..."
apt-get autoremove --purge -y 2>/dev/null || true
apt-get clean
rm -rf /var/lib/apt/lists/*

echo ""
echo "[TOPU:chroot] ✅ Post-install complete — TOPU OS layers configured"
