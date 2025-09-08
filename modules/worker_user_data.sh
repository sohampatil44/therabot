#!/bin/bash

set -xe
exec > >(tee /var/log/worker_user_data.log | logger -t worker_user_data -s 2>/dev/console) 2>&1

yum update -y 

#Install dependencies
yum install -y wget unzip jq amazon-ssm-agent
yum install -y python3 awscli

#enable and start ssm agent
systemctl enable amazon-ssm-agent
systemctl start amazon-ssm-agent

# -----------------------------
# 1. CREATE 4G SWAP
# -----------------------------
SWAPFILE=/swapfile
SWAPSIZE=4G
fallocate -l $SWAPSIZE $SWAPFILE || dd if=/dev/zero of=$SWAPFILE bs=1M count=4096
chmod 600 $SWAPFILE
mkswap $SWAPFILE
swapon $SWAPFILE
echo "$SWAPFILE none swap sw 0 0" >> /etc/fstab


# -----------------------------
# ALLOW SWAP IN K3S AGENT
# -----------------------------
mkdir -p /etc/systemd/system/k3s-agent.service.d
cat <<EOF > /etc/systemd/system/k3s-agent.service.d/override.conf
[Service]
ExecStart=
ExecStart=/usr/local/bin/k3s agent --kubelet-arg=fail-swap-on=false
EOF

systemctl daemon-reload
systemctl restart k3s-agent


#fetch token from ssm
TOKEN=$(aws ssm get-parameter --name "/k3s/token" --with-decryption --query "Parameter.Value" --output text --region "${AWS_REGION:-us-east-1}")

# Fetch master private IP
while true; do
    MASTER_IP=$(aws ssm get-parameter --name "/k3s/master/private_ip" --query "Parameter.Value" --output text --region "${AWS_REGION:-us-east-1}")
    if [[ -n "$MASTER_IP" ]]; then
        break
    fi
    echo "Waiting for master private IP in SSM..."
    sleep 5
done

#install k3s agent (worker node)
curl -sfL https://get.k3s.io | K3S_URL="https://${MASTER_IP}:6443" K3S_TOKEN="$TOKEN" sh -


