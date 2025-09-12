#!/bin/bash

set -xe
exec > >(tee /var/log/worker_user_data.log | logger -t worker_user_data -s 2>/dev/console) 2>&1

yum update -y 

# -----------------------------
# 1. INSTALL TOOLS
# -----------------------------
yum install -y wget unzip jq amazon-ssm-agent python3 awscli
systemctl enable amazon-ssm-agent
systemctl start amazon-ssm-agent

# -----------------------------
# 2. CREATE 4G SWAP
# -----------------------------
SWAPFILE=/swapfile
SWAPSIZE=4G
fallocate -l $SWAPSIZE $SWAPFILE || dd if=/dev/zero of=$SWAPFILE bs=1M count=4096
chmod 600 $SWAPFILE
mkswap $SWAPFILE
swapon $SWAPFILE
echo "$SWAPFILE none swap sw 0 0" >> /etc/fstab

# -----------------------------
# 3. ALLOW SWAP FOR K3S AGENT
# -----------------------------
mkdir -p /etc/systemd/system/k3s-agent.service.d
cat <<EOF > /etc/systemd/system/k3s-agent.service.d/override.conf
[Service]
ExecStart=
ExecStart=/usr/local/bin/k3s agent --kubelet-arg=fail-swap-on=false
EOF
systemctl daemon-reload

# -----------------------------
# 4. FETCH TOKEN AND MASTER IP
# -----------------------------
TOKEN=$(aws ssm get-parameter --name "/k3s/token" --with-decryption --query "Parameter.Value" --output text --region "${AWS_REGION:-us-east-1}")

while true; do
    MASTER_IP=$(aws ssm get-parameter --name "/k3s/master/private_ip" --query "Parameter.Value" --output text --region "${AWS_REGION:-us-east-1}")
    if [[ -n "$MASTER_IP" ]]; then
        break
    fi
    echo "Waiting for master private IP in SSM..."
    sleep 5
done

# -----------------------------
# 5. WAIT UNTIL MASTER API IS READY
# -----------------------------
echo "Waiting for master API server to be ready..."
until curl -k https://${MASTER_IP}:6443/healthz >/dev/null 2>&1; do
    echo "Master API not ready, sleeping 10s..."
    sleep 10
done
echo "✅ Master API ready"

# -----------------------------
# 6. INSTALL K3S AGENT
# -----------------------------
curl -sfL https://get.k3s.io | K3S_URL="https://${MASTER_IP}:6443" K3S_TOKEN="$TOKEN" sh -

# -----------------------------
# 7. VERIFY NODE JOINED
# -----------------------------
until kubectl get nodes --kubeconfig /home/ec2-user/kubeconfig | grep -q 'Ready'; do
    echo "Waiting for this worker node to appear in cluster..."
    sleep 10
done

kubectl get nodes --kubeconfig /home/ec2-user/kubeconfig
