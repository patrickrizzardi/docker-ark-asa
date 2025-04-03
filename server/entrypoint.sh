#!/bin/bash
# This script serves as the container's entrypoint

# Load configuration from JSON file if it exists
if [ -f "/ark-server-config.json" ]; then
  echo "📝 Loading configuration from JSON file..."
  source "${MANAGER_DIR}/utils/configLoader.sh" "/ark-server-config.json"
fi

# Make sure WINEPREFIX directory exists and is writable
mkdir -p "${WINEPREFIX}" 2>/dev/null || true

# Set up a virtual display for Wine
echo "🖥️ Setting up virtual display..."
# Create X11 directory if needed
mkdir -p /tmp/.X11-unix 2>/dev/null || true

# Start Xvfb
Xvfb :99 -screen 0 1024x768x16 -ac &
XVFB_PID=$!
sleep 2

# Make sure X server started properly
if ! ps -p $XVFB_PID >/dev/null; then
  echo "❌ Failed to start X server, trying alternate approach..."
  Xvfb :99 -nolisten tcp -screen 0 1024x768x16 &
  XVFB_PID=$!
  sleep 2
fi

# Initialize Wine environment
echo "🍷 Testing Wine..."
wine64 --version || echo "Wine version check failed (continuing anyway)"

# Run a command if provided
if [ "$1" ]; then
  echo "🚀 Running command: $@"
  # Execute the command, inheriting environment variables from Dockerfile
  exec "$@"
  exit $?
fi

# Execute the init.sh script directly from its location
echo "🚀 Initializing ARK server..."
cd "${MANAGER_DIR}"
exec ./init.sh "$@"
