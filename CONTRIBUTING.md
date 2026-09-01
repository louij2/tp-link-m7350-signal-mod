# Contributing

Thanks for looking. The most useful contribution right now is **a probe report
from a hardware revision that isn't v3.20 EU** — see below. It needs no
installation and takes a minute.

## The quickest way to help: a revision report

```bash
git clone https://github.com/louij2/tp-link-m7350-signal-mod
cd tp-link-m7350-signal-mod && scripts/probe.sh
```

It is read-only. It writes nothing to the device and sends no AT command that
changes modem state. Open a *Hardware revision report* issue and paste the
output. Even "it found nothing" is useful, because it tells us the web assets or
AT channels differ on your revision.

## Working on the UI without a device

You do not need an M7350 to work on the web UI:

```bash
tools/mock/serve.sh          # http://127.0.0.1:8777/status.html
```

This serves the **real** `device/WEBSERVER/www/sigmod.js` against a mock of the
stock page, with synthetic JSON standing in for the CGIs.

**The mock mirrors the firmware's real structure on purpose, including the parts
that are awkward.** `#statusContent` carries a `hide` class that the firmware
clears with an *inline style*; `.statusPage` is pinned to `width:850px;
height:500px; min-height:630px`; the sections are floated at 49.5% with fixed
heights and are **not** direct children of `.statusPage`. Every one of those has
caused a real bug. If you find yourself "tidying" `tools/mock/stock.css`, don't:
that file exists to fight you the way the device does.

What the mock cannot tell you: anything about the CGIs, the daemon, or the modem.
Those need hardware.

## Deploying to a device

```bash
scripts/deploy.sh            # ADB over USB, or SSH if the device is remote
```

It picks its transport automatically and **verifies every file by sha256 after
copying**, because an early version copied nothing and reported success.

## House rules for changes

- **Never read an smd channel from a CGI.** It blocks and takes lighttpd with it.
  Modem data comes from the `signal_poll.sh` daemon via its JSON cache.
- **State-changing CGI actions must stay password-gated and fail closed.** If
  `/etc/signalmod.pw` is absent, refuse; do not fall back to unauthenticated.
- **Don't force `display` on a class the firmware toggles.** It clears `hide`
  with an inline style, so an `!important` rule beats it and hides real content.
- **`!important` beats specificity.** A narrow rule without it loses to a broad
  rule with it. This has silently broken two features so far.
- **Judge a daemon by its output, not by a PID.** `grep name /proc/*/cmdline`
  matches the shell running the check.
- **A loop iteration is ~7s, not the 5s of its `sleep`.** Wait two minutes before
  concluding a slow-cadence feature is broken.
- Keep it working on a box with **41 MB of RAM, ~3 MB free, one ARMv7 core and a
  rootfs 87% full**. Nothing resident unless it earns its place. Put new files in
  `/usr`, not `/`.

## Branches and releases

Work on `dev`, PR into `main`. `main` is what release tags are cut from. Every
release gets a CHANGELOG entry, a tag, and a bundle from
`scripts/make-release.sh`.

## Commit messages

Say what broke and why, not just what changed. The commit log is the best
documentation this project has, and several entries have already saved a repeat
of the same bug.
