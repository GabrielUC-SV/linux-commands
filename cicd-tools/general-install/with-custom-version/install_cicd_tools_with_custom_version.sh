#!/bin/bash

echo "----------------- Start Install Docker -----------------"

sudo apt-get update

sudo apt-get install \
    ca-certificates \
    curl \
    gnupg \
    lsb-release --yes

apt-cache madison docker-ce

apt-cache madison docker-ce-cli

sudo apt-get install docker-ce="5:19.03.12~3-0~ubuntu-focal" docker-ce-cli="5:19.03.12~3-0~ubuntu-focal" containerd.io docker-compose-plugin --yes

sudo service docker start

sudo usermod -aG docker ${USER}

su - ${USER}

read -p "Enter user for add to docker group: " username

sudo usermod -aG docker $username


echo "----------------- Helm -----------------"

sudo apt-get update

apt-cache madison helm

sudo apt-get install helm="3.1.2-1" --yes

helm version

echo "----------------- Kubernetes (Kubectl) -----------------"

curl -LO https://dl.k8s.io/release/v1.19.3/bin/linux/amd64/kubectl

sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

kubectl version --client --output=yaml


echo "----------------- RKE (Rancher) -----------------"

curl -s https://api.github.com/repos/rancher/rke/releases/latest | grep download_url | grep amd64 | cut -d '"' -f 4 

curl -LO "https://github.com/rancher/rke/releases/download/v1.2.21-rc1/rke_linux-amd64"

chmod +x ./rke_linux-amd64

sudo mv ./rke_linux-amd64 /usr/local/bin/rke

rke --version

echo "----------------- Kubeadm -----------------"

sudo apt-get update

sudo apt-get install -y apt-transport-https ca-certificates curl

sudo curl -fsSLo /usr/share/keyrings/kubernetes-archive-keyring.gpg https://packages.cloud.google.com/apt/doc/apt-key.gpg

echo "deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list

sudo apt-get update

sudo apt-get install -y kubelet kubeadm kubectl

sudo apt-mark hold kubelet kubeadm kubectl

echo "----------------- SSH -----------------"


sudo apt install openssh-server --yes

filename="/etc/ssh/sshd_config"

oldvalues=(
  "#Port 22"
  "PasswordAuthentication no"
  "#PermitEmptyPasswords no"
  "#AllowAgentForwarding yes"
  "#AllowTcpForwarding yes"
  "#PermitTTY yes"
  "#PrintLastLog yes"
  "#PermitTunnel no"
)

newvalues=(
  "Port 22"
  "PasswordAuthentication yes"
  "PermitEmptyPasswords yes"
  "AllowAgentForwarding yes"
  "AllowTcpForwarding yes"
  "PermitTTY yes"
  "PrintLastLog yes"
  "PermitTunnel yes"
)

echo "Replacing values start ..."

for (( i = 0; i < ${#oldvalues[@]}; ++i )); do

    if grep -Fxq "${oldvalues[i]}" $filename
  then
      sudo sed -i "s/${oldvalues[i]}/${newvalues[i]}/" $filename
      echo "${oldvalues[i]} : replaced"
  else
      echo "${oldvalues[i]} : not found"
  fi
done

echo "Replacing values done ..."

sudo service ssh stop

sudo ufw allow ssh

sudo swapoff -a

sudo service ssh start

echo "----------------- create SSH directories -----------------"

mkdir $HOME/.ssh

chmod 700 $HOME/.ssh

touch $HOME/.ssh/authorized_keys

chmod 600 $HOME/.ssh/authorized_keys

echo "----------------- creating SSH key pair -----------------"

cd $HOME/.ssh/

ssh-keygen -t rsa

echo "----------------- insatall ssh public key -----------------"

cat $HOME/.ssh/id_rsa.pub | ssh 127.0.0.1 "sudo tee -a $HOME/.ssh/authorized_keys"

cat $HOME/.ssh/id_rsa.pub > $HOME/.ssh/authorized_keys

echo "All tools has been installed ........ "