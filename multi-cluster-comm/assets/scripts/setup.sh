#!/bin/bash

## IMPORTANT: Check prerequsites.sh into install the cli tooling

# Create DigitalOcean Kubernetes(DOKS) Clusters in lon1(west)
doctl kubernetes cluster create west --region lon1 --count 3 --size s-8vcpu-16gb
doctl kubernetes cluster kubeconfig save <cluster-id>
# Rename the context just for ease of demo
kubectl config rename-context do-lon1-west west

# Create DigitalOcean Kubernetes(DOKS) Clusters in ams3(east)
doctl kubernetes cluster create east --region ams3 --count 3 --size s-8vcpu-16gb
doctl kubernetes cluster kubeconfig save <cluster-id>
# Rename the cluster context just for ease of demo
kubectl config rename-context do-ams3-east east

# Linkerd requires a shared trust anchor to exist between the installations in all clusters 
# that communicate with each other. This is used to encrypt the traffic between clusters and authorize 
# requests that reach the gateway so that your cluster is not open to the public internet.
# For more details: https://linkerd.io/2.13/tasks/generate-certificates/#trust-anchor-certificate

# Generate trust anchor root certificate and key
step certificate create root.linkerd.cluster.local root.crt root.key \
  --profile root-ca --no-password --insecure

# The trust anchor that we’ve generated is a self-signed certificate 
# which can be used to create new certificates (a certificate authority). 
# Generate the issuer credentials using the trust anchor.
step certificate create identity.linkerd.cluster.local issuer.crt issuer.key \
  --profile intermediate-ca --not-after 8760h --no-password --insecure \
  --ca root.crt --ca-key root.key

# Install Linkerd CRDs on both clusters
linkerd install --crds | tee \
    >(kubectl --context=west apply -f -) \
    >(kubectl --context=east apply -f -)

# Install Linkerd with identity configuration on both clusters
linkerd install \
  --identity-trust-anchors-file root.crt \
  --identity-issuer-certificate-file issuer.crt \
  --identity-issuer-key-file issuer.key \
  | tee \
    >(kubectl --context=west apply -f -) \
    >(kubectl --context=east apply -f -)

# Install multicluster components on both clusters linkerd-viz extension
# on both the clusters
for ctx in west east; do
  linkerd --context=${ctx} multicluster install | \
  kubectl --context=${ctx} apply -f - || break
  linkerd --context=${ctx} viz install | \
  kubectl --context=${ctx} apply -f - || break
done

# Link west cluster to east cluster
linkerd --context=east multicluster link --cluster-name east | \
kubectl --context=west apply -f -

# Install emojivoto microservice application
for ctx in west east; do
  echo "Adding emojivoto services on cluster: ${ctx} ........."
  kubectl config use-context ${ctx}
  linkerd inject https://run.linkerd.io/emojivoto.yml | kubectl apply -f -
  echo "-------------"
done

# Delete certain deployments and services in the west cluster(for demo purpose)
kubectl --context=west -n emojivoto delete deploy voting web emoji
kubectl --context=west -n emojivoto delete svc voting-svc web-svc emoji-svc

# Delete certain deployments in the east cluster(for demo purpose) and 
kubectl --context=east -n emojivoto delete deploy vote-bot

# Label web-svc for service-mirroring
# for more details: https://linkerd.io/2020/02/25/multicluster-kubernetes-with-service-mirroring/
kubectl --context=east label svc -n emojivoto web-svc mirror.linkerd.io/exported=true

# Get endpoint IP of web-svc-east in the west cluster
kubectl --context=west -n emojivoto get endpoints web-svc-east \
  -o 'custom-columns=ENDPOINT_IP:.subsets[*].addresses[*].ip'

# Get the IP of the linkerd-gateway service in the east cluster
kubectl --context=east -n linkerd-multicluster get svc linkerd-gateway \
  -o "custom-columns=GATEWAY_IP:.status.loadBalancer.ingress[*].ip"

# To verify `mTLS`:

```bash
linkerd --context=west -n emojivoto viz tap deploy/vote-bot | \
  grep "$(kubectl --context=east -n linkerd-multicluster get svc linkerd-gateway \
    -o "custom-columns=GATEWAY_IP:.status.loadBalancer.ingress[*].ip")"
```

# Apply curl deployment (optional)
kubectl --context=west apply -f curl-deployment.yml

# Retrieve the clusterIP of `web-svc-east`
kubectl --context=west -n emojivoto get svc web-svc-east -o=jsonpath='{.spec.clusterIP}' && echo

# Edit vote-bot deployment in the west cluster to point to web-svc-east
# Replace <clusterIP> with the IP obtained from the previous command
kubectl set env deployment/vote-bot -n emojivoto WEB_HOST=<clusterIP>:80 --context west

# Open and inspect Linkerd dashboards
linkerd viz dashboard --context west --port 50750 &
linkerd viz dashboard --context east --port 50760 &

# Deny traffic to the east cluster (demo)
linkerd --context=east upgrade --default-inbound-policy deny | kubectl apply -f -
# Allow cluster-authenticated access to the east cluster
linkerd --context=east upgrade --default-inbound-policy cluster-authenticated | kubectl apply -f -
