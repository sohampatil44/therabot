#!/bin/bash

exec > /var/log/user-data.log 2>&1

echo "Starting the user data script"

sudo yum update -y
sudo yum install -y docker git

DOCKER_COMPOSE_VERSION=2.24.6
mkdir -p /home/ec2-user/.docker/cli-plugins
curl -SL https://github.com/docker/compose/releases/download/v${DOCKER_COMPOSE_VERSION}/docker-compose-linux-x86_64 \
  -o /home/ec2-user/.docker/cli-plugins/docker-compose

chmod +x /home/ec2-user/.docker/cli-plugins/docker-compose
chown -R ec2-user:ec2-user /home/ec2-user/.docker

sudo systemctl enable docker
sudo systemctl start docker
sudo usermod -aG docker ec2-user

# Ensure ec2-user owns the home folder
chown -R ec2-user:ec2-user /home/ec2-user

# Clone repo as ec2-user
sudo -u ec2-user git clone https://github.com/sohampatil44/therabot.git /home/ec2-user/therabot

# Retry docker compose up as ec2-user
cd /home/ec2-user/therabot

RETRIES=5
COUNT=0
until sudo -u ec2-user /home/ec2-user/.docker/cli-plugins/docker-compose up -d; do
  echo "Docker compose failed, retrying in 15 seconds.."
  sleep 15
  COUNT=$((COUNT + 1))
  if [ "$COUNT" -ge "$RETRIES" ]; then
    echo "Docker compose failed after $RETRIES attempts, exiting."
    exit 1
  fi  
done
