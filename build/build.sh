#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════
#  TOPU OS — Main ISO Build Script
#  Run on: Pop!_OS 24.04 / Ubuntu 24.04 VM (NOT WSL2)
#  Output: build/output/TOPU.iso
#
#  Usage:  sudo bash build.sh
# ═══════════════════════════════════════════════════════════════════════

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$SCRIPT_DIR"
CHROOT_DIR="$BUILD_DIR/chroot"
STAGING_DIR="$BUILD_DIR/staging"
OUTPUT_DIR="$BUILD_DIR/output"
ISO_LABEL="TOPU"
ISO_VERSION="1.0"
ISO_NAME="TOPU-${ISO_VERSION}-amd64.iso"
ARCH="amd64"
SUITE="noble"   # Ubuntu 24.04 LTS codename
MIRROR="http://archive.ubuntu.com/ubuntu"

# ── Colors ──────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'
YELLOW='\033[1;33m'; BOLD='\033[1m'; NC='\033[0m'

log()  { echo -e "${CYAN}[TOPU]${NC} $1"; }
ok()   { echo -e "${GREEN}[OK]${NC}   $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; exit 1; }

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║           TOPU OS — ISO Build System  v${ISO_VERSION}             ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""

# ── Checks ───────────────────────────────────────────────────────────
[[ $EUID -ne 0 ]] && fail "This script must be run as root (sudo bash build.sh)"

# ── Install build tools (self-contained — no pre-install needed) ──────
log "Installing ISO build tools..."
apt-get update -qq --allow-releaseinfo-change 2>/dev/null || apt-get update -qq || true
apt-get install -y \
  debootstrap squashfs-tools xorriso \
  grub-pc-bin grub-efi-amd64-bin \
  mtools dosfstools isolinux syslinux-common \
  live-build git curl wget python3 build-essential cmake &>/dev/null
ok "Build tools ready"

# ── Clean dirs ────────────────────────────────────────────────────────
log "Preparing build directories..."
rm -rf "$CHROOT_DIR" "$STAGING_DIR"
mkdir -p "$CHROOT_DIR" "$STAGING_DIR"/{live,boot/grub,EFI/BOOT,isolinux} "$OUTPUT_DIR"

# ── Step 1: Bootstrap Ubuntu base ─────────────────────────────────────
log "Bootstrapping Ubuntu 24.04 base (this takes ~5-10 min)..."
debootstrap --arch=$ARCH --variant=minbase "$SUITE" "$CHROOT_DIR" "$MIRROR"
ok "Base system bootstrapped"

# ── Step 2: Configure chroot ──────────────────────────────────────────
log "Configuring chroot environment..."

# Mount virtual filesystems
mount --bind /dev     "$CHROOT_DIR/dev"
mount --bind /dev/pts "$CHROOT_DIR/dev/pts"
mount --bind /proc    "$CHROOT_DIR/proc"
mount --bind /sys     "$CHROOT_DIR/sys"
mount --bind /run     "$CHROOT_DIR/run"

# Set up resolv.conf for DNS inside chroot
cp /etc/resolv.conf "$CHROOT_DIR/etc/resolv.conf"

# Set up APT sources (Ubuntu only — no 3rd party repos to avoid GPG issues)
cat > "$CHROOT_DIR/etc/apt/sources.list" <<EOF
deb $MIRROR $SUITE main restricted universe multiverse
deb $MIRROR $SUITE-updates main restricted universe multiverse
deb $MIRROR $SUITE-security main restricted universe multiverse
EOF

# Pre-accept apt mirror errors (transient sync issues)
mkdir -p "$CHROOT_DIR/etc/apt/apt.conf.d"
cat > "$CHROOT_DIR/etc/apt/apt.conf.d/99topu-build" <<EOF
Acquire::Check-Valid-Until "false";
Acquire::Retries "3";
APT::Get::Fix-Missing "true";
EOF

# Copy project configs into chroot
cp -r "$PROJECT_ROOT/config"   "$CHROOT_DIR/tmp/topu-config"
cp -r "$PROJECT_ROOT/branding" "$CHROOT_DIR/tmp/topu-branding"
cp -r "$PROJECT_ROOT/voice"    "$CHROOT_DIR/tmp/topu-voice"
cp -r "$PROJECT_ROOT/installer" "$CHROOT_DIR/tmp/topu-installer"
cp    "$BUILD_DIR/post-install.sh" "$CHROOT_DIR/tmp/post-install.sh"
chmod +x "$CHROOT_DIR/tmp/post-install.sh"

ok "Chroot configured"

# ── Step 3: Run post-install inside chroot ────────────────────────────
log "Running TOPU post-install inside chroot (this takes ~15-30 min)..."
chroot "$CHROOT_DIR" /bin/bash /tmp/post-install.sh
ok "Post-install complete"

# ── Step 4: Clean chroot ──────────────────────────────────────────────
log "Cleaning chroot..."
chroot "$CHROOT_DIR" apt-get autoremove --purge -y &>/dev/null || true
chroot "$CHROOT_DIR" apt-get clean &>/dev/null
rm -f "$CHROOT_DIR/etc/resolv.conf"
rm -f "$CHROOT_DIR/tmp/post-install.sh"
rm -rf "$CHROOT_DIR/tmp/topu-config" "$CHROOT_DIR/tmp/topu-branding" \
        "$CHROOT_DIR/tmp/topu-voice" "$CHROOT_DIR/tmp/topu-installer"

# Unmount virtual filesystems
for mnt in run sys proc dev/pts dev; do
  umount "$CHROOT_DIR/$mnt" 2>/dev/null || true
done
ok "Chroot cleaned"

# ── Step 5: Create squashfs ────────────────────────────────────────────
log "Compressing rootfs to squashfs (this takes ~10-20 min)..."
mksquashfs "$CHROOT_DIR" "$STAGING_DIR/live/filesystem.squashfs" \
  -comp xz -Xbcj x86 -b 1M -no-progress
ok "Squashfs created ($(du -sh "$STAGING_DIR/live/filesystem.squashfs" | cut -f1))"

# Print filesystem size
printf $(du -sx --block-size=1 "$CHROOT_DIR" | cut -f1) > \
  "$STAGING_DIR/live/filesystem.size"

# ── Step 6: Copy kernel and initrd ────────────────────────────────────
log "Copying kernel and initrd..."
KERNEL=$(ls "$CHROOT_DIR/boot/vmlinuz-"* | sort -V | tail -1)
INITRD=$(ls "$CHROOT_DIR/boot/initrd.img-"* | sort -V | tail -1)
cp "$KERNEL" "$STAGING_DIR/live/vmlinuz"
cp "$INITRD" "$STAGING_DIR/live/initrd"
ok "Kernel: $(basename $KERNEL)"

# ── Step 7: Set up GRUB (BIOS + UEFI) ────────────────────────────────
log "Configuring GRUB bootloader..."

# Copy TOPU GRUB theme into staging
if [ -d "$PROJECT_ROOT/branding/grub-theme" ]; then
  mkdir -p "$STAGING_DIR/boot/grub/themes"
  cp -r "$PROJECT_ROOT/branding/grub-theme" "$STAGING_DIR/boot/grub/themes/topu"
fi

cat > "$STAGING_DIR/boot/grub/grub.cfg" <<'GRUBEOF'
set default=0
set timeout=5

if [ -d /boot/grub/themes/topu ]; then
  set theme=/boot/grub/themes/topu/theme.txt
fi

menuentry "Install TOPU OS" --class topu {
  linux  /live/vmlinuz boot=live quiet splash
  initrd /live/initrd
}

menuentry "Try TOPU OS (Live)" --class topu {
  linux  /live/vmlinuz boot=live nomodeset
  initrd /live/initrd
}

menuentry "TOPU OS — Safe Mode" --class topu {
  linux  /live/vmlinuz boot=live nomodeset noapic
  initrd /live/initrd
}
GRUBEOF

# Build BIOS bootable GRUB image with minimal embedded modules
# (full module set loaded from ISO at runtime — avoids 0x78000 size limit)
grub-mkstandalone \
  --format=i386-pc \
  --output="$STAGING_DIR/isolinux/core.img" \
  --install-modules="normal linux" \
  --modules="normal linux" \
  "boot/grub/grub.cfg=$STAGING_DIR/boot/grub/grub.cfg"

cat /usr/lib/grub/i386-pc/cdboot.img "$STAGING_DIR/isolinux/core.img" \
  > "$STAGING_DIR/isolinux/bios.img"

# Build UEFI boot image
grub-mkstandalone \
  --format=x86_64-efi \
  --output="$STAGING_DIR/EFI/BOOT/bootx64.efi" \
  --install-modules="linux linux16 linuxefi normal iso9660 search fat" \
  "boot/grub/grub.cfg=$STAGING_DIR/boot/grub/grub.cfg"

# Create EFI FAT image
(cd "$STAGING_DIR" && \
  dd if=/dev/zero of=efiboot.img bs=1M count=10 2>/dev/null && \
  mkfs.vfat efiboot.img && \
  mmd -i efiboot.img EFI BOOT && \
  mcopy -i efiboot.img EFI/BOOT/bootx64.efi ::EFI/BOOT/
)
ok "GRUB configured (BIOS + UEFI)"


# ── Step 8: Master the ISO ─────────────────────────────────────────────
log "Mastering TOPU.iso..."
xorriso \
  -as mkisofs \
  -iso-level 3 \
  -full-iso9660-filenames \
  -volid "$ISO_LABEL" \
  -graft-points \
  -eltorito-boot isolinux/bios.img \
    -no-emul-boot \
    -boot-load-size 4 \
    -boot-info-table \
    --grub2-boot-info \
    --grub2-mbr /usr/lib/grub/i386-pc/boot_hybrid.img \
  -eltorito-alt-boot \
    -e --interval:appended_partition_2:all:: \
    -no-emul-boot \
    -append_partition 2 0xef "$STAGING_DIR/efiboot.img" \
  -output "$OUTPUT_DIR/$ISO_NAME" \
  "$STAGING_DIR"

ok "ISO created: $OUTPUT_DIR/$ISO_NAME"
ISO_SIZE=$(du -sh "$OUTPUT_DIR/$ISO_NAME" | cut -f1)

# ── Done ───────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}${BOLD}║  ✅  TOPU OS ISO build complete!                         ║${NC}"
echo -e "${GREEN}${BOLD}║                                                          ║${NC}"
echo -e "${GREEN}${BOLD}║  Output: build/output/${ISO_NAME}         ║${NC}"
echo -e "${GREEN}${BOLD}║  Size:   ${ISO_SIZE}                                              ║${NC}"
echo -e "${GREEN}${BOLD}║                                                          ║${NC}"
echo -e "${GREEN}${BOLD}║  Flash to USB:                                           ║${NC}"
echo -e "${GREEN}${BOLD}║  sudo dd if=$OUTPUT_DIR/$ISO_NAME                        ║${NC}"
echo -e "${GREEN}${BOLD}║          of=/dev/sdX bs=4M status=progress && sync       ║${NC}"
echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
