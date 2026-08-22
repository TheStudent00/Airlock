#!/usr/bin/env bash
# Build both images. This is the ONLY phase with open network access:
# every toolchain gets baked in here so the runner never needs the
# internet for its own setup.
#
# Usage:  ./build.sh
set -euo pipefail
cd "$(dirname "$0")"

echo "=== building sandbox-runner image (this takes a while) ==="
podman build -t sandbox-runner:latest -f Containerfile .

echo "=== building sandbox-proxy image ==="
podman build -t sandbox-proxy:latest -f proxy/Containerfile.proxy .

echo
echo "done. images:"
podman images --filter reference='sandbox-*' \
    --format '  {{.Repository}}:{{.Tag}}  {{.Size}}'
echo
echo "next:  ./up.sh"
