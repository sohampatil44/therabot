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

echo "Updating packages..."
sudo yum update -y

if [ $? -ne 0 ]; then
    echo "Package update failed, but continuing..."
fi

echo "Installing packages..."
sudo yum install -y git  python3 python3-pip jq curl

echo "Installing Docker (Amazon Linux 2023)..."
sudo dnf install -y docker
sudo systemctl enable docker
sudo systemctl start docker
sudo groupadd docker || true

sudo usermod -aG docker ec2-user


which docker
docker --version






# Verify git installation
echo "Verifying git installation..."
if command -v git >/dev/null 2>&1; then
    echo "Git installed successfully: $(git --version)"
else
    echo "Git installation failed. Trying alternative installation..."
    sudo yum install -y git-core
    
    # Check again
    if command -v git >/dev/null 2>&1; then
        echo "Git installed successfully with git-core: $(git --version)"
    else
        echo "Git installation failed completely. Exiting..."
        exit 1
    fi
fi



# Wait for Docker daemon to be ready
echo "Waiting for Docker daemon to be ready..."
for i in {1..30}; do
    if sudo docker info >/dev/null 2>&1; then
        echo "Docker daemon is ready."
        break
    else
        echo "Waiting for Docker daemon... ($i/30)"
        sleep 2
    fi
done

# Add ec2-user to docker group
if getent group docker; then
    echo "Docker group exists."
else
    echo "Creating docker group manually..."
    sudo groupadd docker
fi
sudo usermod -aG docker ec2-user

# ----------------------
# Docker Compose Installation
# ----------------------

DOCKER_COMPOSE_VERSION=2.24.6
echo "Installing Docker Compose..."

# Create directories
sudo mkdir -p /home/ec2-user/.docker/cli-plugins
sudo mkdir -p /usr/local/lib/docker/cli-plugins

# Download Docker Compose
echo "Downloading Docker Compose v${DOCKER_COMPOSE_VERSION}..."
curl -SL "https://github.com/docker/compose/releases/download/v${DOCKER_COMPOSE_VERSION}/docker-compose-linux-x86_64" -o /tmp/docker-compose

if [ $? -eq 0 ]; then
    echo "Docker Compose downloaded successfully."
else
    echo "Failed to download Docker Compose. Exiting..."
    exit 1
fi

# Install Docker Compose
sudo cp /tmp/docker-compose /home/ec2-user/.docker/cli-plugins/docker-compose
sudo cp /tmp/docker-compose /usr/local/lib/docker/cli-plugins/docker-compose
sudo chmod +x /home/ec2-user/.docker/cli-plugins/docker-compose
sudo chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

# Fix ownership
sudo chown -R ec2-user:ec2-user /home/ec2-user/.docker

# Verify Docker Compose installation
echo "Verifying Docker Compose installation..."
if sudo docker compose version; then
    echo "Docker Compose installed successfully."
else
    echo "Docker Compose installation failed."
fi

#checkig for git

echo "checking git installation.."
which git
command -v git 
git --version 2>/dev/null || echo "git is not installed as version not found"
echo "PATH: $PATH"
echo "installed packages with "git" in name:"
yum list installed | grep git
echo "-----------------------"



# ----------------------
# Clone the Repository
# ----------------------

echo "Cloning repository..."
sudo rm -rf /home/ec2-user/therabot

# Clone as ec2-user with proper error handling
sudo -u ec2-user git clone https://github.com/sohampatil44/therabot.git /home/ec2-user/therabot

if [ $? -eq 0 ]; then
    echo "Repository cloned successfully."
else
    echo "Failed to clone repository. Check if the repository exists and is accessible."
    exit 1
fi

# Wait for successful clone and verify
echo "Verifying repository clone..."
for i in {1..10}; do
    if [ -d /home/ec2-user/therabot ] && [ -f /home/ec2-user/therabot/compose.yaml ]; then
        echo "Repository successfully cloned and verified."
        break
    else
        echo "Waiting for repository clone to complete... ($i/10)"
        sleep 2
    fi
done

if [ ! -d /home/ec2-user/therabot ]; then
    echo "Repository clone failed or directory not found."
    exit 1
fi

# ----------------------
# Copy Grafana provisioning files
# ----------------------

echo "Setting up Grafana provisioning files..."
sudo mkdir -p /etc/grafana/provisioning/datasources
sudo mkdir -p /etc/grafana/provisioning/dashboards
sudo mkdir -p /etc/grafana/provisioning/dashboards-json

