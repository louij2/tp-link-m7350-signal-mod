# Changelog

All notable changes to the M7350 Extreme mod are documented here.

## [Unreleased]

### Fixed
- **The firmware's own status cards had stopped appearing.** They live inside
  `#statusContent`, which the firmware unhides with an *inline style* while
  leaving the `hide` class on it. A `.statusPage .hide{display:none!important}`
  rule, added to stop a SIM PIN panel appearing, outranked that inline style and
  suppressed the whole stock block. Removed; the PIN panel stays hidden anyway
  because the section styling already excludes `.hide`.
- The geometry overrides used `.statusPage > .connectionSection`, but those
  sections are grandchildren via `#statusContent`, so the child combinator never
  matched and the firmware's `float:left`, 49.5% widths and fixed heights all
  survived. Now descendant selectors.

### Added
- **Drag-and-drop card arrangement** on the Status tab. All seven cards, the
  firmware's three included, can be reordered by dragging. The stock sections are
  reparented (moved, never recreated) so everything shares one flow, keeping
  their nodes and ids so firmware updates still land.
- **The order is stored on the router**, not the browser, so the layout follows
  the device. `GET /cgi-bin/tiles.sh` is open since the page needs the order
  before authenticating and card names are not sensitive; `POST` requires the
  control password and validates the body against the known tile names, so
  nothing else can be written. A **Reset layout** button restores the default.
- **RSRP sparkline**: four hours of signal history in a tmpfs ring, drawn as
  inline SVG on a fixed -120..-60 dBm scale.
- **Serving cell**: Cell ID, derived eNodeB and TAC, via `AT+CEREG`.
- **SIM identity**: ICCID and Carrier (SPN) read from the card with `AT+CRSM`,
  which is what identifies the active profile on a removable eUICC.

### Documentation
- README: setting up Multi-WAN failover on a GL.iNet travel router, the GL-MT3000
  USB 3.0 / 2.4 GHz repeater interference bug, and how removable eUICC cards work
  with this device (profiles cannot be managed on it; `CSIM`/`CCHO`/`CGLA` all
  return errors).

## [2.3.1] — 2026-08-30  ·  **status page actually works on the device**

2.3.0 shipped a status page that was broken on real hardware. It had been
"verified" against a mock whose DOM was invented rather than observed, so none of
the following showed up until it was opened on the router.

### Fixed
- **The firmware's fixed geometry was never overridden.** `settings.css` pins
  `.statusPage` to `width:850px; height:500px; min-height:630px` and floats the
  sections at `49.5%` with `height:310px`, with `height:25px` rows and floated
  labels. `min-height:630px` is why a tall empty band appeared above the cards:
  the container holds its height whether or not its children are still in flow.
  Every one of those declarations is now undone explicitly.
- **A SIM PIN unlock panel appeared on the status page.** `display:grid!important`
  on `.pinSection` overrode the firmware's own `.hide` class. Section styling is
  scoped with `:not(.hide)`, and `.hide` is forced to `display:none` so a stock
  hide that works by clipping cannot be defeated either.
- **Cards overlapped each other.** `display:contents` dissolved `.popup` and
  `.help-popup`, which the stock stylesheet positions itself. The mod no longer
  restructures any firmware element; the dashboard layout applies only to
  containers the mod owns.
- **The SSH key list rendered one character wide.** A flex item defaults to
  `min-width:auto`, and `overflow-wrap:anywhere` then breaks at every character.
- **The page used only about two thirds of the window**, because the firmware
  constrains the wrappers around `.statusPage`. With that lifted, cards get real
  width and the long identifiers (IMEI, IMSI, MAC) stop breaking mid-token.

### Changed
- Status cards and the mod's own cards now pack in one masonry flow, so a short
  card no longer strands the space beneath it. Security and About Device are
  welded into a single unbreakable unit so they always stay stacked together.
- About Device is regrouped: what the device is, what network it is on, then the
  subscriber identifiers together, keeping the long values adjacent.
- `tools/mock` now carries the firmware's real geometry and hierarchy,
  transcribed from the device, including the hidden `pinSection` and both popups.
  Every fault above reproduces there. The previous mock modelled what the
  firmware was assumed to do rather than what it does, which is the only reason
  any of this reached a release.

## [2.3.0] — 2026-08-29  ·  **safe by default**

### Security
- **`control.sh` now fails closed.** State-changing actions (`*_on`, `*_off`,
  `reboot`, `setpw`) previously fell back to *unauthenticated* when
  `/etc/signalmod.pw` was absent, for backwards compatibility. That meant a fresh
  install handed root-level toggles — FTP and telnet serving the whole
  filesystem, ADB, reboot — to anyone on the network until the owner noticed and
  set a password. With no password file, every mutation is now refused with 503.
- **No unauthenticated bootstrap.** `setpw` is refused too when no password
  exists, so nobody on the LAN can claim an unclaimed device by setting the
  password first. Create the first password over ADB or SSH, which you
  necessarily have if you installed this at all:
  `printf '%s' 'yourpassword' > /etc/signalmod.pw && chmod 600 /etc/signalmod.pw`
- Status reads stay open, so the panel still polls without prompting.

This is the change that made the repository safe to publish.

