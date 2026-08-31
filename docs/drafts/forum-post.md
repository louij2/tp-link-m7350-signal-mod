Title: M7350 web UI mod: live LTE stats, dark dashboard, SSH, Prometheus (v3.20 EU tested, need other revisions)

I've been modding the stock firmware on a TP-Link M7350 v3.20 (Qualcomm MDM9625)
rather than trying to replace it. It installs over root ADB, no reflash, and
scripts/uninstall.sh restores the stock pages from backups it takes on first run.

https://github.com/louij2/tp-link-m7350-signal-mod

What it adds to the web UI:

- RSRP, RSRQ, RSSI, EARFCN, band, serving cell ID, eNodeB and TAC
- 4 hours of signal history as an inline SVG sparkline
- CPU, load, RAM, swap, storage and SD-slot state
- ICCID and carrier name read off the SIM, which is how you tell which profile
  is live on a removable eUICC
- drag to reorder and drag the corner to resize every card, layout stored on the
  router rather than in the browser
- SSH (static dropbear, key only), TTL fix, Wi-Fi/FTP/Telnet toggles
- a Prometheus endpoint for Grafana
- dark theme across the whole UI, including the Advanced pages

Findings that might save someone else the time:

**AT channel capabilities are split, and not how you'd expect.** On mine
$QCRSRP? answers on /dev/smd8 and smd11 but returns ERROR on smd7, while +COPS
only answers on smd7. My poller originally health-checked "did the channel reply
at all", which was true, so it sat happily on a channel that could never produce
the one number the whole thing exists to display. Probe for the command you
actually need, not for liveness.

**No on-device eSIM management.** AT+CSIM, AT+CCHO and AT+CGLA all return errors,
so there is no APDU path to the ISD-R and no LPA can run on this hardware. But
AT+CRSM does work, which is enough to read EF_ICCID (2FE2) and EF_SPN (6F46), so
a removable eUICC can be provisioned elsewhere and the router will still tell you
which profile is enabled.

**Secure boot looks enforced and the LTE stack is proprietary.** Partitions
include sbl, mba (Modem Boot Authenticator), tz and a signed qdsp, and the data
path is QCMAP_ConnectionManager plus /usr/bin/qti over SMD. That is why I stopped
looking at OpenWRT for this box: even with something booting, you would lose the
modem.

**It is a very small machine.** 41 MB RAM with about 3 MB free and 1.4 MB already
in swap, one ARMv7 core at 38 BogoMIPS, rootfs 87% full. A speed test on the
device itself gives a flat 19.3 Mbps at RSRP -82, so on this hardware the aerial
is never the interesting variable.

**What I need: other hardware revisions.** I only have a v3.20 EU. There is a
read-only probe that reports your revision, firmware, web UI structure, which AT
commands each smd channel answers, and resources. It writes nothing and sends no
AT command that changes modem state (deliberately never AT+COPS=?, which is slow
and can wedge a channel):

    git clone https://github.com/louij2/tp-link-m7350-signal-mod
    cd tp-link-m7350-signal-mod && scripts/probe.sh

If you have a v1, v2, v4 or a non-EU v3, I would genuinely like to see that
output even if you never install the mod. Especially if your device answers
AT+CSIM, because that would mean it can manage eSIM profiles on-board and mine
cannot, which would be worth building for.
