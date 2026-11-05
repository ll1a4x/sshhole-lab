#!/usr/bin/env bash
# Tear down the *sshhole lab: stop/remove the container and delete the image.
#   ./cleanup.sh
set -u

for NAME in sshhole-lab; do
  if docker ps -a --format '{{.Names}}' | grep -qx "$NAME"; then
    echo "[*] Removing container: $NAME"
    docker rm -f "$NAME" >/dev/null 2>&1 || true
  fi
  if docker image inspect "$NAME" >/dev/null 2>&1; then
    echo "[*] Removing image:     $NAME"
    docker rmi -f "$NAME" >/dev/null 2>&1 || true
  fi
done

echo "[+] Done. Verify nothing is left:"
docker ps -a  --filter 'name=sshhole' --format '    container: {{.Names}}'
docker images --filter 'reference=sshhole*' --format '    image:     {{.Repository}}:{{.Tag}}'
echo "    (no lines above = fully cleaned)"
