# Backlog

Roughly ordered by value per unit of effort. Nothing here is committed to; it is
a list of what looks worth doing next and why.

---

## 1. Get other hardware revisions tested

The single biggest limitation: **everything is verified on one device, a v3.20
EU.** Until that changes, the project can only honestly claim to work there.

- [ ] Post the recruitment write-up (`docs/drafts/forum-post.md`) to the OpenWrt
      forum and XDA
- [ ] Add a **compatibility table** to the README, one row per revision, fed by
      probe reports. Even two rows changes how the project reads
- [ ] Have `probe.sh` emit a **paste-ready markdown block** so a reporter does
      not have to format anything
- [ ] Label triage: reports arrive as `compatibility`, get closed into the table

## 2. Make contributions safe to accept

Right now a PR could break the device and nothing would catch it.

- [ ] **CI on pull requests**: `shellcheck` over `device/**/*.sh` and `scripts/`,
      `node --check` over `sigmod.js`. Cheap, and would have caught real bugs
- [ ] **Headless mock render check**: boot `tools/mock`, assert the invariants
      that have actually regressed — no overlapping cards, PIN section hidden,
      no horizontal overflow, every stock row visible. This is the single
      highest-value test in the project, because all four have broken before
- [ ] A `scripts/selftest.sh` to run **on a device**: check each CGI responds,
      that mutating endpoints 403 without a password, and that the daemon's
      output file is fresh
- [ ] Enable **Discussions** for "does this work on X" chatter, keeping Issues
      for actionable things

## 3. Device features worth building

- [ ] **Verify the LTE watchdog backstop.** `bring_up_wwan` is armed but has
      never been observed firing. Needs a deliberate outage while someone is
      physically present, since a wrong operation code drops the data call
- [ ] **Band locking / preference.** The modem is on B3; Three also runs B1 and
      B20. Worth exposing if the AT command exists — probe first, and never
      `AT+COPS=?`
- [ ] **SD card support.** The slot is detected and reports `empty`; once a card
      is in, show capacity and mount state, and consider it as a home for logs
      given the rootfs is 87% full
- [ ] **Signal history beyond 4 hours**, written to SD rather than tmpfs so it
      survives a reboot
- [ ] **SMS in the mod UI.** The stock SMS tab exists but is untouched by the
      theme work
- [ ] **OLED custom text.** Documented as invasive: `oledd` owns the framebuffer
      and redraws continuously, so it needs displacing plus a font blitter.
      Needs someone physically watching the screen

## 3b. Data budgeting (for metered/roaming use)

Prompted by burning 20 GB in a few days. The device is a fine LTE backup at home
and a liability abroad, so it needs to be able to shut up and to say who is
talking.

**Where attribution has to live.** The M7350 sees a single aggregate flow from
the GL.iNet, so it can never tell you *which client* spent the data. Per-client
accounting belongs on the GL.iNet, which sees each device separately.

- [ ] **nlbwmon on the GL.iNet** for per-host, per-protocol accounting with a
      LuCI page. This is the actual answer to "who used what"
- [ ] **vnstat** alongside it for per-interface history, so a spike can be placed
      in time
- [ ] Document both in the README's travel section, since that is where someone
      will look

**A data-saver mode in the mod**, one toggle in Controls that stops the device
chattering:

- [ ] Stop the daemon's latency ping (currently ~every 7s to 1.1.1.1; tiny, but
      it is unsolicited traffic on a metered link and looks bad in a data audit)
- [ ] Have `metrics.sh` refuse while data-saver is on, so a home Prometheus
      scraping over Tailscale cannot pull from it
- [ ] Slow the poll cadence: signal every 30s rather than 5s, cell and SIM reads
      hourly rather than each minute
- [ ] Persist the setting like the TTL toggle, and re-apply at boot
- [ ] Show it plainly in the UI, because a silent data-saver is worse than none

**Make usage visible before it is a problem:**

- [ ] Surface the stock **Data Settings** monthly limit in the mod UI. The
      firmware already supports a cap and a warning threshold; it is buried
- [ ] Add data used today / this month to the dashboard, from the counters the
      Statistics card already reads
- [ ] A **usage sparkline** reusing the existing ring, so a 5 GB day is obvious
- [ ] Optional: alert when a threshold is crossed, via the existing metrics path

**Worth measuring rather than assuming:** before optimising anything, capture a
day of nlbwmon output. Telemetry is almost certainly noise next to one laptop
deciding to sync, and fixing the wrong thing costs effort and changes nothing.

## 4. Dashboard polish

- [ ] **Per-card visibility.** Hide cards you never look at, alongside reorder
      and resize
- [ ] **Multiple named layouts**, e.g. "travel" versus "at home"
- [ ] **Threshold colouring** on RSRP/RSRQ so bad values are obvious at a glance
- [ ] **Sparklines for throughput and latency**, reusing the existing ring
- [ ] Make the sparkline's fixed -120..-60 dBm scale **configurable**

## 5. Monitoring and integration

- [ ] Add **cell ID, band and ICCID as Prometheus labels** so Grafana can graph
      a handover or a profile switch
- [ ] A ready-made **Grafana dashboard JSON** in `docs/`
- [ ] **Alert rules** worth shipping: link down, RSRP degraded, telnet or FTP
      left on, rootfs nearly full

## 6. Housekeeping

- [ ] **Reduce rootfs usage.** 4.8 MB free on `/` is the tightest constraint on
      the device and will eventually bite
- [ ] **Uninstall path needs testing on a fresh device**, not just on one that
      has had every version installed over the top
- [ ] Document the **release process** in CONTRIBUTING, since it is currently
      only in the maintainer's head
- [ ] Consider **signing release bundles**, now that the repo is public

---

## Explicitly not doing

Recorded so they stop being re-proposed. All tested on v3.20:

- **eSIM profile management on-device.** `AT+CSIM`, `AT+CCHO` and `AT+CGLA` all
  return errors, so there is no APDU path to the ISD-R and no LPA can run.
  `AT+CRSM` works, which is why ICCID and SPN can still be read
- **OpenWRT.** *Not ruled out on principle, but nobody has ported it and it is a
  large job.* An earlier version of this file said secure boot prevented it; that
  was an inference from the `sbl`/`mba`/`tz` partitions, which every Qualcomm
  device has whether or not the fuses are blown, and it appears to be wrong.
  [m0veax/tplink_m7350](https://github.com/m0veax/tplink_m7350) reports fastboot
  is available (bootloader 0.5, an LK derivative) and that custom kernels can be
  booted. The real obstacles are that **MDM9625 has no mainline support** (its
  siblings MDM9615 and MDM9607 do), so it needs a device tree and clock, pinctrl
  and regulator bring-up written from scratch, and then the modem needs MSS
  remoteproc plus a data path to replace the proprietary QCMAP/qti stack. Months
  of specialist work, for a device whose LTE would be worse than stock afterwards.
  - [ ] **`fastboot getvar all`** to record what the bootloader actually reports
        about lock and secure-boot state, replacing guesswork with a fact.
        **Blocked: waiting for the SIM to go back in so the device is reachable.**
  - Work now tracked in a separate private repo, `louij2/m7350-openwrt`, so this
    project stays about the mod
- **SNMP.** `snmpd` is resident and wants more RAM than the device has free. The
  Prometheus endpoint covers the same ground for nothing
- **External antennas.** No connectors on the case, and at RSRP -82 with a flat
  19.3 Mbps the radio is not the limiting factor anyway
