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
# 4. GET MASTER IP (MOVE THIS EARLY WITH ROBUST METHOD)
# -----------------------------
echo "Getting master private IP with multiple methods..."
MASTER_IP=""

# Method 1: Try IMDSv2 (token-based) - Most secure and reliable
echo "Trying IMDSv2..."
TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" --connect-timeout 10 --max-time 30 2>/dev/null || echo "")
if [[ -n "$TOKEN" ]]; then
    MASTER_IP=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" "http://169.254.169.254/latest/meta-data/local-ipv4" --connect-timeout 10 --max-time 30 2>/dev/null || echo "")
fi

# Method 2: Try IMDSv1 (if IMDSv2 fails)
if [[ -z "$MASTER_IP" || ! "$MASTER_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "IMDSv2 failed, trying IMDSv1..."
    MASTER_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4 --connect-timeout 10 --max-time 30 2>/dev/null || echo "")
fi

# Method 3: Use hostname -I as backup
if [[ -z "$MASTER_IP" || ! "$MASTER_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "IMDS failed, using hostname -I..."
    MASTER_IP=$(hostname -I | awk '{print $1}' 2>/dev/null || echo "")
fi

# Method 4: Use ip route as last resort
if [[ -z "$MASTER_IP" || ! "$MASTER_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "hostname -I failed, using ip route..."
    MASTER_IP=$(ip route get 8.8.8.8 2>/dev/null | grep -oP 'src \K[0-9.]+' | head -1 || echo "")
fi

# Method 5: Use network interface directly
if [[ -z "$MASTER_IP" || ! "$MASTER_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "ip route failed, checking network interfaces..."
    MASTER_IP=$(ip addr show $(ip route | awk '/default/ {print $5; exit}') 2>/dev/null | grep 'inet ' | awk '{print $2}' | cut -d'/' -f1 | head -1 || echo "")
fi

# Wait and retry with exponential backoff if all methods fail
retry_count=0
max_retries=5
while [[ -z "$MASTER_IP" || ! "$MASTER_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && [[ $retry_count -lt $max_retries ]]; do
    retry_count=$((retry_count + 1))
    wait_time=$((retry_count * 10))
    echo "Attempt $retry_count/$max_retries failed. Waiting ${wait_time}s before retry..."
    sleep $wait_time
    
    # Try IMDSv2 again with longer timeout
    TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" --connect-timeout 15 --max-time 45 2>/dev/null || echo "")
    if [[ -n "$TOKEN" ]]; then
        MASTER_IP=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" "http://169.254.169.254/latest/meta-data/local-ipv4" --connect-timeout 15 --max-time 45 2>/dev/null || echo "")
    fi
done

# Final validation
if [[ -z "$MASTER_IP" || ! "$MASTER_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "❌ CRITICAL: Failed to get valid master private IP after all attempts"
    echo "Debug information:"
    echo "- Network interfaces:"
    ip addr show 2>/dev/null || echo "ip addr failed"
    echo "- Default route:"
    ip route 2>/dev/null || echo "ip route failed"
    echo "- Hostname methods:"
    hostname -I 2>/dev/null || echo "hostname -I failed"
    hostname -i 2>/dev/null || echo "hostname -i failed"
    echo "- DNS resolution:"
    nslookup $(hostname) 2>/dev/null || echo "nslookup failed"
    exit 1
fi

echo "✅ Successfully obtained master IP: $MASTER_IP"

# -----------------------------
# 5. INSTALL K3S MASTER
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
echo "Updating kubeconfig server endpoint from localhost to $MASTER_IP..."
sed -i "s|https://127.0.0.1:6443|https://$MASTER_IP:6443|g" /home/ec2-user/kubeconfig

# Verify the kubeconfig was updated correctly
echo "Verifying kubeconfig server endpoint:"
grep "server:" /home/ec2-user/kubeconfig

# Test the updated kubeconfig works
echo "Testing updated kubeconfig..."
max_attempts=10
attempt=0
while [ $attempt -lt $max_attempts ]; do
    if kubectl get nodes --kubeconfig /home/ec2-user/kubeconfig >/dev/null 2>&1; then
        echo "✅ Updated kubeconfig works correctly"
        break
    else
        attempt=$((attempt + 1))
        echo "Kubeconfig test failed, attempt $attempt/$max_attempts. Retrying in 10s..."
        sleep 10
    fi
done

if [ $attempt -eq $max_attempts ]; then
    echo "❌ Updated kubeconfig failed after $max_attempts attempts - falling back to original"
    cp /etc/rancher/k3s/k3s.yaml /home/ec2-user/kubeconfig
    chown ec2-user:ec2-user /home/ec2-user/kubeconfig
fi

# Push kubeconfig to SSM with retry logic
echo "Pushing kubeconfig to SSM..."
retry_ssm=0
max_ssm_retries=5
while [ $retry_ssm -lt $max_ssm_retries ]; do
    if aws ssm put-parameter \
      --name "/therabot/kubeconfig" \
      --type "SecureString" \
      --value "$(cat /home/ec2-user/kubeconfig)" \
      --overwrite \
      --region "${AWS_REGION:-us-east-1}"; then
        echo "✅ Kubeconfig successfully saved to SSM"
        break
    else
        retry_ssm=$((retry_ssm + 1))
        echo "❌ SSM push failed, attempt $retry_ssm/$max_ssm_retries. Retrying in 15s..."
        sleep 15
    fi
done

if [ $retry_ssm -eq $max_ssm_retries ]; then
    echo "❌ Failed to save kubeconfig to SSM after $max_ssm_retries attempts"
fi

# Push k3s token to SSM with retry logic
echo "Pushing k3s token to SSM..."
TOKEN=$(cat /tmp/k3s_token)
retry_token=0
while [ $retry_token -lt $max_ssm_retries ]; do
    if aws ssm put-parameter \
      --name "/k3s/token" \
      --value "$TOKEN" \
      --type "SecureString" \
      --overwrite \
      --region "${AWS_REGION:-us-east-1}"; then
        echo "✅ K3s token successfully saved to SSM"
        break
    else
        retry_token=$((retry_token + 1))
        echo "❌ Token SSM push failed, attempt $retry_token/$max_ssm_retries. Retrying in 15s..."
        sleep 15
    fi
done

# -----------------------------
# 7. SAVE MASTER PRIVATE IP TO SSM
# -----------------------------
echo "Pushing master IP to SSM..."
retry_ip=0
while [ $retry_ip -lt $max_ssm_retries ]; do
    if aws ssm put-parameter \
        --name "/k3s/master/private_ip" \
        --value "$MASTER_IP" \
        --type "String" \
        --overwrite \
        --region "${AWS_REGION:-us-east-1}"; then
        echo "✅ Master IP successfully saved to SSM"
        break
    else
        retry_ip=$((retry_ip + 1))
        echo "❌ Master IP SSM push failed, attempt $retry_ip/$max_ssm_retries. Retrying in 15s..."
        sleep 15
    fi
done

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
echo "Master IP: $MASTER_IP"
echo "Kubeconfig server: https://$MASTER_IP:6443"
kubectl get nodes --kubeconfig /home/ec2-user/kubeconfig
kubectl get pods -A --kubeconfig /home/ec2-user/kubeconfig