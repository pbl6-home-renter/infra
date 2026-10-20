#!/usr/bin/env bash
set -euo pipefail

private_key="private.pem"
public_key="public.pem"

if [[ -e "$private_key" || -e "$public_key" ]]; then
  echo "Refusing to overwrite existing JWT key material." >&2
  exit 1
fi

openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out "$private_key"
openssl rsa -in "$private_key" -pubout -out "$public_key"
chmod 600 "$private_key" "$public_key"

echo "Generated $private_key and $public_key. Keep private.pem secret."
echo
echo "Paste these lines into env/identity.env:"
echo "JWT_PRIVATE_KEY=$(awk '{printf "%s\\n", $0}' "$private_key")"
echo "JWT_PUBLIC_KEY=$(awk '{printf "%s\\n", $0}' "$public_key")"
