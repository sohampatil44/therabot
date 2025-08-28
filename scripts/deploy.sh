#!bin/bash
K3S_MASTER="<MASTER_PRIVATE_IP>"
K3S_TOKEN="$(curl -s http://${K3S_MASTER}:3000/node-token)"

curl -sfL https://get.k3s.io | K3S_URL="https://${K3S_MASTER}:6443" \
    K3S_TOKEN="$K3S_TOKEN" sh -


    