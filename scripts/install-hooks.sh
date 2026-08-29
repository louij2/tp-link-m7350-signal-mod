#!/usr/bin/env bash
# Install a git post-merge hook so the device auto-updates whenever you merge or
# pull changes (e.g. after merging a PR on GitHub, then `git pull` on the Mac).
#
# The hook simply calls deploy.sh and lets it choose its own transport: ADB when
# the router is on USB, otherwise SSH. It used to test for ADB itself and skip
# outright when there was none, which meant every merge silently skipped the
# deploy once the device moved behind the GL.iNet and became reachable only over
# the network.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$HERE/.git/hooks/post-merge"
cat > "$HOOK" <<'EOF'
#!/usr/bin/env bash
# Auto-deploy the web-UI mod to the M7350 after a merge/pull.
# deploy.sh picks the transport itself: ADB over USB, else SSH over the network.
# Never fail the merge over this -- an unreachable router is not a bad merge.
root="$(git rev-parse --show-toplevel)"
echo "[post-merge] deploying M7350 mod..."
if "$root/scripts/deploy.sh"; then
  :
else
  echo "[post-merge] device unreachable or deploy failed (non-fatal); run scripts/deploy.sh when it is back."
fi
EOF
chmod +x "$HOOK"
echo "Installed post-merge hook -> $HOOK"
echo "Now: edit in VS Code -> commit/merge -> git pull  => device redeploys automatically."
