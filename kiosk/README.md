# Kiosk setup (NiPoGi E3B, Ubuntu Server 24.04 LTS)

The kiosk boots straight into the OST Astro Arcade: `systemd` → `cage` (a Wayland compositor
that shows exactly one fullscreen app) → Godot. There is no desktop and no login prompt, and
switching to another virtual terminal is disabled. If the app crashes, systemd restarts it.
If it hangs, the watchdog restarts it (heartbeat older than 60 s).

## 1. Prepare the machine

1. **BIOS** (DEL/F2 at boot):
   - set a supervisor password
   - boot only from the internal SSD and disable USB/network boot
   - set *Restore on AC power loss* to **Power On**
   - optional: an RTC wake time for daily auto-start
2. Install **Ubuntu Server 24.04 LTS** (minimal) with an admin account (e.g. `ostadmin`) and
   OpenSSH. Optionally create a separate partition for `/var/lib/ost` (scores, telemetry); this
   is needed for the read-only root in step 5.
3. Copy your SSH key: `ssh-copy-id ostadmin@<kiosk>`. Test that a key login works.

## 2. Install

```bash
# on the dev machine
rsync -a kiosk/ ostadmin@<kiosk>:ost-kiosk/
ssh ostadmin@<kiosk> 'sudo bash ost-kiosk/install.sh --lan 192.168.0.0/16'
```

`install.sh` does the following:
- installs cage, Mesa Vulkan (RADV), PipeWire and the HWE kernel
- creates the user `kiosk` (no password, no sudo, no shell)
- sets up the systemd units and the watchdog
- adds a polkit rule so that `kiosk` may only power off and reboot
- disables Ctrl+Alt+Del, SysRq and extra VT logins, and hides the GRUB menu
- restricts SSH to key login only
- allows only SSH from the LAN through the firewall (ufw)
- enables automatic security updates with a reboot at 04:30

## 3. Deploy the app

On the dev machine, the Godot export templates must be installed once (Godot editor:
*Editor → Manage Export Templates*, or unpack the `.tpz` to
`~/.local/share/godot/export_templates/4.7.2.stable/`).

```bash
kiosk/deploy.sh ostadmin@<kiosk>     # tests, export, upload, switch, restart
```

Releases are kept in `/opt/ost/releases/` (the last 3), and `/opt/ost/current` points to the
active one. To roll back:
`sudo ln -sfn /opt/ost/releases/<older> /opt/ost/current && sudo systemctl restart ost-arcade`.

External apps (NBodyTouch) go to `/opt/ost/external/nbody/`; see `docs/external_apps.md`.

## 4. Manual hardening

- **GRUB password** (stops editing the kernel command line at boot):
  `grub-mkpasswd-pbkdf2`, then add the following to `/etc/grub.d/40_custom` and run `update-grub`:
  `set superusers="ostadmin"` and `password_pbkdf2 ostadmin <hash>`.
  Add `--unrestricted` to the normal boot entry so the kiosk still boots without a password
  (`sed -i 's/CLASS="--class gnu-linux/CLASS="--unrestricted --class gnu-linux/' /etc/grub.d/10_linux`).
- **Admin PIN in the app:** the default is `1234`. Change it in the admin menu: hold the
  top-left corner for 3 s, then tap the other corners clockwise.
- **Physical:** keep the mini PC out of reach (locked case or behind the display) and do not
  leave a keyboard attached.

## 5. Optional: read-only root

`overlayroot` makes every reboot return to a clean state: changes to `/` live only in RAM.
`/var/lib/ost` must be a separate partition so that scores and telemetry survive.

```bash
sudo apt install overlayroot
echo 'overlayroot="tmpfs:swap=1,recurse=0"' | sudo tee /etc/overlayroot.local.conf
sudo reboot
```

The trade-off is that automatic updates are lost on reboot. Update manually with
`sudo overlayroot-chroot`, then run `apt upgrade`. Only enable this once everything else works.

## 6. Acceptance checklist

- [ ] Cold boot goes straight to the hub, without a login prompt, in under 30 s
- [ ] Touch: the admin menu's touch test shows 10 simultaneous points
- [ ] Ctrl+Alt+F1…F12, Alt+Tab, Ctrl+Alt+Del and SysRq do nothing
- [ ] Pulling the power plug and plugging it in again boots back into the hub
- [ ] `sudo kill -STOP $(pgrep -f ost_astro_arcade)` makes the watchdog restart the app within ~90 s
- [ ] Admin menu: power off works as user `kiosk`
- [ ] FPS overlay: hub and games run at ≥ 55 fps at 2560×1440
