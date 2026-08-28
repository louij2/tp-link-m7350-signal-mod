# Local render harness (no device needed)

Renders the **real** `device/WEBSERVER/www/sigmod.js` against a mock of the stock
M7350 status page, so the layout can be checked and iterated on without the
router — useful because the device is only reachable over USB-ADB or a flaky
LTE-backed Tailscale path.

```bash
tools/mock/serve.sh          # http://127.0.0.1:8777/status.html
```

* `status.html` / `login.html` — a faithful copy of the stock DOM *structure*
  (`.statusPage`, `.connectionSection`, `.content-group`/`.content-label`, the
  tab strip, `#loginStatus`) that the mod's CSS has to work with.
* `stock.css` — an approximation of the stock light theme, so the dark override
  is visibly doing its job.
* `cgi-bin/*.sh` — static JSON fixtures standing in for the real CGIs. Values are
  **synthetic**: the IMEI/IMSI/MAC/phone number here are dummies, which is why
  the screenshots in `docs/` carry no real identifiers.

Caveats — what the harness can **not** tell you:

* it does not prove anything about the CGIs, the AT daemon, or the device;
* the stock DOM here is reconstructed from the selectors the mod targets, not
  pulled from the firmware, so nesting may differ. The CSS is written to survive
  that (see the `display:contents` notes in `sigmod.js`), but a real-device
  screenshot is still the final word;
* the real firmware page's `viewport` meta is unknown — the mock sets one so
  phone widths can be exercised at all.
