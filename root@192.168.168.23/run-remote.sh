#!/bin/bash

# run-remote.sh - Script điều phối: đẩy + chạy trên máy đích

set -euo pipefail

HOST_SCRIPT="$1"
TARGET_HOST="$2"
REMOTE_DIR="/tmp/pvn-scripts"

if [[ -z "$HOST_SCRIPT" || -z "$TARGET_HOST" ]]; then
  echo "Usage: $0 <host-script> <target-host>"
  exit 1
fi

echo "Deploying $HOST_SCRIPT to $TARGET_HOST..."
scp "$HOST_SCRIPT" "$TARGET_HOST:$REMOTE_DIR/"
ssh "$TARGET_HOST" "bash $REMOTE_DIR/$(basename "$HOST_SCRIPT")"
