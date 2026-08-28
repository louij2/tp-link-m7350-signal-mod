# Changelog

All notable changes to the M7350 Extreme mod are documented here.

## [2.0.0] — 2026-08-28

First tagged release. A web-UI + system mod for the TP-Link M7350 v3 (Qualcomm
MDM9625), installed over root ADB. Reversible; all files live on persistent NAND.

### Added
- **Live LTE signal** on the login page **and** the post-login Status tab:
  RSRP / RSRQ / RSSI, EARFCN, derived **LTE band**, colour-coded signal bar.
- **System panel**: download/upload throughput, latency, temperature, **battery**,
  uptime, WAN IP.
- **Controls panel**: Reboot, **ADB** on/off, **TTL-fix** (pin egress TTL 65 for
  SMARTY/Three tethering), **FTP**, **Telnet**, **Wi-Fi AP** on/off — all LAN-only.
- **About Device**: model, firmware, hardware, IMEI, IMSI, SIM number, MAC,
  operator (MCC/MNC), APN, network mode — read live from the device (no PII in
  the repo).
- **Modern dark theme** with inline-SVG icons; the stock status sections are
  restyled into cards to match. Original TP-LINK logo kept.
- **Rebranding**: device name "M7350 Extreme" in the UI, model "M7350+", firmware
  "Extreme 2.0.0". The **OLED** shows a custom name and rotates model ↔ operator.
- **SSH**: `scripts/build-ssh.sh` compiles a static dropbear from source and
  installs key-only root SSH (LAN-bound), with boot persistence.
- **Prometheus** metrics endpoint (`/cgi-bin/metrics.sh`) for Grafana.
- **Signal daemon** with AT-channel auto-failover (smd7 → smd8 → smd11).
- **Boot persistence** via a SysV init script; TTL-fix / FTP / OLED rotator /
  SSH re-applied at boot when enabled.
- **LAN re-addressing** support (services derive the LAN IP dynamically).
- **Dev workflow**: `scripts/deploy.sh` (auto cache-bust) + a `post-merge` git
  hook so edits auto-deploy to a connected device.
- Optional **web root console** (off by default; `scripts/enable-console.sh`).

### Security note
Several features (FTP, Telnet, the web console) expose **unauthenticated root
access on the LAN**. They are **off by default**, bound to the LAN interface
only (never the mobile WAN), and toggled explicitly. Treat this as hobbyist
tooling for a device **you own**; do not enable it on an untrusted network.
