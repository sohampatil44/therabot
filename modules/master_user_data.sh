#!/bin/bash

set -xe
exec > >(tee /var/log/master_user_data.log | logger -t master_user_data -s 2>/dev/console) 2>&1
yum update -y


yum install -y curl wget unzip jq amazon-ssm-agent
yum install -y curl python3 awscli

#enable and start ssm agent

systemctl enable amazon-ssm-agent
systemctl start amazon-ssm-agent

#Install k3s master
curl -sfL https://get.k3s.io | sh -s - server --write-kubeconfig-mode 644

sleep 20
#Save k3s token for worker nodes to join the master

mkdir -p /var/lib/rancher/k3s/server
cp /var/lib/rancher/k3s/server/node-token /tmp/k3s_token

#store kubeconfig in a secure location
cp /etc/rancher/k3s/k3s.yaml /home/ec2-user/kubeconfig
chown ec2-user:ec2-user /home/ec2-user/kubeconfig

#push k3s token to SSM parameter store
TOKEN=$(cat /tmp/k3s_token)
aws ssm put-parameter --name "/k3s/token" --value "$TOKEN" --type "SecureString" --region "us-east-1"


#save master private ip to ssm


MASTER_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)
aws ssm put-parameter \
    --name "/k3s/master/private_ip" \
    --value "$MASTER_IP" \
    --type "String" \
    --overwrite \
    --region $(AWS_REGION:-us-east-1)