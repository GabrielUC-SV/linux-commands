#!/bin/bash

echo "----------------- Installing Basic CICD Tools -----------------"

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

read -p "Enter user for add to docker group: " username

sudo usermod -aG docker $username

echo "----------------- Helm -----------------"

curl https://baltocdn.com/helm/signing.asc | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg > /dev/null

sudo apt-get install apt-transport-https --yes

echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list

sudo apt-get update

sudo apt-get install helm --yes

helm version

echo "----------------- Kubernetes (Minikube) -----------------"

curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64

sudo install minikube-linux-amd64 /usr/local/bin/minikube

minikube start

minikube kubectl -- get pods -A

alias kubectl="minikube kubectl"

echo "----------------- Install Istio -----------------"

helm repo add istio https://istio-release.storage.googleapis.com/charts

helm repo update

kubectl create namespace istio-system

helm install istio-base istio/base -n istio-system

helm install istiod istio/istiod -n istio-system --wait

kubectl create namespace istio-ingress

kubectl label namespace istio-ingress istio-injection=enabled

helm install istio-ingress istio/gateway -n istio-ingress --wait

helm status istiod -n istio-system

echo "----------------- insatall Kiali -----------------"

helm repo add kiali https://kiali.org/helm-charts

helm repo update

helm install \
    --set cr.create=true \
    --set cr.namespace=istio-system \
    --namespace kiali-operator \
    --create-namespace \
    kiali-operator \
    kiali/kiali-operator

echo "All tools has been installed ........ "