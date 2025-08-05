#!/bin/bash

exec > >(tee /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1

echo "Starting the user data script"

# ----------------------
# MAXIMUM SWAP CREATION
# ----------------------

echo "Checking existing swap space..."
if free | awk '/^Swap:/ {exit !$2}'; then
    echo "Swap already exists. Skipping creation."
else
    echo "Creating 4G swap file..."
    sudo fallocate -l 4G /swapfile || sudo dd if=/dev/zero of=/swapfile bs=1M count=4096
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile
    sudo swapon /swapfile
    echo '/swapfile swap swap defaults 0 0' | sudo tee -a /etc/fstab
    echo "vm.swappiness=20" | sudo tee -a /etc/sysctl.conf
    echo "Swap successfully created and enabled."
fi

# ----------------------
# Package Installations
# ----------------------

sudo yum update -y
sudo yum install -y git docker python3 python3-pip jq curl

# ----------------------
# Docker Compose Installation
# ----------------------

DOCKER_COMPOSE_VERSION=2.24.6
mkdir -p /home/ec2-user/.docker/cli-plugins

echo "Downloading Docker Compose..."
curl -SL "https://github.com/docker/compose/releases/download/v${DOCKER_COMPOSE_VERSION}/docker-compose-linux-x86_64" -o /home/ec2-user/.docker/cli-plugins/docker-compose

chmod +x /home/ec2-user/.docker/cli-plugins/docker-compose
chown -R ec2-user:ec2-user /home/ec2-user/.docker

sudo mkdir -p /usr/local/lib/docker/cli-plugins
sudo cp /home/ec2-user/.docker/cli-plugins/docker-compose /usr/local/lib/docker/cli-plugins/
sudo chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

sudo systemctl enable docker
sudo systemctl start docker
sudo usermod -aG docker ec2-user

chown -R ec2-user:ec2-user /home/ec2-user

# ----------------------
# Clone the Repository
# ----------------------

echo "Cloning repository..."
rm -rf /home/ec2-user/therabot
sudo -u ec2-user git clone https://github.com/sohampatil44/therabot.git /home/ec2-user/therabot

# Wait for successful clone
while [ ! -d /home/ec2-user/therabot ]; do
  sleep 2
done  

# ----------------------
# Copy Grafana provisioning files
# ----------------------

sudo mkdir -p /etc/grafana/provisioning/datasources
sudo mkdir -p /etc/grafana/provisioning/dashboards
sudo mkdir -p /etc/grafana/provisioning/dashboards-json

sudo cp /home/ec2-user/therabot/scripts/grafana/provisioning/datasources/cloudwatch-datasource.yaml /etc/grafana/provisioning/datasources/
sudo cp /home/ec2-user/therabot/scripts/grafana/provisioning/dashboards/dashboards.yaml /etc/grafana/provisioning/dashboards/
sudo cp /home/ec2-user/therabot/scripts/grafana/provisioning/dashboards-json/*.json /etc/grafana/provisioning/dashboards-json/

cd /home/ec2-user/therabot

# ----------------------
# CloudWatch Agent
# ----------------------

echo "Installing CloudWatch Agent..."
sudo yum install -y amazon-cloudwatch-agent

echo "Starting CloudWatch Agent..."
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config \
  -m ec2 \
  -c file:/home/ec2-user/therabot/scripts/cloudwatch-agent-config.json \
  -s

# ----------------------
# Wait for Docker to be available
# ----------------------

echo "Waiting for Docker to become available..."
for i in {1..10}; do
    if command -v docker >/dev/null 2>&1; then
        echo "Docker is now available."
        break
    else
        echo "Docker not found, retrying in 5 seconds..."
        sleep 5
    fi
done

# ----------------------
# Docker Compose Up
# ----------------------

echo "Starting Docker Compose..."
sudo docker compose up -d

if [ $? -eq 0 ]; then
    echo "Docker compose started successfully!"
else
    echo "Docker compose failed!"
fi

# ----------------------
# Install Grafana
# ----------------------

echo "Installing Grafana..."
sudo tee /etc/yum.repos.d/grafana.repo <<EOF
[grafana]
name=Grafana OSS
baseurl=https://packages.grafana.com/oss/rpm
repo_gpgcheck=1
enabled=1
gpgcheck=1
gpgkey=https://packages.grafana.com/gpg.key
EOF

sudo yum install -y grafana

# Copy provisioning files again (to be safe)
mkdir -p /etc/grafana/provisioning/datasources
mkdir -p /etc/grafana/provisioning/dashboards
mkdir -p /etc/grafana/provisioning/dashboards-json

cp /home/ec2-user/therabot/scripts/grafana/provisioning/dashboards/dashboards.yaml /etc/grafana/provisioning/dashboards/
cp /home/ec2-user/therabot/scripts/grafana/provisioning/dashboards-json/ec2-dashboard.json /etc/grafana/provisioning/dashboards-json/
cp /home/ec2-user/therabot/scripts/grafana/provisioning/datasources/cloudwatch-datasource.yaml /etc/grafana/provisioning/datasources/

sudo systemctl enable grafana-server
sudo systemctl start grafana-server

echo "Grafana installation and service started"

# ----------------------
# Create Grafana dashboard automatically
# ----------------------

sleep 30
python3 /home/ec2-user/therabot/scripts/grafana/auto_dashboard.py

echo "User data script completed successfully!"
