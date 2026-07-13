# System maintenance

Audit started 2026-07-12 after restoring the X220 from a long period of
inactivity.

## Baseline completed

- [x] Bring Arch fully up to date and reboot into the installed kernel.
- [x] Merge outstanding `.pacnew` files.
- [x] Rebuild and inspect the encrypted-Btrfs initramfs.
- [x] Confirm zero failed system services.
- [x] Confirm the Pacman database and packaged-file integrity are sound.
- [x] Confirm Snapper creates hourly snapshots of `/` and `/home`.
- [x] Confirm Btrfs reports no device I/O or corruption errors.
- [x] Review installed AUR packages against the current AUR metadata.

## Live maintenance

- [x] Install `dosfstools`, `smartmontools`, `pacman-contrib`, and `arch-audit`.
- [x] Remove the orphaned `ffmpeg4.4` package.
- [x] Run `arch-audit` and review its findings (no currently available fixes;
      `arch-audit -u` and `pacman -Qu` are empty).
- [x] Inspect the Samsung SSD's SMART data and run a self-test (passed; zero
      reported uncorrectable sectors and zero CRC errors).
- [x] Repair the unclean `/boot` FAT filesystem while it is unmounted (dirty
      flag cleared; clean read-only verification passed before remounting).
- [x] Run an initial Btrfs scrub and verify that it finds no errors (16.59 GiB
      scrubbed on 2026-07-12).
- [x] Enable the monthly `btrfs-scrub@-.timer`.
- [ ] Reinstall GRUB 2.14 to the BIOS/MBR target `/dev/sda`.
- [ ] Regenerate `grub.cfg` and remove its nonexistent fallback-image entry.
- [ ] Decide on an off-device Restic or Borg backup destination and configure it.

## Requires a reboot or manual intervention

- [ ] Update the ThinkPad X220 BIOS from 1.28 to Lenovo's final 1.46 release.
- [ ] Decide whether to expose SSD allocation patterns through LUKS, then enable
      discard passthrough and weekly `fstrim` if accepted.
- [ ] Optionally install `linux-lts` and test it as a recovery kernel.
- [ ] Optionally use `mitigations=auto,nosmt` for complete MDS mitigation.

## Configuration capture

- [ ] Adopt the intentional `/etc/pacman.conf` changes into `system/`.
- [ ] Adopt the three custom systemd-networkd profiles into `system/`.
- [ ] Adopt `/etc/udev/rules.d/70-pcspkr-beep.rules` into `system/`.
- [ ] Track native and foreign explicit-package manifests for rebuilding Arch.
