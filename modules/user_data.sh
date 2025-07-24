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

echo "Sleeping for 5 seconds to ensure Docker is ready..."
sleep 5

echo "Trying docker compose up as root..."
docker compose up -d

if [ $? -eq 0 ]; then
    echo "Docker compose started successfully!"
else
    echo "Docker compose failed!"
fi

echo "Script completed successfully!"