# Copy files if they exist
if [ -f /home/ec2-user/therabot/scripts/grafana/provisioning/datasources/cloudwatch-datasource.yaml ]; then
    sudo cp /home/ec2-user/therabot/scripts/grafana/provisioning/datasources/cloudwatch-datasource.yaml /etc/grafana/provisioning/datasources/
fi

if [ -f /home/ec2-user/therabot/scripts/grafana/provisioning/dashboards/dashboards.yaml ]; then
    sudo cp /home/ec2-user/therabot/scripts/grafana/provisioning/dashboards/dashboards.yaml /etc/grafana/provisioning/dashboards/
fi

if [ -d /home/ec2-user/therabot/scripts/grafana/provisioning/dashboards-json/ ]; then
    sudo cp /home/ec2-user/therabot/scripts/grafana/provisioning/dashboards-json/*.json /etc/grafana/provisioning/dashboards-json/ 2>/dev/null || echo "No JSON files found to copy"
fi

cd /home/ec2-user/therabot

# ----------------------
# CloudWatch Agent
# ----------------------

echo "Installing CloudWatch Agent..."
sudo yum install -y amazon-cloudwatch-agent

if [ -f /home/ec2-user/therabot/scripts/cloudwatch-agent-config.json ]; then
    echo "Starting CloudWatch Agent..."
    sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
      -a fetch-config \
      -m ec2 \
      -c file:/home/ec2-user/therabot/scripts/cloudwatch-agent-config.json \
      -s

    echo "Enabling and starting CloudWatch Agent service..."
    sudo systemctl enable amazon-cloudwatch-agent
    sudo systemctl start amazon-cloudwatch-agent
else
    echo "CloudWatch agent config file not found, skipping agent configuration."
fi

sudo systemctl status amazon-cloudwatch-agent >> /var/log/cloudwatch-agent-status.log

# ----------------------
# Docker Compose Up
# ----------------------

echo "Starting Docker Compose..."

# Ensure we're in the right directory and docker-compose.yml exists
if [ ! -f compose.yaml ]; then
    echo "compose.yaml not found in $(pwd)"
    ls -la
    exit 1
fi

# Fix permissions
sudo chown -R ec2-user:ec2-user /home/ec2-user/therabot

echo "Waiting before starting app..."
sleep 60


# Start services with proper user
echo "Running Docker Compose as ec2-user..."
sudo -u ec2-user docker compose up -d

if [ $? -eq 0 ]; then
    echo "Docker compose started successfully!"
    sudo -u ec2-user docker compose ps
else
    echo "Docker compose failed!"
    sudo -u ec2-user docker compose logs
    exit 1
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
sudo mkdir -p /etc/grafana/provisioning/datasources
sudo mkdir -p /etc/grafana/provisioning/dashboards
sudo mkdir -p /etc/grafana/provisioning/dashboards-json

# Copy files with error checking
if [ -f /home/ec2-user/therabot/scripts/grafana/provisioning/dashboards/dashboards.yaml ]; then
    sudo cp /home/ec2-user/therabot/scripts/grafana/provisioning/dashboards/dashboards.yaml /etc/grafana/provisioning/dashboards/
fi

if [ -f /home/ec2-user/therabot/scripts/grafana/provisioning/dashboards-json/ec2-dashboard.json ]; then
    sudo cp /home/ec2-user/therabot/scripts/grafana/provisioning/dashboards-json/ec2-dashboard.json /etc/grafana/provisioning/dashboards-json/
fi

if [ -f /home/ec2-user/therabot/scripts/grafana/provisioning/datasources/cloudwatch-datasource.yaml ]; then
    sudo cp /home/ec2-user/therabot/scripts/grafana/provisioning/datasources/cloudwatch-datasource.yaml /etc/grafana/provisioning/datasources/
fi

sudo systemctl enable grafana-server
sudo systemctl start grafana-server

echo "Grafana installation and service started"

# ----------------------
# Create Grafana dashboard automatically
# ----------------------

echo "Waiting for Grafana to start..."
sleep 30

if [ -f /home/ec2-user/therabot/scripts/grafana/auto_dashboard.py ]; then
    python3 /home/ec2-user/therabot/scripts/grafana/auto_dashboard.py
else
    echo "auto_dashboard.py not found, skipping dashboard creation."
fi

echo "User data script completed successfully!"