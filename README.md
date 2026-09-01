# Gateway API Inference Extension CRDs for Helm

This project packages the official `manifests.yaml` CRD bundle from
[Gateway API Inference Extension releases](https://github.com/kubernetes-sigs/gateway-api-inference-extension/releases)
as a version-matched Helm chart and publishes it to GitHub Container Registry.

[Browse all published chart versions on GitHub Packages.](https://github.com/sohooo/gateway-api-inference-extension-helm/pkgs/container/charts%2Fgateway-api-inference-extension-crds)

## Install

Choose the upstream release with Helm's chart version:

```bash
helm upgrade --install inference-extension-crds \
  oci://ghcr.io/sohooo/charts/gateway-api-inference-extension-crds \
  --version 1.6.0
```

CRD installation can be disabled with `--set crds.enabled=false`. The CRDs are
annotated with `helm.sh/resource-policy: keep`, so uninstalling the chart does
not delete CRDs or existing custom resources.

## Build locally

Helm, Ruby, and curl are required:

```bash
scripts/build-chart.sh v1.6.0
```

The chart is written to `dist/`. It contains the downloaded upstream manifest,
its source URL, and its SHA-256 checksum.

CI builds and validates the chart with pinned Helm 3 and Helm 4 releases.

## Releases

GitHub Actions checks the upstream repository every six hours and publishes one
immutable OCI chart version for every new stable upstream release, starting
with `v1.6.0`. A specific release can also be published through the manual
**Publish chart** workflow. Set the GHCR package visibility to public after its
first publication if anonymous pulls are desired.
