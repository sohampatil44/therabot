#!/bin/bash
exec > /var/log/user-data.log 2>&1

echo "Starting the user data script"

sudo yum update -y
sudo yum install -y docker git

DOCKER_COMPOSE_VERSION=2.24.6
mkdir -p /home/ec2-user/.docker/cli-plugins

echo "About to download docker compose..."
curl -SL "https://github.com/docker/compose/releases/download/v${DOCKER_COMPOSE_VERSION}/docker-compose-linux-x86_64" -o /home/ec2-user/.docker/cli-plugins/docker-compose

chmod +x /home/ec2-user/.docker/cli-plugins/docker-compose
chown -R ec2-user:ec2-user /home/ec2-user/.docker

sudo systemctl enable docker
sudo systemctl start docker
sudo usermod -aG docker ec2-user

chown -R ec2-user:ec2-user /home/ec2-user

echo "About to clone repository..."
sudo -u ec2-user git clone https://github.com/sohampatil44/therabot.git /home/ec2-user/therabot

cd /home/ec2-user/therabot

echo "About to start retry loop..."
echo "Current directory: $(pwd)"
echo "Files in directory: $(ls -la)"

# Simple version first - just try once
echo "Trying docker compose up..."
sudo -u ec2-user docker compose up -d

if [ $? -eq 0 ]; then
    echo "Docker compose started successfully on first try!"
else
    echo "Docker compose failed, would retry but skipping for debug"
fi

echo "Script completed successfully!"