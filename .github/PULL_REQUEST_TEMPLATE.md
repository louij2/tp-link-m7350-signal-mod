## What this changes

<!-- and why. If it fixes a bug, say what the bug actually was. -->

## How it was verified

<!-- Be specific. "Looks fine" has let several bugs through on this project. -->

- [ ] Tested on a device (state the revision, e.g. v3.20 EU)
- [ ] Checked in `tools/mock/serve.sh`
- [ ] Not testable without hardware I don't have (say which part)

## Checklist

- [ ] No CGI reads an smd channel (it blocks and kills lighttpd)
- [ ] Any new state-changing endpoint is password-gated and **fails closed**
- [ ] No `display` forced on a class the firmware toggles
- [ ] Nothing new left resident (the device has ~3 MB RAM free)
- [ ] New files go in `/usr`, not `/` (rootfs is 87% full)
- [ ] CHANGELOG updated if user-visible
