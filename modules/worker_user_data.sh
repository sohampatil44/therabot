#!/bin/bash

set -xe
exec > >(tee /var/log/worker_user_data.log | logger -t worker_user_data -s 2>/dev/console) 2>&1

# -----------------------------
# 1. UPDATE SYSTEM & INSTALL TOOLS
# -----------------------------
yum update -y
yum install -y wget unzip jq amazon-ssm-agent python3 awscli
systemctl enable amazon-ssm-agent
systemctl start amazon-ssm-agent

# -----------------------------
# 2. CREATE 4G SWAP (if not exists)
# -----------------------------
SWAPFILE=/swapfile
SWAPSIZE=4G
if ! swapon --show | grep -q "$SWAPFILE"; then
    fallocate -l $SWAPSIZE $SWAPFILE || dd if=/dev/zero of=$SWAPFILE bs=1M count=4096
    chmod 600 $SWAPFILE
    mkswap $SWAPFILE
    swapon $SWAPFILE
    echo "$SWAPFILE none swap sw 0 0" >> /etc/fstab
fi

# -----------------------------
# 3. FETCH TOKEN AND MASTER IP
# -----------------------------
TOKEN=$(aws ssm get-parameter --name "/k3s/token" --with-decryption --query "Parameter.Value" --output text --region "${AWS_REGION:-us-east-1}")

while true; do
    MASTER_IP=$(aws ssm get-parameter --name "/k3s/master/private_ip" --query "Parameter.Value" --output text --region "${AWS_REGION:-us-east-1}")
    if [[ -n "$MASTER_IP" ]]; then
        echo "✅ Got master IP: $MASTER_IP"
        break
    fi
    echo "Waiting for master private IP in SSM..."
    sleep 5
done

# -----------------------------
# 4. WAIT UNTIL MASTER API IS READY
# -----------------------------
echo "Waiting for master API server to be ready..."
until curl -sk https://${MASTER_IP}:6443/healthz >/dev/null 2>&1; do
    echo "Master API not ready, sleeping 10s..."
    sleep 10
done
echo "✅ Master API ready"

# -----------------------------
# 5. INSTALL K3S AGENT
# -----------------------------
curl -sfL https://get.k3s.io | K3S_URL="https://${MASTER_IP}:6443" K3S_TOKEN="$TOKEN" sh -s - agent --kubelet-arg=fail-swap-on=false

# -----------------------------
# 6. FETCH KUBECONFIG FROM SSM (for verification only)
# -----------------------------
aws ssm get-parameter \
  --name "/therabot/kubeconfig" \
  --with-decryption \
  --query "Parameter.Value" \
  --output text \
  --region "${AWS_REGION:-us-east-1}" > /home/ec2-user/kubeconfig

chown ec2-user:ec2-user /home/ec2-user/kubeconfig

# -----------------------------
# 7. VERIFY NODE JOINED CLUSTER
# -----------------------------
echo "Verifying worker node joined..."
for i in {1..30}; do
    if kubectl get nodes --kubeconfig /home/ec2-user/kubeconfig | grep -q "$(hostname)"; then
        echo "✅ Worker node $(hostname) successfully joined the cluster!"
        break
    fi
    echo "⏳ Waiting for this worker node to appear in cluster... ($i/30)"
    sleep 10
done

kubectl get nodes --kubeconfig /home/ec2-user/kubeconfig
