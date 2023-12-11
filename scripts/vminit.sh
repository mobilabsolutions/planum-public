sudo apt update
sudo apt install -y apt-transport-https ca-certificates curl software-properties-common jq net-tools certbot authbind
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.28/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.28/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt update
sudo apt install -y docker-ce kubectl
sudo useradd -d /home/planum planum
sudo usermod -aG docker planum
sudo su - planum
curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
k3d cluster create planum -p "30000-30010:30000-30010@server:0"
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "NodePort"}}'
kubectl get service argocd-server -n argocd -ojson | jq '.spec.ports[0].nodePort = 30000' | jq '.spec.ports[1].nodePort = 30001' | kubectl apply -f -
kubectl patch configmap argocd-cm -n argocd --type merge -p '{"data":{"application.resourceTrackingMethod":"annotation"}}'
curl -sSL -o argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
sudo install -m 555 argocd-linux-amd64 /usr/local/bin/argocd
rm argocd-linux-amd64
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
helm repo add crossplane-stable https://charts.crossplane.io/stable
helm repo update
helm install crossplane -n crossplane-system crossplane-stable/crossplane --create-namespace --set args='{--debug,--enable-environment-configs}'

kubectl create namespace planum

kubectl create clusterrolebinding planum-admin-binding --clusterrole cluster-admin --serviceaccount="planum:default"

gitHubOrganization=$(cat /tmp/gitHubOrganization.txt | xargs)
gitHubRepo=$(cat /tmp/gitHubRepo.txt | xargs)
gitHubToken=$(cat /tmp/gitHubToken.txt | xargs)
sudo rm -f /tmp/gitHub*.txt

#planum app
while test -z $(kubectl get appprojects -n argocd | grep default)
do
  sleep 15
done
cat <<EOF | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: planum
  namespace: argocd
spec:
  destination:
    namespace: planum
    server: https://kubernetes.default.svc
  project: default
  source:
    directory:
      jsonnet: {}
      recurse: true
    path: crossplane
    repoURL: https://github.com/mobilabsolutions/planum-public
    targetRevision: HEAD
  syncPolicy:
    automated:
      selfHeal: true
    retry:
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m0s
      limit: 3
EOF
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: platform
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repository
stringData:
  url: https://github.com/${gitHubOrganization}/${gitHubRepo}
  password: ${gitHubToken}
  username: argocd
  project: default
  type: git
  name: platform
EOF
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  namespace: planum
  name: github
type: Opaque
stringData:
  credentials: |
    {
      "token": "${gitHubToken}"
    }
EOF
cat <<EOF | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: platform
  namespace: argocd
spec:
  destination:
    namespace: platform
    server: https://kubernetes.default.svc
  project: default
  source:
    directory:
      jsonnet: {}
      recurse: true
    path: .
    repoURL: https://github.com/${gitHubOrganization}/${gitHubRepo}
    targetRevision: HEAD
  syncPolicy:
    automated:
      selfHeal: true
    retry:
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m0s
      limit: 3
EOF

while test -z $(kubectl api-resources -oname | grep "providers.pkg.crossplane.io")
do
  sleep 15
done

cat <<EOF | kubectl apply -f -
apiVersion: pkg.crossplane.io/v1
kind: Provider
metadata:
  name: provider-kubernetes
spec:
  package: xpkg.upbound.io/crossplane-contrib/provider-kubernetes:v0.9.0
EOF

kubectl get providers

while test -z $(kubectl api-resources -oname | grep "providerconfigs.kubernetes.crossplane.io")
do
  sleep 15
done

cat <<EOF | kubectl apply -f -
apiVersion: kubernetes.crossplane.io/v1alpha1
kind: ProviderConfig
metadata:
  name: kubernetes
spec:
  credentials:
    source: InjectedIdentity
EOF

cat <<EOF | kubectl apply -f -
apiVersion: github.crossplane.io/v1alpha1
kind: ProviderConfig
metadata:
  name: github-provider-config
spec:
  credentials:
    source: Secret
    secretRef:
      namespace: planum
      name: github
      key: credentials
EOF

SA=""
while test -z $SA
do
  sleep 5
  SA=$(kubectl -n crossplane-system get sa -o name | grep provider-kubernetes | sed -e 's|serviceaccount\/|crossplane-system:|g')
done
kubectl create clusterrolebinding provider-kubernetes-admin-binding --clusterrole cluster-admin --serviceaccount="${SA}"

password=$(argocd admin initial-password -n argocd | head -n 1 | xargs)
echo "password:$password"
argocd login localhost:30001 --username admin --password $password --insecure
argocd account update-password --account admin --current-password $password --new-password ${gitHubToken:0:8}

sudo iptables -t nat -A PREROUTING -p tcp --dport 443 -i eth0 -j REDIRECT --to-port 30001

mkdir cert
sudo touch /etc/authbind/byport/80
sudo chgrp planum /etc/authbind/byport/80
sudo chmod g+x /etc/authbind/byport/80
authbind certbot certonly --quiet --non-interactive --agree-tos --keep-until-expiring --config-dir=./cert/ --work-dir=./cert/ --logs-dir=./cert/  -m "ramin@mblb.net" -d $(cat /tmp/fqdn.txt|xargs) --standalone
kubectl create -n argocd secret tls argocd-server-tls --cert=./cert/live/$(cat /tmp/fqdn.txt|xargs)/fullchain.pem  --key=./cert/live/$(cat /tmp/fqdn.txt|xargs)/privkey.pem

#to make sure providerconfigs.azure.upbound.io will be avilable soon
cat <<EOF | kubectl apply -f -
apiVersion: pkg.crossplane.io/v1
kind: Provider
metadata:
  name: provider-azure-web
spec:
  package: xpkg.upbound.io/upbound/provider-azure-web:v0.39.0
EOF

curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
instanceMetadata=$(curl -s -H Metadata:true --noproxy "*" "http://169.254.169.254/metadata/instance?api-version=2021-02-01")
vmName=$(echo $instanceMetadata | jq -r '.compute.name')
resourceGroupName=$(echo $instanceMetadata | jq -r '.compute.resourceGroupName')
az login --identity
vmIdentityPrincipalId=$(az account get-access-token | jq -r '.accessToken' | jq -r -R 'split(".") | .[1] | @base64d | fromjson | .oid')
kubectl create namespace planum
kubectl create configmap vm --namespace=planum --from-literal=vmName=$vmName --from-literal=resourceGroupName=$resourceGroupName --from-literal=vmIdentityPrincipalId=$vmIdentityPrincipalId

echo "creating default"

while test -z $(kubectl api-resources -oname | grep "providerconfigs.azure.upbound.io")
do
  echo "waiting for providerconfigs.azure.upbound.io to be available..."
  sleep 15
done

account=$(az account show)
tenantId=$(echo $account | jq -r '.tenantId')
subscriptionId=$(echo $account | jq -r '.id')
appId=$(az account get-access-token | jq -r '.accessToken' | jq -r -R 'split(".") | .[1] | @base64d | fromjson | .appid')

cat <<EOF | kubectl apply -f -
apiVersion: azure.upbound.io/v1beta1
metadata:
  name: default
kind: ProviderConfig
spec:
  credentials:
    source: SystemAssignedManagedIdentity
  subscriptionID: $subscriptionId
  tenantID: $tenantId
  clientID: $appId
EOF

echo "done"