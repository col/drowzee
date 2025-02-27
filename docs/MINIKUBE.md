# Dev Setup with Minikube

## Install minikube
```bash
brew install minikube
```

## Start minikube
```bash
minikube start
```

## Install Ingress Controller Addon
```bash
minikube addons enable ingress
```

## Install Drowzee (using released version)
```bash
helm repo add drowzee https://col.github.io/drowzee
helm repo update
helm upgrade --install drowzee drowzee/drowzee \
    --namespace default -f local_values.yaml
```

## Install Drowzee (using Helm source)
```bash
# Default namespace
helm upgrade --install drowzee ./chart \
    --namespace default -f local_values.yaml

# Dev namespace
helm upgrade --install drowzee ./chart \
    --namespace dev -f local_dev_values.yaml
```

## Install Drowzee (using app source)
Build local image
```bash
docker build -t drowzee:dev .
```

Make the image is available in Minikube
```bash
# If it already exists
minikube image rm drowzee:dev

# Load the image
minikube image load drowzee:dev
```

Add image tag to `local_values.yaml`
```yaml
image:
  repository: "drowzee"
  pullPolicy: IfNotPresent
  tag: "dev"
```

Install Helm Chart
```bash
helm upgrade --install drowzee ./chart \
    --namespace default -f local_values.yaml
```

## Install an example service
```bash
helm repo add podinfo https://stefanprodan.github.io/podinfo
helm repo update
helm upgrade --install podinfo podinfo/podinfo --set ingress.enabled=true
```

## Add Host Entries
```bash
echo "$(minikube ip) drowzee.local" | sudo tee -a /etc/hosts
echo "$(minikube ip) podinfo.local" | sudo tee -a /etc/hosts
```


