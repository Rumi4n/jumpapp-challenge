#!/bin/sh
set -e

echo "==> Starting Jumpapp Email Sorter..."
echo "==> Checking environment variables..."

# Check critical environment variables
if [ -z "$DATABASE_URL" ]; then
  echo "ERROR: DATABASE_URL is not set!"
  exit 1
fi

if [ -z "$SECRET_KEY_BASE" ]; then
  echo "ERROR: SECRET_KEY_BASE is not set!"
  exit 1
fi

if [ -z "$PHX_HOST" ]; then
  echo "ERROR: PHX_HOST is not set!"
  exit 1
fi

echo "==> Environment variables OK"
echo "==> PHX_HOST: $PHX_HOST"
echo "==> PORT: ${PORT:-4000}"
echo "==> Database URL: ${DATABASE_URL:0:20}..." # Show only first 20 chars

echo "==> Checking if server binary exists..."
if [ ! -f /app/bin/server ]; then
  echo "ERROR: /app/bin/server not found!"
  ls -la /app/bin/
  exit 1
fi

echo "==> Server binary found"
echo "==> Starting application..."

# Execute the server
exec /app/bin/server

