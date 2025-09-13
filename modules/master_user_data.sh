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
# 5. GET MASTER IP (DO THIS EARLY)
# -----------------------------
echo "Getting master private IP..."
MASTER_IP=""
for i in {1..10}; do
    MASTER_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4 2>/dev/null || echo "")
    if [[ -n "$MASTER_IP" && "$MASTER_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "✅ Master IP: $MASTER_IP"
        break
    fi
    echo "Attempt $i: Waiting for valid master IP..."
    sleep 5
done

if [[ -z "$MASTER_IP" ]]; then
    echo "❌ Failed to get master private IP"
    exit 1
fi

# -----------------------------
# 6. SAVE K3S TOKEN & KUBECONFIG
# -----------------------------
mkdir -p /var/lib/rancher/k3s/server
while [ ! -f /var/lib/rancher/k3s/server/node-token ]; do
    echo "Waiting for k3s node-token..."
    sleep 5
done
cp /var/lib/rancher/k3s/server/node-token /tmp/k3s_token

# Copy and fix kubeconfig
cp /etc/rancher/k3s/k3s.yaml /home/ec2-user/kubeconfig
chown ec2-user:ec2-user /home/ec2-user/kubeconfig

# Replace localhost in kubeconfig with the master IP
sed -i "s|https://127.0.0.1:6443|https://$MASTER_IP:6443|g" /home/ec2-user/kubeconfig

# Verify the kubeconfig was updated correctly
echo "Verifying kubeconfig server endpoint:"
grep "server:" /home/ec2-user/kubeconfig

# Test the updated kubeconfig works
echo "Testing updated kubeconfig..."
if kubectl get nodes --kubeconfig /home/ec2-user/kubeconfig >/dev/null 2>&1; then
    echo "✅ Updated kubeconfig works correctly"
else
    echo "❌ Updated kubeconfig failed - falling back to original"
    cp /etc/rancher/k3s/k3s.yaml /home/ec2-user/kubeconfig
    chown ec2-user:ec2-user /home/ec2-user/kubeconfig
fi

# Push kubeconfig to SSM
echo "Pushing kubeconfig to SSM..."
aws ssm put-parameter \
  --name "/therabot/kubeconfig" \
  --type "SecureString" \
  --value "$(cat /home/ec2-user/kubeconfig)" \
  --overwrite \
  --region "${AWS_REGION:-us-east-1}"

if [ $? -eq 0 ]; then
    echo "✅ Kubeconfig successfully saved to SSM"
else
    echo "❌ Failed to save kubeconfig to SSM"
fi

# Push k3s token to SSM
echo "Pushing k3s token to SSM..."
TOKEN=$(cat /tmp/k3s_token)
aws ssm put-parameter \
  --name "/k3s/token" \
  --value "$TOKEN" \
  --type "SecureString" \
  --region "${AWS_REGION:-us-east-1}"

if [ $? -eq 0 ]; then
    echo "✅ K3s token successfully saved to SSM"
else
    echo "❌ Failed to save k3s token to SSM"
fi

# -----------------------------
# 7. SAVE MASTER PRIVATE IP TO SSM
# -----------------------------
echo "Pushing master IP to SSM..."
aws ssm put-parameter \
    --name "/k3s/master/private_ip" \
    --value "$MASTER_IP" \
    --type "String" \
    --overwrite \
    --region "${AWS_REGION:-us-east-1}"

if [ $? -eq 0 ]; then
    echo "✅ Master IP successfully saved to SSM"
else
    echo "❌ Failed to save master IP to SSM"
fi

# -----------------------------
# 8. VERIFY CLUSTER IS HEALTHY
# -----------------------------
echo "Verifying cluster health..."
kubectl get nodes --kubeconfig /home/ec2-user/kubeconfig
kubectl get pods -A --kubeconfig /home/ec2-user/kubeconfig

# -----------------------------
# 9. WAIT FOR WORKER NODES (OPTIONAL)
# -----------------------------
echo "Master node setup complete. Workers will join automatically."
echo "Current cluster status:"
kubectl get nodes --kubeconfig /home/ec2-user/kubeconfig

# 🎉 DONE
echo "🎉 Master node initialization completed successfully!"
kubectl get nodes --kubeconfig /home/ec2-user/kubeconfig
kubectl get pods -A --kubeconfig /home/ec2-user/kubeconfig
