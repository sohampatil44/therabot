#!/bin/bash

set -xe
exec > >(tee /var/log/master_user_data.log | logger -t master_user_data -s 2>/dev/console) 2>&1

# -----------------------------
# 1. CREATE 4G SWAP
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
# 2. UPDATE SYSTEM
# -----------------------------
yum update -y

# -----------------------------
# 3. INSTALL TOOLS
# -----------------------------
yum install -y wget unzip jq amazon-ssm-agent python3 awscli
systemctl enable amazon-ssm-agent
systemctl start amazon-ssm-agent

# -----------------------------
# 4. INSTALL K3S MASTER
# -----------------------------
curl -sfL https://get.k3s.io | sh -s - server --write-kubeconfig-mode 644 --kubelet-arg=fail-swap-on=false

# Wait until k3s API server is ready
echo "Waiting for k3s API server to be ready..."
until kubectl get nodes --kubeconfig /etc/rancher/k3s/k3s.yaml >/dev/null 2>&1; do
    echo "API server not ready, sleeping 10s..."
    sleep 10
done
echo "✅ API server ready"

# -----------------------------
# 5. SAVE K3S TOKEN & KUBECONFIG
# -----------------------------
mkdir -p /var/lib/rancher/k3s/server
while [ ! -f /var/lib/rancher/k3s/server/node-token ]; do
    echo "Waiting for k3s node-token..."
    sleep 5
done
cp /var/lib/rancher/k3s/server/node-token /tmp/k3s_token

cp /etc/rancher/k3s/k3s.yaml /home/ec2-user/kubeconfig
chown ec2-user:ec2-user /home/ec2-user/kubeconfig

# Push kubeconfig to SSM
aws ssm put-parameter \
  --name "/therabot/kubeconfig" \
  --type "SecureString" \
  --value "$(cat /home/ec2-user/kubeconfig)" \
  --overwrite \
  --region "${AWS_REGION:-us-east-1}"

# Push k3s token to SSM
TOKEN=$(cat /tmp/k3s_token)
aws ssm put-parameter --name "/k3s/token" --value "$TOKEN" --type "SecureString" --region "${AWS_REGION:-us-east-1}"

# -----------------------------
# 6. SAVE MASTER PRIVATE IP
# -----------------------------
while true; do
    TOKEN_IMDS=$(curl -X PUT "http://169.254.169.254/latest/api/token" \
        -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
    
    MASTER_IP=$(curl -H "X-aws-ec2-metadata-token: $TOKEN_IMDS" \
        -s http://169.254.169.254/latest/meta-data/local-ipv4)

    if [[ -n "$MASTER_IP" ]]; then
        break
    fi
    echo "Waiting for instance metadata service"
    sleep 5
done             

aws ssm put-parameter \
    --name "/k3s/master/private_ip" \
    --value "$MASTER_IP" \
    --type "String" \
    --overwrite \
    --region "${AWS_REGION:-us-east-1}"

# -----------------------------
# 7. VERIFY WORKER NODES JOIN
# -----------------------------
echo "Waiting for worker nodes to join..."
until kubectl get nodes --kubeconfig /home/ec2-user/kubeconfig | grep -q 'Ready'; do
    echo "No Ready nodes yet, sleeping 10s..."
    sleep 10
done

kubectl get nodes --kubeconfig /home/ec2-user/kubeconfig
kubectl get pods -A --kubeconfig /home/ec2-user/kubeconfig
