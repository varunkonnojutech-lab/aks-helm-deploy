# AKS setup: from zero to `helm install`

Everything below uses the Azure CLI. Costs are real — a 2-node Standard
cluster runs roughly a dollar or two a day — so the last step is cleanup.

## 1. Resource group, registry, cluster

```bash
RG=rg-shop-dev
LOCATION=eastus
ACR=shopacr$RANDOM        # must be globally unique, lowercase letters/numbers
AKS=aks-shop-dev

az group create -n $RG -l $LOCATION
az acr create -n $ACR -g $RG --sku Basic
az aks create -n $AKS -g $RG --node-count 2 \
  --node-vm-size Standard_B2s --attach-acr $ACR \
  --generate-ssh-keys
az aks get-credentials -n $AKS -g $RG
kubectl get nodes   # should list 2 Ready nodes
```

`--attach-acr` is the step people skip and then debug for an hour: it grants
the cluster's managed identity permission to pull from your registry, so you
never hand-craft an `imagePullSecret`.

## 2. Build and push the service images

From a checkout of the
[dotnet-microservices](https://github.com/varunkonnojutech-lab/dotnet-microservices)
repo, which holds one Dockerfile per service:

```bash
cd dotnet-microservices
az acr build -r $ACR -t ecommerce/catalog-service:latest  -f src/CatalogService/Dockerfile  .
az acr build -r $ACR -t ecommerce/ordering-service:latest -f src/OrderingService/Dockerfile .
az acr build -r $ACR -t ecommerce/gateway:latest          -f src/Gateway/Dockerfile          .
```

`az acr build` compiles in Azure, so you don't need Docker locally.

## 3. Ingress controller (prod values only)

The prod values file enables an Ingress, which needs a controller to serve
it. ingress-nginx is the standard choice on AKS:

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace
kubectl get svc -n ingress-nginx   # note the EXTERNAL-IP
```

Point your DNS hostname at that IP, then set `ingress.host` in
`values-prod.yaml` to match.

## 4. Secrets, then install

```bash
kubectl create namespace microservices
kubectl create secret generic rabbitmq-auth -n microservices \
  --from-literal=username=shop-user \
  --from-literal=password="$(openssl rand -base64 24)"
```

Edit `values-prod.yaml`: `global.imageRegistry` to `$ACR.azurecr.io`,
`ingress.host` to your hostname, and confirm
`rabbitmq.auth.existingSecret: rabbitmq-auth`. Then:

```bash
helm install shop ./charts/microservices \
  -f charts/microservices/values-prod.yaml \
  --namespace microservices
kubectl get pods,svc,ingress -n microservices
curl https://<your-host>/catalog/products
```

## 5. Day-2 commands worth memorizing

```bash
helm upgrade shop ./charts/microservices -f charts/microservices/values-prod.yaml -n microservices
helm history shop -n microservices
helm rollback shop -n microservices
kubectl logs -l app.kubernetes.io/component=catalog -n microservices --tail=50
kubectl scale deploy/shop-catalog -n microservices --replicas=4   # then watch the HPA fight you — that's the lesson
```

## 6. Cleanup

```bash
az group delete -n $RG --yes --no-wait
```

Deleting the resource group removes the cluster, the registry, and the
disks in one shot — nothing billable is left behind.
