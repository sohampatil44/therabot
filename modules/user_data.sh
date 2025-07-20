#!/bin/bash

# Enable debug mode and redirect all output to a log file
exec > /var/log/user-data.log 2>&1
set -euxo pipefail

echo "🚀 Starting optimized deployment script..."

# --- System Prep ---
yum update -y
yum install -y docker git amazon-efs-utils htop

# Install Git LFS
curl -s https://packagecloud.io/install/repositories/github/git-lfs/script.rpm.sh | bash
yum install -y git-lfs

# --- Create 8GB Swap (CRITICAL for memory management) ---
SWAP_FILE="/swapfile"
if [ ! -f "$SWAP_FILE" ]; then
  echo "Creating 8GB swap file..."
  dd if=/dev/zero of=$SWAP_FILE bs=1M count=8192
  chmod 600 $SWAP_FILE
  mkswap $SWAP_FILE
  swapon $SWAP_FILE
  echo "$SWAP_FILE none swap sw 0 0" >> /etc/fstab
  
  # Optimize swap usage for low memory systems
  echo 'vm.swappiness=10' >> /etc/sysctl.conf
  echo 'vm.vfs_cache_pressure=50' >> /etc/sysctl.conf
  echo 'vm.dirty_ratio=15' >> /etc/sysctl.conf
  echo 'vm.dirty_background_ratio=5' >> /etc/sysctl.conf
  sysctl -p
  
  echo "✅ Swap configured successfully"
fi

# --- Mount EBS Volume ---
DEVICE="/dev/xvdf"
MOUNT_POINT="/mnt/docker-storage"

# Wait until volume is attached
while [ ! -b "$DEVICE" ]; do
  echo "Waiting for EBS device $DEVICE..."
  sleep 2
done

# Mount only if not already mounted
if ! mount | grep -q "$MOUNT_POINT"; then
  mkdir -p $MOUNT_POINT
  if ! blkid $DEVICE | grep -q ext4; then
    mkfs.ext4 $DEVICE
  fi
  mount $DEVICE $MOUNT_POINT
  UUID=$(blkid -s UUID -o value $DEVICE)
  grep -q "$UUID" /etc/fstab || echo "UUID=$UUID $MOUNT_POINT ext4 defaults,nofail 0 2" >> /etc/fstab
  echo "✅ EBS volume mounted successfully"
fi

# --- Configure Docker with Memory Optimizations ---
mkdir -p "$MOUNT_POINT/docker"
mkdir -p /etc/docker
cat > /etc/docker/daemon.json <<EOL
{
  "data-root": "$MOUNT_POINT/docker",
  "storage-driver": "overlay2",
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "default-ulimits": {
    "memlock": {
      "Name": "memlock",
      "Hard": -1,
      "Soft": -1
    }
  }
}
EOL

# Start Docker
systemctl daemon-reexec
systemctl enable docker
systemctl start docker

# Wait for Docker to be ready
until docker info >/dev/null 2>&1; do
  echo "Waiting for Docker to start..."
  sleep 2
done

# Add EC2 user to Docker group
usermod -aG docker ec2-user
echo "✅ Docker configured and started"

# --- Install Docker Compose Plugin (v2) ---
sudo -u ec2-user bash <<'EOF'
set -euxo pipefail
mkdir -p ~/.docker/cli-plugins
curl -SL https://github.com/docker/compose/releases/download/v2.27.0/docker-compose-linux-x86_64 -o ~/.docker/cli-plugins/docker-compose
chmod +x ~/.docker/cli-plugins/docker-compose
echo "✅ Docker Compose installed"
EOF

# --- Setup Memory Monitoring ---
sudo -u ec2-user bash <<'EOF'
cat > ~/monitor_system.sh <<'MONITOR'
#!/bin/bash
LOG_FILE="$HOME/system_monitor.log"
echo "=== System Monitor Started at $(date) ===" >> $LOG_FILE

while true; do
  {
    echo "--- $(date) ---"
    echo "Memory Usage:"
    free -h
    echo "Swap Usage:"
    swapon --show
    echo "Docker Stats:"
    timeout 10 docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}" 2>/dev/null || echo "Docker not ready"
    echo "Disk Usage:"
    df -h /mnt/docker-storage
    echo "===================="
  } >> $LOG_FILE 2>&1
  sleep 60
done
MONITOR

chmod +x ~/monitor_system.sh
nohup ~/monitor_system.sh > /dev/null 2>&1 &
echo "✅ System monitoring started"
EOF

# --- Clone Repo & Start the App with Maximum Optimization ---
sudo -u ec2-user bash <<'EOF'
set -euxo pipefail
cd ~

# Set conservative shell limits
ulimit -n 1024
ulimit -u 1024

git lfs install

# Clone only if not already present
if [ ! -d "ripensense" ]; then
  echo "Cloning repository..."
  git clone https://github.com/sohampatil44/ripensense.git
