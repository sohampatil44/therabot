#!/bin/bash


set -xe
exec > >(tee /var/log/worker_user_data.log | logger -t worker_user_data -s 2>/dev/console) 2>&1

yum update -y 

#Install dependencies
yum install -y  wget unzip jq amazon-ssm-agent
yum install -y python3 awscli

#enable and start ssm agent

systemctl enable amazon-ssm-agent
systemctl start amazon-ssm-agent

#fetch token from ssm

TOKEN=$(aws ssm get-parameter --name "/k3s/token" --with-decryption --query "Parameter.Value" --output text --region $(AWS_REGION:-us-east-1))


#Fetch master priv IP from ASG or known value
MASTER_IP=$(aws ssm get-parameter --name "/k3s/master/private_ip" --query "Parameter.Value" --output text --region $(AWS_REGION:-us-east-1))

#install k3s agent (worker node)
curl -sfL https://get.k3s.io | K3S_URL="https://${MASTER_IP}:6443" K3S_TOKEN="$TOKEN" sh -

#setup kubeconfig for ec2-user
cp /etc/rancher/k3s/k3s.yaml /home/ec2-user/kubeconfig
chown ec2-user:ec2-user /home/ec2-user/kubeconfig
chmod 644 /home/ec2-user/kubeconfig

#verify node has joined the cluster
sleep 20
kubectl get nodes --kubeconfig /home/ec2-user/kubeconfig    
kubectl get pods -A --kubeconfig /home/ec2-user/kubeconfig

