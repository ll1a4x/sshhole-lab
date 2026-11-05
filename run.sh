#!/usr/bin/env bash
# Build + start the vulnerable lab, then print the precondition check.
# Run on the macOS host, from the folder holding Dockerfile and check.sh.
#   ./run.sh [port]
set -euo pipefail

IMAGE=sshhole-lab
NAME=sshhole-lab
PORT="${1:-2222}"

echo "[*] Building (compiles OpenSSH 9.6p1 from source — ~1-2 min)..."
docker build -t "$IMAGE" .

docker rm -f "$NAME" >/dev/null 2>&1 || true
docker run -d --name "$NAME" -p "${PORT}:22" "$IMAGE" >/dev/null
sleep 1

echo
docker exec "$NAME" /check.sh
echo
echo "[+] Lab up on localhost:${PORT}"
echo "    Target  : deploy  (shadow field '*', no password — should be unloginable)"
echo "    Control : alice   (password 'correcthorsebatterystaple')"
echo "    Exploit : ./exploit.sh ${PORT}"
echo "    Logs    : docker logs -f ${NAME}"
