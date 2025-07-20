#!/bin/bash

# Update and install packages
yum update -y
yum install -y docker git amazon-efs-utils

# Install Git LFS
curl -s https://packagecloud.io/install/repositories/github/git-lfs/script.rpm.sh | bash
yum install -y git-lfs

# Variables
DEVICE="/dev/xvdf"
MOUNT_POINT="/mnt/docker-storage"
REPO_DIR="/root/ripensense"  # Since you're SSH-ing as root

# Wait for volume to attach
while [ ! -b $DEVICE ]; do
  echo "Waiting for $DEVICE..."
  sleep 2
done

# Mount the volume
if ! mount | grep -q "$MOUNT_POINT"; then
  mkdir -p $MOUNT_POINT
  if ! blkid $DEVICE | grep -q ext4; then
    mkfs -t ext4 $DEVICE
  fi
  mount $DEVICE $MOUNT_POINT
  UUID=$(blkid -s UUID -o value $DEVICE)
  grep -q "$UUID" /etc/fstab || echo "UUID=$UUID $MOUNT_POINT ext4 defaults,nofail 0 2" >> /etc/fstab
fi

# Configure Docker to use new storage
mkdir -p $MOUNT_POINT/docker
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

# Wait for Docker to start
until docker info >/dev/null 2>&1; do
  echo "Waiting for Docker to start..."
  sleep 2
done

# Install Docker Compose globally
mkdir -p /usr/libexec/docker/cli-plugins
curl -SL https://github.com/docker/compose/releases/download/v2.27.0/docker-compose-linux-x86_64 -o /usr/libexec/docker/cli-plugins/docker-compose
chmod +x /usr/libexec/docker/cli-plugins/docker-compose
ln -sf /usr/libexec/docker/cli-plugins/docker-compose /usr/local/bin/docker-compose

# Clone repo and start app as root
cd /root
git lfs install
git clone https://github.com/sohampatil44/ripensense.git
cd ripensense
git lfs pull

# Start app
docker compose pull
docker compose up -d

# Log output
docker ps -a > /root/container-status.log
docker compose logs --no-color > /root/docker-startup.log 2>&1
