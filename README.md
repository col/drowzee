<div align="center">
  <img src="./priv/static/images/logo.png" alt="Droezee Logo" width="300">
</div>

# Drowzee

Drowzee is a K8s operator to put deployments to sleep (scaled down), and wake them up (scaled up), according to a sleep schedule.

Drowzee comes with a web interface that allows you to view sleep schedules, their current status and even manually override the schedule to wake up deployments when required. 

Drowzee also supports redirecting the ingress record of a sleeping deployment to drowzee so that users can easily manage the deployment and the sleep schedule from the same interface.


### Installation / Upgrade

```
helm repo add drowzee https://col.github.io/drowzee
helm repo update
helm upgrade --install drowzee drowzee/drowzee --namespace default -f values.yaml
```

## Configuration

Drowzee can either run in a single namespace or cluster mode. 

In single namespace mode, Drowzee will only detect sleep schedules and manage deployments in the same namespace as the Drowzee deployment.

In cluster mode, Drowzee will detect sleep schedules and manage deployments in multiple namespaces.

### Single namespace

```yaml
mode: single_namespace

app:
  host: "drowzee.dev.example.com"

secrets:
  secretKeyBase: "MSDuI5nQY0KTF2B3gjkUQeE4jDL7hkzmBhqqhXgG1pMRk7meVP8rOXW9Y1IJ1X04"

# Optional but required in order to access the Drowzee Web UI
ingress:
  enabled: true
  annotations:
    kubernetes.io/ingress.class: "nginx"
  hosts:
    - host: drowzee.dev.example.com
      paths:
        - path: /
          pathType: ImplementationSpecific
```

### Cluster mode

```yaml
mode: cluster

app:
  host: "drowzee.nonprod.example.com"
  # Use `__ALL__` to manage all namespaces
  namespaces: "dev,qa,staging"

secrets:
  secretKeyBase: "MSDuI5nQY0KTF2B3gjkUQeE4jDL7hkzmBhqqhXgG1pMRk7meVP8rOXW9Y1IJ1X04"

# Optional but required in order to access the Drowzee Web UI
ingress:
  enabled: true
  annotations:
    kubernetes.io/ingress.class: "nginx"
  hosts:
    - host: drowzee.nonprod.example.com
      paths:
        - path: /
          pathType: ImplementationSpecific
```

### Resources

Drowzee is reasonably light weight but really depends on the number of sleep schedules and the number of deployments that are being managed. `100m` CPU and `256Mi` memory is a safe starting point.

```yaml
resources:
  requests:
    cpu: 100m
    memory: 256Mi
  limits:
    cpu: 200m
    memory: 256Mi
```

### Uninstall

```
helm uninstall drowzee
```


## Sleep Schedule Status

For a description of the conditions used to determine the sleep schedule status see [Sleep Schedule Status](SleepScheduleStatus.md).

## Acknowledgements

This project was inspired by [Snorlax](https://github.com/moonbeam-nyc/snorlax). Unfortunately I had issues while trying to run Snorlax and wanted to address some of those by creating my own operator. The main areas of improvement were:
- A simplier approach to managing ingresses
  - Drowzee uses a single annotation to redirect traffic rather than re-writing the whole ingress record. 
  - The downside it that Drowzee currently only supports Nginx ingress controllers. 
- More explicit wake up
  - Snorlax immediately wakes up a deployment whenever the ingress receives a request.
  - Drowzee requires the user to click the wake up button. This avoids unexpected wakeups.
- Feature rich UI
  - Drowzee provides a much more feature rich web interface to view and manage sleep schedules.

This project makes use of the [Bonny framework](https://github.com/coryodaniel/bonny) which makes the creation of K8s operators easy using Elixir. This project would not exist without it!
