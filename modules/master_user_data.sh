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

# Set explicit region
export AWS_REGION=us-east-1
export AWS_DEFAULT_REGION=us-east-1

# -----------------------------
# 4. GET MASTER IP
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

# Also fetch public IPv4 (if present) and use it for kubeconfig server endpoint so GitHub runners can connect
MASTER_PUBLIC_IP=""
# Try IMDSv2 public-ipv4
if [[ -n "$TOKEN" ]]; then
    MASTER_PUBLIC_IP=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "")
fi
# fallback to IMDSv1
if [[ -z "$MASTER_PUBLIC_IP" ]]; then
    MASTER_PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "")
fi

if [[ -n "$MASTER_PUBLIC_IP" && "$MASTER_PUBLIC_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "✅ Found MASTER_PUBLIC_IP: $MASTER_PUBLIC_IP"
else
    echo "ℹ️ MASTER_PUBLIC_IP not found, will use private IP in kubeconfig (if only private exists)"
    MASTER_PUBLIC_IP=""
fi

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

# Copy kubeconfig to home
cp /etc/rancher/k3s/k3s.yaml /home/ec2-user/kubeconfig
chown ec2-user:ec2-user /home/ec2-user/kubeconfig

# Replace localhost in kubeconfig with the PUBLIC IP if available, otherwise private IP
if [[ -n "$MASTER_PUBLIC_IP" ]]; then
    echo "Updating kubeconfig server endpoint from localhost to public IP $MASTER_PUBLIC_IP..."
    sed -i "s|https://127.0.0.1:6443|https://$MASTER_PUBLIC_IP:6443|g" /home/ec2-user/kubeconfig
else
    echo "No public IP; using private IP $MASTER_IP in kubeconfig..."
    sed -i "s|https://127.0.0.1:6443|https://$MASTER_IP:6443|g" /home/ec2-user/kubeconfig
fi

# Verify the kubeconfig was updated correctly
echo "Verifying kubeconfig server endpoint:"
grep "server:" /home/ec2-user/kubeconfig || true

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

# -----------------------------
# 7. SAVE TO SSM - FIXED VERSION
# -----------------------------
echo "🔍 Testing SSM access..."
aws sts get-caller-identity || echo "No AWS identity"

# Test basic SSM access
if aws ssm describe-parameters --max-items 1 >/dev/null 2>&1; then
    echo "✅ SSM access confirmed"
else
    echo "❌ SSM access failed"
    exit 1
fi

echo "💾 Saving kubeconfig to SSM as String (not SecureString)..."
retry_ssm=0
max_ssm_retries=3
while [ $retry_ssm -lt $max_ssm_retries ]; do
    # CHANGED: Using String instead of SecureString to avoid KMS issues
    if aws ssm put-parameter \
      --name "/therabot/kubeconfig" \
      --type "String" \
      --value "$(cat /home/ec2-user/kubeconfig)" \
      --overwrite \
      --region us-east-1; then
        echo "✅ Kubeconfig saved to SSM as String"
        
        # Verify it was saved
        sleep 2
        if aws ssm get-parameter --name "/therabot/kubeconfig" --region us-east-1 >/dev/null 2>&1; then
            echo "✅ Kubeconfig verified in SSM"
        else
            echo "⚠️  Saved but can't retrieve"
        fi
        break
    else
        retry_ssm=$((retry_ssm + 1))
        echo "❌ SSM save failed, attempt $retry_ssm/$max_ssm_retries. Retrying in 10s..."
        sleep 10
    fi
done

if [ $retry_ssm -eq $max_ssm_retries ]; then
    echo "❌ Failed to save kubeconfig to SSM after $max_ssm_retries attempts"
    
    # Debug: Show what we're trying to save
    echo "🔍 Kubeconfig size: $(wc -c < /home/ec2-user/kubeconfig) bytes"
    echo "🔍 Kubeconfig preview:"
    head -10 /home/ec2-user/kubeconfig
    
    # Try saving a simple test parameter
    echo "🧪 Testing simple parameter save..."
    if aws ssm put-parameter --name "/test/debug" --value "test123" --type "String" --overwrite --region us-east-1; then
        echo "✅ Simple parameter works - issue is with kubeconfig content"
    else
        echo "❌ Even simple parameter fails - IAM/SSM permissions issue"
    fi
    exit 1
fi

# Save k3s token (also as String)
echo "💾 Saving k3s token to SSM..."
TOKEN=$(cat /tmp/k3s_token)
aws ssm put-parameter \
  --name "/k3s/token" \
  --value "$TOKEN" \
  --type "String" \
  --overwrite \
  --region us-east-1 && echo "✅ Token saved" || echo "⚠️  Token save failed"

# Save master IP
echo "💾 Saving master IP to SSM..."
aws ssm put-parameter \
    --name "/k3s/master/private_ip" \
    --value "$MASTER_IP" \
    --type "String" \
    --overwrite \
    --region us-east-1 && echo "✅ Master IP saved" || echo "⚠️  Master IP save failed"

# Final verification
echo "📋 Final SSM verification:"
aws ssm get-parameters --names "/therabot/kubeconfig" "/k3s/token" "/k3s/master/private_ip" --region us-east-1 --query "Parameters[*].[Name,LastModifiedDate]" --output table || echo "Failed to verify parameters"

# -----------------------------
# 8. VERIFY CLUSTER IS HEALTHY
# -----------------------------
echo "Verifying cluster health..."
kubectl get nodes --kubeconfig /home/ec2-user/kubeconfig
kubectl get pods -A --kubeconfig /home/ec2-user/kubeconfig

# -----------------------------
# 9. FINAL STATUS
# -----------------------------
echo "Master node setup complete. Workers will join automatically."
echo "Current cluster status:"
kubectl get nodes --kubeconfig /home/ec2-user/kubeconfig

# 🎉 DONE
echo "🎉 Master node initialization completed successfully!"
echo "Master IP: $MASTER_IP"
if [[ -n "$MASTER_PUBLIC_IP" ]]; then
  echo "Kubeconfig server: https://$MASTER_PUBLIC_IP:6443"
else
  echo "Kubeconfig server: https://$MASTER_IP:6443"
fi
kubectl get nodes --kubeconfig /home/ec2-user/kubeconfig
kubectl get pods -A --kubeconfig /home/ec2-user/kubeconfig
