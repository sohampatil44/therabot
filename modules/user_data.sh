#!/bin/bash

# 1. Install Docker & Git
yum update -y
yum install -y docker git

# 2. Start and enable Docker
systemctl start docker
systemctl enable docker

# 3. Add ec2-user to docker group
usermod -aG docker ec2-user

# 4. Install Docker Compose plugin
runuser -l ec2-user -c '
  mkdir -p ~/.docker/cli-plugins
  curl -SL https://github.com/docker/compose/releases/download/v2.27.0/docker-compose-linux-x86_64 \
    -o ~/.docker/cli-plugins/docker-compose
  chmod +x ~/.docker/cli-plugins/docker-compose
  echo "export PATH=\$PATH:\$HOME/.docker/cli-plugins" >> ~/.bashrc
'

# 5. Clone repo as ec2-user
runuser -l ec2-user -c '
  cd ~
  git clone https://github.com/sohampatil44/ripensense.git
'

# 6. Run Docker Compose in a **login shell with updated group**
su - ec2-user -c '
  export PATH=$PATH:$HOME/.docker/cli-plugins
  cd ~/ripensense
  docker compose up --build -d
'
