#!/bin/bash

# Enable debug mode for logging
exec > /var/log/user-data.log 2>&1
set -x

# Update system
yum update -y
yum install -y docker git amazon-efs-utils

# Install Git LFS
curl -s https://packagecloud.io/install/repositories/github/git-lfs/script.rpm.sh | bash
yum install -y git-lfs

DEVICE="/dev/xvdf"
MOUNT_POINT="/mnt/docker-storage"

# Wait for volume to attach
while [ ! -b $DEVICE ]; do
  echo "Waiting for $DEVICE..."
  sleep 2
done

# Mount the device
if ! mount | grep -q "$MOUNT_POINT"; then
  mkdir -p $MOUNT_POINT
  if ! blkid $DEVICE | grep -q ext4; then
    mkfs -t ext4 $DEVICE
  fi
  mount $DEVICE $MOUNT_POINT
  UUID=$(blkid -s UUID -o value $DEVICE)
  grep -q "$UUID" /etc/fstab || echo "UUID=$UUID $MOUNT_POINT ext4 defaults,nofail 0 2" >> /etc/fstab
fi

# Configure Docker to use mounted storage
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

# Wait for Docker to become ready
until docker info >/dev/null 2>&1; do
  echo "Waiting for Docker to start..."
  sleep 2
done

# Add ec2-user to docker group
usermod -aG docker ec2-user

# Install Docker Compose for ec2-user
sudo -u ec2-user bash <<'EOF'
set -x
mkdir -p ~/.docker/cli-plugins
curl -SL https://github.com/docker/compose/releases/download/v2.27.0/docker-compose-linux-x86_64 -o ~/.docker/cli-plugins/docker-compose
chmod +x ~/.docker/cli-plugins/docker-compose
EOF

# Clone repo and run app
sudo -u ec2-user bash <<'EOF'
set -x
cd ~
git lfs install

# Clone repo only if not exists
if [ ! -d "ripensense" ]; then
  git clone https://github.com/sohampatil44/ripensense.git || {
    echo "Git clone failed"
    exit 1
  }
else
  echo "Repo already cloned"
fi

cd ripensense || { echo "Failed to cd into ripensense"; exit 1; }

# Pull LFS files
git lfs pull

# Update PATH
export PATH=$PATH:$HOME/.docker/cli-plugins

# Start Docker Compose
docker compose pull || echo "Docker compose pull failed"
docker compose up -d || echo "Docker compose up failed"

# Log container status
docker ps -a > ~/container-status.log
docker compose logs --no-color > ~/docker-startup.log 2>&1
EOF
