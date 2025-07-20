#!/bin/bash

# Enable debug mode and log output
exec > /var/log/user-data.log 2>&1
set -x

# System prep
yum update -y
yum install -y docker git amazon-efs-utils

# Install Git LFS
curl -s https://packagecloud.io/install/repositories/github/git-lfs/script.rpm.sh | bash
yum install -y git-lfs

# Create 1GB swap file to avoid OOM issues
SWAP_FILE="/swapfile"
if [ ! -f $SWAP_FILE ]; then
  dd if=/dev/zero of=$SWAP_FILE bs=1M count=1024
  chmod 600 $SWAP_FILE
  mkswap $SWAP_FILE
  swapon $SWAP_FILE
  echo "$SWAP_FILE none swap sw 0 0" >> /etc/fstab
fi

# Mount EBS volume
DEVICE="/dev/xvdf"
MOUNT_POINT="/mnt/docker-storage"

while [ ! -b $DEVICE ]; do
  echo "Waiting for $DEVICE..."
  sleep 2
done

if ! mount | grep -q "$MOUNT_POINT"; then
  mkdir -p $MOUNT_POINT
  if ! blkid $DEVICE | grep -q ext4; then
    mkfs -t ext4 $DEVICE
  fi
  mount $DEVICE $MOUNT_POINT
  UUID=$(blkid -s UUID -o value $DEVICE)
  grep -q "$UUID" /etc/fstab || echo "UUID=$UUID $MOUNT_POINT ext4 defaults,nofail 0 2" >> /etc/fstab
fi

# Docker setup
mkdir -p $MOUNT_POINT/docker
mkdir -p /etc/docker
cat > /etc/docker/daemon.json <<EOL
{
  "data-root": "$MOUNT_POINT/docker"
}
EOL

systemctl daemon-reexec
systemctl enable docker
systemctl start docker

until docker info >/dev/null 2>&1; do
  echo "Waiting for Docker to start..."
  sleep 2
done

usermod -aG docker ec2-user

# Install Docker Compose plugin
sudo -u ec2-user bash <<'EOF'
set -x
mkdir -p ~/.docker/cli-plugins
curl -SL https://github.com/docker/compose/releases/download/v2.27.0/docker-compose-linux-x86_64 -o ~/.docker/cli-plugins/docker-compose
chmod +x ~/.docker/cli-plugins/docker-compose
EOF

# Clone and start the app
sudo -u ec2-user bash <<'EOF'
set -x
cd ~
git lfs install

if [ ! -d "ripensense" ]; then
  git clone https://github.com/sohampatil44/ripensense.git || {
    echo "Git clone failed"
    exit 1
  }
else
  echo "Repo already cloned"
fi

cd ripensense || exit 1

git lfs pull
export PATH=$PATH:$HOME/.docker/cli-plugins

docker compose pull || echo "Compose pull failed"
docker compose up -d || echo "Compose up failed"

docker ps -a > ~/container-status.log
docker compose logs --no-color > ~/docker-startup.log 2>&1
EOF
