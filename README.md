# aks-helm-deploy

[![CI](https://github.com/varunkonnojutech-lab/aks-helm-deploy/actions/workflows/ci.yml/badge.svg)](https://github.com/varunkonnojutech-lab/aks-helm-deploy/actions/workflows/ci.yml)
[![Open in GitHub Codespaces](https://github.com/codespaces/badge.svg)](https://codespaces.new/varunkonnojutech-lab/aks-helm-deploy)

Deploy the [dotnet-microservices](https://github.com/varunkonnojutech-lab/dotnet-microservices) app — Catalog API, Ordering API, YARP gateway, RabbitMQ — to Azure Kubernetes Service with one Helm chart.

## Who it's for

You can already run the microservices app with `docker compose` and you want the next step: a real cluster, with one command to install, upgrade, and roll back the whole system. No prior Helm experience assumed — every template is commented, and the chart is deliberately small enough to read end to end.

## What you'll learn

- **Chart anatomy** — `Chart.yaml`, `values.yaml`, `_helpers.tpl`, and one template file per Kubernetes object, with no magic.
- **Templating that stays readable** — named templates for labels and image names, `toYaml` for resources, and per-component `enabled` flags instead of copy-pasted YAML.
- **Service discovery, the Helm way** — the app's config points at bare hostnames (`catalog`, `ordering`), but Helm names Services `<release>-catalog`. The chart bridges that gap with environment-variable overrides (`ReverseProxy__Clusters__...__Address`), which is how ASP.NET Core config layering is supposed to work.
- **Environment layering** — base `values.yaml` plus `values-dev.yaml` (one replica, no persistence) and `values-prod.yaml` (autoscaling, Ingress + TLS, secrets via `existingSecret`).
- **Day-2 operations** — `helm upgrade`, `helm rollback`, `helm diff`-style review with `helm template`, and HorizontalPodAutoscalers driven by CPU.
- **AKS specifics** — ACR attach, the `managed` StorageClass for RabbitMQ persistence, and ingress-nginx in front of the gateway (see [docs/aks-setup.md](docs/aks-setup.md)).

## What the chart deploys

| Component | Objects | Notes |
|---|---|---|
| Catalog API | Deployment + ClusterIP Service | HTTP probes on `/products` (a real route) |
| Ordering API | Deployment + ClusterIP Service | HTTP probes on `/orders` |
| YARP gateway | Deployment + Service | Only public entry point; TCP probes (it owns no route) |
| RabbitMQ | Deployment + Service + PVC | Single broker on purpose; management UI on 15672 |
| Ingress (prod only) | Ingress | nginx class, optional TLS |
| Autoscaling (prod only) | 3 HPAs | CPU-based, one per API/gateway |

## Quick start

No cluster needed to learn the chart — rendering it is the fastest feedback loop:

```bash
helm lint charts/microservices
helm template shop charts/microservices | python3 scripts/validate_templates.py
helm template shop charts/microservices -f charts/microservices/values-prod.yaml
```

### Deploy to a cluster (kind, minikube, or AKS)

First build and push the service images — the default image names match the
`dotnet-microservices` repo's manifests (`ecommerce/catalog-service` and
friends). For AKS, see [docs/aks-setup.md](docs/aks-setup.md) for the
ACR + `az acr build` version of this step.

```bash
# Dev: one replica each, ClusterIP gateway, no persistence
./scripts/deploy.sh dev

# Or by hand:
helm install shop ./charts/microservices \
  -f charts/microservices/values-dev.yaml \
  --namespace microservices --create-namespace
```

Then exercise the whole system through the gateway:

```bash
kubectl port-forward svc/shop-gateway -n microservices 8080:80
curl http://localhost:8080/catalog/products

# Create an order, then watch the stock drop (Ordering publishes an
# OrderCreated event; Catalog consumes it and decrements stock)
curl -X POST http://localhost:8080/orders \
  -H "Content-Type: application/json" \
  -d '{"productId": 1, "quantity": 2}'
curl http://localhost:8080/catalog/products
```

### Upgrade, roll back, uninstall

```bash
helm upgrade shop ./charts/microservices \
  -f charts/microservices/values-prod.yaml -n microservices
helm history shop -n microservices
helm rollback shop -n microservices        # previous revision, one command
helm uninstall shop -n microservices
```

## The values files, and when to use each

| File | Use it when… | Key differences |
|---|---|---|
| `charts/microservices/values.yaml` | Defaults / learning | 2 replicas, LoadBalancer gateway, RabbitMQ persistence on |
| `charts/microservices/values-dev.yaml` | Local clusters, Codespaces review | 1 replica, ClusterIP gateway, no persistence |
| `charts/microservices/values-prod.yaml` | AKS | 3 replicas, HPAs, Ingress + TLS, RabbitMQ password from a Secret |

Production checklist before `helm install -f values-prod.yaml`:

1. Set `global.imageRegistry` to your ACR login server.
2. Set `ingress.host` to your real hostname.
3. Create the RabbitMQ Secret and set `rabbitmq.auth.existingSecret` — never commit a real password in values.
4. Install ingress-nginx first (see [docs/aks-setup.md](docs/aks-setup.md)).

## One gotcha, solved in the chart

Disabling a backend (`catalog.enabled=false`) also removes the gateway's
override for that backend's YARP cluster — otherwise the gateway would point
at a Service that doesn't exist. But the YARP *route* still lives in the
app's `appsettings.json`, so requests to `/catalog/...` will fail until that
route is removed from the app config too. Helm can only wire up what exists;
the app's routing table is still the app's job.

## Next steps

- Add cert-manager + Let's Encrypt so `ingress.tls` needs no manual Secret.
- Swap the single RabbitMQ Deployment for the Bitnami chart as a dependency, and compare what you gain (clustering, auth) against what you lose (readability).
- Add a `ServiceMonitor` and Prometheus so the HPAs can scale on request latency instead of CPU.
- Try `helm diff upgrade` (via the helm-diff plugin) before your next upgrade, and make it part of your deploy habit.

## Companion repos

- [dotnet-microservices](https://github.com/varunkonnojutech-lab/dotnet-microservices) — the app this chart deploys
- [docker-dotnet-mastery](https://github.com/varunkonnojutech-lab/docker-dotnet-mastery) — the multi-stage images the chart references
- [bicep-azure](https://github.com/varunkonnojutech-lab/bicep-azure) — provision the Azure side (APIM, Function App) with Bicep
- [terraform-azure](https://github.com/varunkonnojutech-lab/terraform-azure) — the same Azure footprint in Terraform
