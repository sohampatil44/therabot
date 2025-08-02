#!/bin/bash
exec > /var/log/user-data.log 2>&1

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
sudo yum install -y docker git

DOCKER_COMPOSE_VERSION=2.24.6
mkdir -p /home/ec2-user/.docker/cli-plugins

echo "About to download docker compose..."
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

echo "About to clone repository..."
sudo -u ec2-user git clone https://github.com/sohampatil44/therabot.git /home/ec2-user/therabot

cd /home/ec2-user/therabot

echo "Installing CloudWatch Agent.."
sudo yum install -y amazon-cloudwatch-agent

echo "Starting Cloudwatch agent with config.."
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config \
  -m ec2 \
  -c file:/home/ec2-user/therabot/scripts/cloudwatch-agent-config.json \
  -s

echo "Sleeping for 5 seconds to ensure Docker is ready..."
sleep 5

echo "Trying docker compose up as root..."
docker compose up -d

if [ $? -eq 0 ]; then
    echo "Docker compose started successfully!"
else
    echo "Docker compose failed!"
fi

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

mkdir -p /etc/grafana/provisioning/datasources
mkdir -p /etc/grafana/provisioning/dashboards
mkdir -p /etc/grafana/provisioning/dashboards-json

echo "Copying Grafana provisioning files..."
cp /home/ec2-user/therabot/scripts/grafana/provisioning/dashboards/dashboards.yaml /etc/grafana/provisioning/dashboards/
cp /home/ec2-user/therabot/scripts/grafana/provisioning/dashboards-json/ec2-dashboard.json /etc/grafana/provisioning/dashboards-json/
cp /home/ec2-user/therabot/scripts/grafana/provisioning/cloudwatch-datasource.yaml /etc/grafana/provisioning/datasources/

sudo systemctl enable grafana-server
sudo systemctl start grafana-server

echo "Grafana installation and service started"

echo "Script completed successfully!"
