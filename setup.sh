#!/bin/bash
# Stop script on first error
set -e 

# Verify Docker is installed and running
if ! docker info >/dev/null 2>&1; then
    echo "ERROR: Docker is not installed or the daemon is not running."
    echo "Please start Docker and try again."
    exit 1
fi

# Initialize and update git submodules
echo "Updating git submodules..."
git submodule update --init --recursive

# Ensure the build task script is executable locally
chmod +x build_scripts/docker_build_tasks.sh 

# Build the Docker image
echo "Building Docker image..."
docker build -t svc-env .

# Run the build tasks inside the container
echo "Running Docker container..."
docker run -v "$(pwd)":/DASH-SVC-Toolchain svc-env /DASH-SVC-Toolchain/build_scripts/docker_build_tasks.sh

echo "Setup of DASH-SVC environment complete!"