## [2.2.0] — 2026-08-29  ·  **security + reliability release**

Everything here was verified against a real M7350 v3.20, not just built.

### Fixed
- **LTE signal readings had stopped working entirely.** RSRP, RSRQ, EARFCN and
  band were all empty. A modem AT channel can answer `AT` and `$QCSYSMODE`
  perfectly while rejecting `$QCRSRP?` — `/dev/smd7` on this device does exactly
  that, where smd8 and smd11 answer it. The daemon's health check asked only
  whether the channel responded *at all*, which it did, so it never re-selected
  and sat indefinitely on a channel that could not produce the one number the
  mod exists to show. It now judges the channel on the value it needs, skips the
  bad one, and falls back to trying every channel so a recovered one is not
  locked out for the life of the daemon.
- **A dead daemon looked alive.** `grep <name> /proc/*/cmdline` matches any shell
  whose own command line mentions the name, including the shell running the
  check. Self and parent PIDs are now excluded and the match is on the full path.
- **`deploy.sh` over SSH copied nothing and reported success.** dropbear ships no
  `sftp-server`, and scp has defaulted to the SFTP protocol since OpenSSH 9.0, so
  every copy failed; the exit status was never checked, and the cache-buster was
  rewritten regardless, leaving the page looking freshly deployed while running
  the old code. Now falls back through `scp -O` to a plain `cat >` stream, and
  compares sha256 for every file.
- Signal-strength bars rendered as invisible spacing: a broad
  `i{background-color:transparent!important}` reset beat the narrower
  non-important `.sigmod-bars i` rule.
- `metrics.sh` reported a flat 0.0 temperature and no battery: this SoC reports
  `thermal_zone0` in whole degrees rather than millidegrees, and the battery uci
  keys are `power_level`/`is_charging`.

### Security
- **Subscriber identifiers are no longer served unauthenticated.** `deviceinfo.sh`
  returned IMEI, IMSI and the SIM's phone number to anyone who could reach the
  device's web port — an IMSI identifies a subscriber, not just a handset. Those
  three fields are now gated on the same `X-Auth` password as `control.sh` and
  redacted otherwise, including when no password is configured (fail closed).
  Everything else in the About card stays open, and the withheld fields render as
  a click-to-unlock `locked` in the UI.
- **SSH key management fails closed.** The new `keys.sh` refuses every action
  unless a control password is set and presented, because installing a key grants
  permanent root SSH. Keys are validated strictly: `authorized_keys` options
  (`command=`, `from=`, `permitopen=`) are rejected outright, since they turn a
  key line into arbitrary root execution, and the last remaining key cannot be
  revoked so you cannot lock yourself out.
- Passwords and public keys are sent in the request body, never the query
  string, where the web server would log them.

### Changed
- **Status tab is a dashboard grid.** Stock sections and the mod's own cards pack
  as siblings in one masonry layout, so the page fits on a screen instead of
  scrolling, and short cards no longer leave dead space. Implemented purely in
  CSS via `display:contents` — no DOM is moved, so every stock row keeps its
  element, its id and its firmware updates.
- **`deploy.sh` works over SSH** when the device is not on USB, picking the
  transport automatically. `M7350_SSH_TARGET` accepts a `~/.ssh/config` alias.
- **LTE watchdog backstop is disarmed unless the device advertises it.**
  `qcmap_method_bring_up_wwan` was never verified, and a wrong operation code
  would drop the data call; the watchdog now probes `ubus -v list qcmap` first
  and otherwise runs autoconnect-only. Also self-tests `ping -W` support, backs
  off to 5 minutes between actions, and logs to `/tmp/lte_reconnect.log`.

### Added
- **`tools/mock/`** — a local render harness that runs the real `sigmod.js`
  against a mock of the stock page, so UI work needs no device. The `docs/`
  screenshots come from it, with synthetic data only.
- **`network_select.sh`** — reports and restores automatic network selection
  (`AT+COPS`). A manual COPS selection reads as "No service" at full signal.
- **`scripts/verify-lte-reconnect.sh`** — read-only probe of the modem's ubus
  methods and link state, to check the watchdog before arming it.
- **Security card** in the web UI: list, add and revoke SSH keys, and change the
  control password.
- **Host metrics**: temperature, memory, load, battery and per-service listeners,
  so an alert can fire when telnet or FTP is left enabled. `rx`/`tx` corrected
  from gauge to counter.
- **Login banner** at `/etc/profile.d/sigmod-banner.sh` showing live LTE, network,
  health and uptime. Guarded to interactive TTYs: a banner leaking into
  non-interactive output would corrupt `deploy.sh`'s digest verification.
- **`deploy.sh` deploys over SSH** when the device is not on USB, choosing the
  transport automatically. `M7350_SSH_TARGET` accepts a `~/.ssh/config` alias.
- The `post-merge` hook now calls `deploy.sh` and lets it pick a transport,
  instead of testing for ADB itself and skipping every merge once the device
  moved behind the GL.iNet.

### Fixed
- **Signal bars were invisible.** The generic `i{background-color:transparent
  !important}` glyph reset beat the non-important `.sigmod-bars i` rule — a
  non-important declaration loses to an important one whatever its specificity.

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
