# Security policy

## Reporting

Please report vulnerabilities privately through GitHub's **Report a
vulnerability** button on the Security tab, rather than opening a public issue.

## What this project is, in security terms

This mod adds **root-level tooling to a consumer router**, so it is worth being
explicit about the threat model.

- The device's web UI is reachable by **every client on the LAN**. Treat the LAN
  as the trust boundary. Nothing here should ever be exposed to the WAN.
- State-changing actions (`*_on`, `*_off`, `reboot`, `setpw`, SSH key management,
  layout) require a password checked against `/etc/signalmod.pw`, and **fail
  closed**: with no password file, they are refused rather than allowed.
- **Adding an SSH key grants permanent root.** `keys.sh` therefore refuses
  everything without the password, rejects `authorized_keys` options such as
  `command=`, and will not let you remove your last key.
- Subscriber identifiers (IMEI, IMSI, SIM number) are **not** served
  unauthenticated. They are redacted unless the caller presents the password.
- **FTP and Telnet serve the entire filesystem as root** on the LAN. They are off
  by default, gated behind the password, and should be turned off when not in use.
- The optional web console is a **root shell**. It is off by default and refuses
  to run unless a password is set.
- There is **no TLS**. Credentials cross the LAN in cleartext. Do not reuse a
  password you care about.

## Versions

Only the latest release is supported. Releases before **v2.3.0** fell back to
*unauthenticated* when no password file existed, and **v2.2.0 and earlier** served
IMEI, IMSI and SIM number to anyone on the LAN. Do not run them.
