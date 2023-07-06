#!/usr/bin/env bash

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 KEYPAIR_OUT_DIR"
    exit 1
fi
KEYPAIR_OUT_DIR="$1"

if [[ -e "$KEYPAIR_OUT_DIR" ]]; then
    echo "Error: KEYPAIR_OUT_DIR exists: $KEYPAIR_OUT_DIR"
    exit 1
fi

set -ex

mkdir "$KEYPAIR_OUT_DIR"
umask 077
wg genkey > "$KEYPAIR_OUT_DIR/private"
wg pubkey < "$KEYPAIR_OUT_DIR/private" > "$KEYPAIR_OUT_DIR/public"
