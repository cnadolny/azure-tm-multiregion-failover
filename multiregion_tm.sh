# Testing Azure Traffic Manager Failover on Multi Region Kubernetes Clusters

export LOCATION1="eastus"
export LOCATION2="westus2"
export RG1="$LOCATION1"
export RG2="$LOCATION2"
export NAME1="$LOCATION1-test"
export NAME2="$LOCATION2-test"
export MYNGINX="my-nginx"
export TM_DNS_NAME="traffic-manager-k8-$((10 + RANDOM%1000))"
export TM_RG="traffic-manager-test"
export TM_NAME="traffic-manager-test"
export TM_LOC="centralus"

# Create RGs and Resources
az group create -n $RG1 -l $LOCATION1
az group create -n $RG2 -l $LOCATION2
az group create -n $TM_RG -l $TM_LOC

az aks create -n $NAME1 -g $RG1 --generate-ssh-keys
az aks create -n $NAME2-test -g $RG2 --generate-ssh-keys
az network traffic-manager profile create -n $TM_NAME -g $TM_RG --routing-method Performance --unique-dns-name $TM_DNS_NAME

# Create the NGINX services for LOCATION1
az aks get-credentials -n $NAME1 -g $RG1

kubectl run $MYNGINX --image=nginx --port=80
kubectl expose deployment $MYNGINX --port=80 --type=LoadBalancer

NGINXIP=""
while [ -z $NGINXIP ]; do
  NGINXIP=$(kubectl get svc $MYNGINX --template="{{range .status.loadBalancer.ingress}}{{.ip}}{{end}}")
  [ -z "$NGINXIP" ] && sleep 10
  echo "Waiting on external IP..."
done
echo $NGINXIP

DNSNAME="nginx-$LOCATION1-kubernetes-$((10 + RANDOM%1000))"

PODNAME="$(k get po | grep $MYNGINX | cut -d' ' -f1)"

kubectl exec -it $PODNAME -- bash -c "echo $LOCATION1 > /usr/share/nginx/html/index.html && exit"

# Get the resource-id of the public ip
PUBLICIPID="$(az network public-ip list --query "[?ipAddress!=null]|[?contains(ipAddress, '$NGINXIP')].[id]" --output tsv)"

# Update public ip address with DNS name
az network public-ip update --ids $PUBLICIPID --dns-name $DNSNAME

az -network traffic-manager endpoint create --name $LOCATION1-endpoint --profile-name $TM_NAME -g $TM_RG -t externalEndpoints --target $DNSNAME.$LOCATION1.cloudapp.azure.com --endpoint-location $LOCATION1

#Next, for LOCATION2
az aks get-credentials -n $NAME2 -g $RG2

kubectl run $MYNGINX --image=nginx --port=80
kubectl expose deployment $MYNGINX --port=80 --type=LoadBalancer

NGINXIP=""
while [ -z $NGINXIP ]; do
  NGINXIP=$(kubectl get svc $MYNGINX --template="{{range .status.loadBalancer.ingress}}{{.ip}}{{end}}")
  [ -z "$NGINXIP" ] && sleep 10
  echo "Waiting on external IP..."
done
echo $NGINXIP

DNSNAME="nginx-$LOCATION2-kubernetes-$((10 + RANDOM%1000))"

PODNAME="$(kubectl get po | grep $MYNGINX | cut -d' ' -f1)"

kubectl exec -it $PODNAME -- bash -c "echo $LOCATION2 > /usr/share/nginx/html/index.html && exit"

# Get the resource-id of the public ip
PUBLICIPID="$(az network public-ip list --query "[?ipAddress!=null]|[?contains(ipAddress, '$NGINXIP')].[id]" --output tsv)"

# Update public ip address with DNS name
az network public-ip update --ids $PUBLICIPID --dns-name $DNSNAME

az network traffic-manager endpoint create --name $LOCATION2-endpoint --profile-name $TM_NAME -g $TM_RG -t externalEndpoints --target $DNSNAME.$LOCATION2.cloudapp.azure.com --endpoint-location $LOCATION2

echo $TM_DNS_NAME.trafficmanager.net