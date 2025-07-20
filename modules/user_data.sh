#!/bin/bash

# Enable debug mode and redirect all output to a log file
exec > /var/log/user-data.log 2>&1
set -euxo pipefail

# --- System Prep ---
yum update -y
yum install -y docker git amazon-efs-utils

# Install Git LFS
curl -s https://packagecloud.io/install/repositories/github/git-lfs/script.rpm.sh | bash
yum install -y git-lfs

# --- Create 4GB Swap (prevents memory OOM issues) ---
SWAP_FILE="/swapfile"
if [ ! -f "$SWAP_FILE" ]; then
  dd if=/dev/zero of=$SWAP_FILE bs=1M count=4096
  chmod 600 $SWAP_FILE
  mkswap $SWAP_FILE
  swapon $SWAP_FILE
  echo "$SWAP_FILE none swap sw 0 0" >> /etc/fstab
fi

# --- Mount EBS Volume ---
DEVICE="/dev/xvdf"
MOUNT_POINT="/mnt/docker-storage"

# Wait until volume is attached
while [ ! -b "$DEVICE" ]; do
  echo "Waiting for EBS device $DEVICE..."
  sleep 2
done

# Mount only if not already mounted
if ! mount | grep -q "$MOUNT_POINT"; then
  mkdir -p $MOUNT_POINT
  if ! blkid $DEVICE | grep -q ext4; then
    mkfs.ext4 $DEVICE
  fi
  mount $DEVICE $MOUNT_POINT
  UUID=$(blkid -s UUID -o value $DEVICE)
  grep -q "$UUID" /etc/fstab || echo "UUID=$UUID $MOUNT_POINT ext4 defaults,nofail 0 2" >> /etc/fstab
fi

# --- Configure Docker to Use Mounted Volume ---
mkdir -p "$MOUNT_POINT/docker"
mkdir -p /etc/docker
cat > /etc/docker/daemon.json <<EOL
{
  "data-root": "$MOUNT_POINT/docker"
}
EOL

# Start Docker
systemctl daemon-reexec
systemctl enable docker
systemctl start docker

# Wait for Docker to be ready
until docker info >/dev/null 2>&1; do
  echo "Waiting for Docker to start..."
  sleep 2
done

# Add EC2 user to Docker group
usermod -aG docker ec2-user

# --- Install Docker Compose Plugin (v2) ---
sudo -u ec2-user bash <<'EOF'
set -euxo pipefail
mkdir -p ~/.docker/cli-plugins
curl -SL https://github.com/docker/compose/releases/download/v2.27.0/docker-compose-linux-x86_64 -o ~/.docker/cli-plugins/docker-compose
chmod +x ~/.docker/cli-plugins/docker-compose
EOF

# --- Clone Repo & Start the App ---
sudo -u ec2-user bash <<'EOF'
set -euxo pipefail
cd ~
git lfs install

# Clone only if not already present
if [ ! -d "ripensense" ]; then
  git clone https://github.com/sohampatil44/ripensense.git
else
  echo "Repo already exists, skipping clone."
fi

cd ripensense

# Pull LFS files (e.g. models/images)
git lfs pull

# Set Docker Compose path
export PATH="$HOME/.docker/cli-plugins:$PATH"

# Override config for low memory usage & resiliency
cat > docker-compose.override.yml <<EOL
services:
  backend:
    command: gunicorn --workers=1 --bind 0.0.0.0:8000 app:app
    deploy:
      resources:
        limits:
          memory: 512M
    restart: always
EOL

# Pull image and launch
docker compose pull || echo "Compose pull failed"
docker compose up -d || echo "Compose up failed"

# Log container info
docker ps -a > ~/container-status.log
docker compose logs --no-color > ~/docker-startup.log 2>&1
EOF

echo "✅ User-data script completed successfully."
