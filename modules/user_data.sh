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
sudo tee /etc/yum.repos.d/grafana.repo > /dev/null <<EOF
[grafana]
name=Grafana OSS
baseurl=https://rpm.grafana.com/oss/rpm
repo_gpgcheck=1
enabled=1
gpgcheck=1
gpgkey=https://rpm.grafana.com/gpg.key
sslverify=1
EOF

sudo yum install -y grafana

mkdir -p /etc/grafana/provisioning/datasources
mkdir -p /etc/grafana/provisioning/dashboards
mkdir -p /etc/grafana/provisioning/dashboards-json

sudo systemctl enable grafana-server
sudo systemctl start grafana-server

echo "Grafana installation and service started

echo "Script completed successfully!"