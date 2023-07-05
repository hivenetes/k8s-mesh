#!/bin/bash

# To cleanup the multicluster control plane, you can run:
linkerd --context=west multicluster unlink --cluster-name east | \
  kubectl --context=west delete -f -

for ctx in west east; do \
  kubectl --context=${ctx} delete ns emojivoto; \
  linkerd --context=${ctx} multicluster uninstall | kubectl --context=${ctx} delete -f - ; \
done

# If you’d also like to remove your Linkerd installation, run:
for ctx in west east; do
  linkerd --context=${ctx} viz uninstall | kubectl --context=${ctx} delete -f -
  linkerd --context=${ctx} uninstall | kubectl --context=${ctx} delete -f -
done