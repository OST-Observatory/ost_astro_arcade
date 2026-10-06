#!/usr/bin/env bash
# One-time kiosk setup for the OST Astro Arcade on Ubuntu Server 24.04 LTS (run as root).
#   sudo bash kiosk/install.sh [--lan 192.168.0.0/16]
# Idempotent: safe to run again after changes. Read kiosk/README.md first (BIOS settings,
# GRUB password, optional read-only root). Make sure your SSH key works BEFORE running it:
# password logins over SSH are switched off.
set -euo pipefail

LAN_CIDR="192.168.0.0/16"
[[ "${1:-}" == "--lan" ]] && LAN_CIDR="$2"

KIOSK_USER=kiosk
DATA_DIR=/var/lib/ost
APP_DIR=/opt/ost
HERE="$(cd "$(dirname "$0")" && pwd)"

[[ $EUID -eq 0 ]] || { echo "Run as root (sudo)." >&2; exit 1; }
if [[ -z "$(find /home/*/.ssh/authorized_keys /root/.ssh/authorized_keys -size +0 2>/dev/null)" ]]; then
  echo "No SSH authorized_keys found. Add your key first, or you will lock yourself out." >&2
  exit 1
fi

echo "==> Packages"
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  linux-generic-hwe-24.04 cage mesa-vulkan-drivers libvulkan1 vulkan-tools \
  libgl1 libegl1 libgles2 libwayland-client0 libwayland-cursor0 libwayland-egl1 libxkbcommon0 \
  libasound2t64 pipewire pipewire-pulse wireplumber fonts-dejavu-core \
  polkitd unattended-upgrades ufw openssh-server rsync

echo "==> Kiosk user (no sudo, no password, no login shell)"
if ! id "$KIOSK_USER" &>/dev/null; then
  useradd --system --create-home --shell /usr/sbin/nologin \
    --groups video,render,input,audio "$KIOSK_USER"
fi
passwd -l "$KIOSK_USER" >/dev/null
install -d -o "$KIOSK_USER" -g "$KIOSK_USER" -m 750 "$DATA_DIR"
install -d -m 755 "$APP_DIR/releases" "$APP_DIR/external"

echo "==> PAM + systemd units"
install -m 644 "$HERE/pam.d/cage" /etc/pam.d/cage
install -m 644 "$HERE/systemd/ost-arcade.service" /etc/systemd/system/
install -m 644 "$HERE/systemd/ost-watchdog.service" /etc/systemd/system/
install -m 644 "$HERE/systemd/ost-watchdog.timer" /etc/systemd/system/
install -m 755 "$HERE/bin/ost-watchdog" /usr/local/sbin/ost-watchdog
systemctl daemon-reload
systemctl disable getty@tty1.service || true
systemctl enable ost-arcade.service ost-watchdog.timer
systemctl set-default graphical.target

echo "==> Kiosk may power off / reboot (admin menu), nothing else"
install -m 644 "$HERE/polkit/50-ost-kiosk.rules" /etc/polkit-1/rules.d/50-ost-kiosk.rules

echo "==> Hardening"
systemctl mask ctrl-alt-del.target
echo "kernel.sysrq = 0" > /etc/sysctl.d/90-ost-kiosk.conf
sysctl --system >/dev/null
# No login prompts on other virtual terminals (cage itself blocks VT switching).
mkdir -p /etc/systemd/logind.conf.d
printf '[Login]\nNAutoVTs=0\nReserveVT=0\nHandlePowerKey=poweroff\n' > /etc/systemd/logind.conf.d/90-ost-kiosk.conf
# Hidden boot menu, quiet boot.
sed -i 's/^GRUB_TIMEOUT_STYLE=.*/GRUB_TIMEOUT_STYLE=hidden/; s/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=0/' /etc/default/grub
sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT="quiet splash loglevel=3 vt.global_cursor_default=0"/' /etc/default/grub
update-grub

echo "==> SSH: keys only"
mkdir -p /etc/ssh/sshd_config.d
printf 'PasswordAuthentication no\nKbdInteractiveAuthentication no\nPermitRootLogin no\n' > /etc/ssh/sshd_config.d/90-ost-kiosk.conf
systemctl reload ssh || systemctl reload sshd || true

echo "==> Firewall: only SSH from $LAN_CIDR"
ufw --force reset >/dev/null
ufw default deny incoming
ufw default allow outgoing
ufw allow from "$LAN_CIDR" to any port 22 proto tcp
ufw --force enable

echo "==> Automatic security updates with reboot at 04:30"
cat > /etc/apt/apt.conf.d/52ost-unattended <<'EOF'
Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Automatic-Reboot-Time "04:30";
EOF
systemctl enable --now unattended-upgrades

echo
echo "Done. Next: deploy a build from the dev machine (kiosk/deploy.sh <host>), then reboot."
echo "Manual steps left: BIOS password + boot order, GRUB password (kiosk/README.md)."
