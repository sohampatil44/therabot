#!/bin/bash

# Update system and install dependencies
yum update -y
yum install -y docker git

# Install Git LFS
curl -s https://packagecloud.io/install/repositories/github/git-lfs/script.rpm.sh | bash
yum install -y git-lfs

# Start and enable Docker
systemctl start docker
systemctl enable docker

# Add ec2-user to docker group
usermod -aG docker ec2-user

# Install Docker Compose
runuser -l ec2-user -c '
  mkdir -p ~/.docker/cli-plugins
  curl -SL https://github.com/docker/compose/releases/download/v2.27.0/docker-compose-linux-x86_64 \
    -o ~/.docker/cli-plugins/docker-compose
  chmod +x ~/.docker/cli-plugins/docker-compose
'

# Clone and setup repo
runuser -l ec2-user -c '
  cd ~
  git lfs install
  git clone https://github.com/sohampatil44/ripensense.git
  cd ripensense
  git lfs pull
'

# Create start_app.sh
cat > /home/ec2-user/start_app.sh << 'EOF'
#!/bin/bash
export PATH=$PATH:$HOME/.docker/cli-plugins
cd ~/ripensense
docker compose down
docker builder prune -a
docker compose up --build -d
EOF

chown ec2-user:ec2-user /home/ec2-user/start_app.sh
chmod +x /home/ec2-user/start_app.sh

echo "Setup complete!"
echo "To start the application, run: sudo -u ec2-user /home/ec2-user/start_app.sh"