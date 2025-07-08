#!/bin/bash

# 1. Update system and install required packages
yum update -y
yum install -y docker git

# 2. Start and enable Docker
systemctl start docker
systemctl enable docker

# 3. Add ec2-user to docker group (to avoid using sudo every time)
usermod -aG docker ec2-user

# 4. Install Docker Compose v2 (latest stable as of now)
DOCKER_CONFIG=${DOCKER_CONFIG:-$HOME/.docker}
mkdir -p $DOCKER_CONFIG/cli-plugins
curl -SL https://github.com/docker/compose/releases/download/v2.27.0/docker-compose-linux-x86_64 -o $DOCKER_CONFIG/cli-plugins/docker-compose
chmod +x $DOCKER_CONFIG/cli-plugins/docker-compose

# 5. Verify docker compose is working
docker compose version

# 6. Clone your project repo
git clone https://github.com/sohampatil44/ripensense.git
cd ripensense 

# 7. Build and run using Compose
docker compose up --build -d
