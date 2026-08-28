# Changelog

All notable changes to the M7350 Extreme mod are documented here.

## [2.1.0] — 2026-08-28  ·  **security release (recommended)**

Hardens the optional root-access features from 2.0.0. **Use this, not 2.0.0, for
anything beyond isolated testing.**

### Security
- **CGI auth**: state-changing control actions (`*_on`/`*_off`/`reboot`) now require
  a password (sent as the `X-Auth` header, checked against `/etc/signalmod.pw` —
  root-only, chmod 600, never in the repo). Status reads stay open. Backwards-
  compatible: with no password file, control behaves as in 2.0.0, so **set a
  password to activate the gate**.
- **Root web console fails closed**: `exec.sh` refuses unless a password is set
  and the correct `X-Auth` is sent. `console.html` prompts for it.

### Added
- **LTE auto-reconnect** watchdog (`lte_reconnect.sh`, opt-in via
  `touch /etc/signalmod_lte`) — keeps the data link up unattended, e.g. behind a
  GL.iNet. Verify the QCMAP ubus operation codes on-device before relying on it.
- Model shows **M7350+**; login header **M7350+ Extreme**; Wi-Fi AP on/off toggle;
  battery in the System panel; status-page card redesign.

## [2.0.0] — 2026-08-28  ·  **initial / testing only**

> ⚠️ **2.0.0 ships unauthenticated root tooling** (FTP/Telnet/web-console toggles
> with no auth). Only run it on an isolated, trusted setup you fully control.
> **Upgrade to 2.1.0** for the authenticated versions.

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