else
  echo "Repository already exists, updating..."
  cd ripensense
  git pull
  cd ~
fi

cd ripensense

# Pull LFS files
echo "Pulling LFS files..."
git lfs pull

# Set Docker Compose path
export PATH="$HOME/.docker/cli-plugins:$PATH"

# Create HIGHLY optimized override config
cat > docker-compose.override.yml <<EOL
services:
  backend:
    command: gunicorn --workers=1 --worker-class=sync --worker-connections=1 --timeout=600 --keepalive=2 --max-requests=50 --max-requests-jitter=10 --preload --bind 0.0.0.0:8000 app:app
    deploy:
      resources:
        limits:
          memory: 300M
          cpus: '0.5'
        reservations:
          memory: 150M
          cpus: '0.25'
    restart: always
    environment:
      - PYTHONUNBUFFERED=1
      - PYTHONDONTWRITEBYTECODE=1
      - TF_CPP_MIN_LOG_LEVEL=2
      - CUDA_VISIBLE_DEVICES=""
      - TF_FORCE_GPU_ALLOW_GROWTH=false
      - TF_XLA_FLAGS=--tf_xla_enable_xla_devices=false
      - OMP_NUM_THREADS=1
      - TF_NUM_INTEROP_THREADS=1
      - TF_NUM_INTRAOP_THREADS=1
      - MALLOC_MMAP_THRESHOLD_=1024
      - MALLOC_TRIM_THRESHOLD_=1024
      - MALLOC_TOP_PAD_=1024
      - MALLOC_MMAP_MAX_=65536
    healthcheck:
      test: ["CMD-SHELL", "curl -f http://localhost:8000/health || exit 1"]
      interval: 120s
      timeout: 30s
      retries: 3
      start_period: 60s
    ulimits:
      memlock:
        soft: -1
        hard: -1
      nofile:
        soft: 1024
        hard: 1024
    tmpfs:
      - /tmp:size=50M
EOL

echo "✅ Docker Compose override created with aggressive memory optimization"

# Clean up before starting
echo "Cleaning up existing containers..."
docker compose down --remove-orphans 2>/dev/null || true
docker system prune -f --volumes 2>/dev/null || true

# Pre-pull image to avoid timeout during startup
echo "Pre-pulling Docker image..."
timeout 300 docker compose pull || {
  echo "⚠️ Image pull timed out or failed, proceeding anyway"
}

# Start application with retry logic and progressive timeouts
for attempt in {1..5}; do
  echo "🚀 Deployment attempt $attempt of 5..."
  
  # Check available memory before starting
  FREE_MEM=$(free -m | awk 'NR==2{print $7}')
  echo "Available memory: ${FREE_MEM}MB"
  
  if [ $FREE_MEM -lt 100 ]; then
    echo "⚠️ Low memory detected, forcing garbage collection..."
    echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
    sync
    sleep 10
  fi
  
  # Start with timeout
  if timeout 180 docker compose up -d; then
    echo "✅ Container started successfully on attempt $attempt"
    
    # Wait for health check
    echo "Waiting for application to become healthy..."
    sleep 30
    
    # Check if container is running
    if docker compose ps | grep -q "running"; then
      echo "🎉 Application is running successfully!"
      break
    else
      echo "❌ Container exited, checking logs..."
      docker compose logs --tail=50
    fi
  else
    echo "❌ Attempt $attempt failed"
    docker compose down 2>/dev/null || true
    
    if [ $attempt -lt 5 ]; then
      WAIT_TIME=$((attempt * 30))
      echo "Waiting ${WAIT_TIME}s before retry..."
      sleep $WAIT_TIME
      
      # Clear memory
      echo "Clearing caches..."
      echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
      sync
    fi
  fi
done

# Final status check and logging
echo "=== Final Status Check ==="
docker compose ps -a > ~/container-status.log 2>&1
docker compose logs --no-color --tail=100 > ~/docker-startup.log 2>&1

# Get final system stats
{
  echo "=== Final System Status ==="
  echo "Memory:"
  free -h
  echo "Swap:"
  swapon --show
  echo "Disk:"
  df -h
  echo "Docker:"
  docker ps -a
} > ~/final-status.log 2>&1

# Check if app is accessible
if curl -f http://localhost:8000/health >/dev/null 2>&1; then
  echo "🎉 SUCCESS: Application is healthy and responding!"
else
  echo "⚠️ Application may not be fully ready yet. Check logs in ~/docker-startup.log"
fi

EOF

echo "✅ Deployment script completed successfully at $(date)"
echo "📊 Check system status: sudo su - ec2-user -c 'tail -f ~/system_monitor.log'"
echo "📋 Check app logs: sudo su - ec2-user -c 'cd ~/ripensense && docker compose logs -f'"