#!/bin/bash

echo "----------------- Installing Basic CICD Tools -----------------"

cd $HOME

mkdir configFiles

cd configFiles

echo "----------------- Kubernetes (Minikube) -----------------"

minikube start

minikube kubectl -- get pods -A

minikube addons enable ingress

echo "----------------- Istio -----------------"

# Reference: https://istio.io/latest/docs/setup/install/helm/

helm repo add istio https://istio-release.storage.googleapis.com/charts

helm repo update

kubectl create namespace istio-system

helm install istio-base istio/base -n istio-system

helm install istiod istio/istiod -n istio-system --wait

helm status istiod -n istio-system

echo "----------------- Istio -----------------"

# Reference: https://istio.io/latest/docs/setup/getting-started/#download

curl -L https://istio.io/downloadIstio | ISTIO_VERSION=1.16.0 TARGET_ARCH=x86_64 sh -

cd istio-1.16.0

export PATH=$PWD/bin:$PATH

echo "----------------- Kiali -----------------"

# Reference: https://kiali.io/docs/installation/installation-guide/install-with-helm/

helm repo add kiali https://kiali.org/helm-charts

helm repo update

helm install \
    --set cr.create=true \
    --set cr.namespace=istio-system \
    --namespace kiali-operator \
    --create-namespace \
    kiali-operator \
    kiali/kiali-operator


echo "----------------- Deploy Kiali on kubernetes -----------------"

# Reference: https://istio.io/latest/docs/ops/integrations/kiali/#installation

cd $HOME/configFiles

mkdir kiali

cd kiali

read -p "Enter URL Kiali yaml: " urlKiali

wget $urlKiali

read -p "Enter yaml file name: " fileKiali

filename="${HOME}/configFiles/kiali/${fileKiali}"

echo "Path file: ${HOME}/configFiles/kiali/${fileKiali}"

read -p "Enter Kiali token login: " tokenKiali

initToken="CHANGEME00000000"

sed -i "s/${initToken}/${tokenKiali}/" $filename

kubectl apply -f $fileKiali

echo "----------------- Deploy Jaeger on kubernetes -----------------"

cd $HOME/configFiles

mkdir jaeger

cd jaeger

read -p "Enter URL Jaeger yaml: " urlJaeger

wget $urlJaeger

read -p "Enter yaml file name: " fileJaeger

kubectl apply -f $fileJaeger

echo "----------------- Jenkins -----------------"

curl -fsSL https://pkg.jenkins.io/debian/jenkins.io.key | sudo tee \/usr/share/keyrings/jenkins-keyring.asc > /dev/null

echo deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] \https://pkg.jenkins.io/debian binary/ | sudo tee \/etc/apt/sources.list.d/jenkins.list > /dev/null

sudo apt-get update

sudo apt-get install jenkins

echo "All tools has been installed ........ "