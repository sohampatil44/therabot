#!/bin/bash

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

usermod -aG docker ec2-user

# Install Docker Compose
sudo -u ec2-user bash <<'EOF'
mkdir -p ~/.docker/cli-plugins
curl -SL https://github.com/docker/compose/releases/download/v2.27.0/docker-compose-linux-x86_64 -o ~/.docker/cli-plugins/docker-compose
chmod +x ~/.docker/cli-plugins/docker-compose
EOF

# Clone repo and run app
sudo -u ec2-user bash <<'EOF'
cd ~
git lfs install
git clone https://github.com/sohampatil44/ripensense.git
cd ripensense
git lfs pull

export PATH=$PATH:$HOME/.docker/cli-plugins

# Start app
docker compose pull
docker compose up -d

# Log container status
docker ps -a > ~/container-status.log
docker compose logs --no-color > ~/docker-startup.log 2>&1 &
EOF
