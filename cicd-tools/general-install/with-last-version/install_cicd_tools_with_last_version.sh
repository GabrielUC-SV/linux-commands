#!/bin/bash

echo "----------------- Start Install Docker -----------------"

sudo apt-get update

sudo apt-get install \
    ca-certificates \
    curl \
    gnupg \
    lsb-release --yes

sudo mkdir -p /etc/apt/keyrings

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update

sudo apt-get install docker-ce docker-ce-cli containerd.io docker-compose-plugin --yes

sudo service docker start

sudo usermod -aG docker ${USER}

su - ${USER}

sudo usermod -aG docker gabriel-uc


echo "----------------- Helm -----------------"

curl https://baltocdn.com/helm/signing.asc | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg > /dev/null

sudo apt-get install apt-transport-https --yes

echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list

sudo apt-get update

sudo apt-get install helm --yes

helm version

echo "----------------- Kubernetes (Kubectl) -----------------"

curl -LO https://storage.googleapis.com/kubernetes-release/release/`curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt`/bin/linux/amd64/kubectl

chmod +x ./kubectl

sudo mv ./kubectl /usr/local/bin/kubectl

kubectl version --client


echo "----------------- RKE (Rancher) -----------------"

curl -s https://api.github.com/repos/rancher/rke/releases/latest | grep download_url | grep amd64 | cut -d '"' -f 4 

curl -LO "https://github.com/rancher/rke/releases/download/v1.3.15/rke_linux-amd64"

chmod +x ./rke_linux-amd64

sudo mv ./rke_linux-amd64 /usr/local/bin/rke

rke --version

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