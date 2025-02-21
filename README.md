# Drowzee

A K8s operator to put deployments to sleep (scaled down), and wake them up (scaled up), according to a sleep schedule.

### Useful dev commands

```
k get CustomResourceDefinitions

k delete CustomResourceDefinition sleepschedules.drowzee.challengr.io

k apply -f manifest.yaml

k apply -f sleep_schedule.yaml

kubectl get dt --watch
```

```
helm upgrade --install ingress-nginx ingress-nginx \
  --repo https://kubernetes.github.io/ingress-nginx \
  --namespace default
```

## Sleep Schedule Status

See [Sleep Schedule Status](SleepScheduleStatus.md) for more information.
