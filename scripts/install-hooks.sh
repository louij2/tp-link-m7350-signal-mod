#!/usr/bin/env bash
# Install a git post-merge hook so the device auto-updates whenever you merge or
# pull changes (e.g. after merging a PR on GitHub, then `git pull` on the Mac).
#
# NOTE: the M7350 is reachable only over its USB link to THIS Mac, so a GitHub
# Action can't deploy to it. This hook runs locally after a merge/pull and
# deploys over ADB. (If you later put the device behind the GL.iNet with a
# network path, a self-hosted runner could do the same on merge.)
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$HERE/.git/hooks/post-merge"
cat > "$HOOK" <<'EOF'
#!/usr/bin/env bash
# Auto-deploy the web-UI mod to the connected M7350 after a merge/pull.
root="$(git rev-parse --show-toplevel)"
if command -v adb >/dev/null 2>&1 && adb get-state >/dev/null 2>&1; then
  echo "[post-merge] deploying M7350 mod to device..."
  "$root/scripts/deploy.sh" || echo "[post-merge] deploy failed (non-fatal)"
else
  echo "[post-merge] no ADB device — skipping device deploy."
fi
EOF
chmod +x "$HOOK"
echo "Installed post-merge hook -> $HOOK"
echo "Now: edit in VS Code -> commit/merge -> git pull  => device redeploys automatically."
