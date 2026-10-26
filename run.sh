#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE='ghcr.io/userver-framework/ubuntu-22.04-userver@sha256:fca9c8ac7e97b4e2b042d822facbb152aec10a9d4e09c0862e44c50640f3f303'

mkdir -p "$ROOT/results"

docker run --rm --init \
    --platform linux/amd64 \
    --cpus=4 --cpuset-cpus=0-3 --memory=8g --memory-swap=8g \
    --user 0:0 \
    --env "HOST_UID=$(id -u)" --env "HOST_GID=$(id -g)" \
    --mount "type=bind,source=$ROOT,target=/repo,readonly" \
    --mount "type=bind,source=$ROOT/results,target=/results" \
    --workdir /work --entrypoint /bin/bash \
    "$IMAGE" /repo/measure.sh

echo "Готово: $ROOT/results"
