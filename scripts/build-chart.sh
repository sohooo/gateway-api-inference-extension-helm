#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/build-chart.sh VERSION [OUTPUT_DIRECTORY]

Build a Helm chart from an upstream Gateway API Inference Extension release.
VERSION may be written as 1.6.0 or v1.6.0. Set MANIFEST_FILE to use an
already-downloaded manifest instead of fetching the GitHub release asset.
EOF
}

if [[ ${1:-} == "-h" || ${1:-} == "--help" ]]; then
  usage
  exit 0
fi

if [[ $# -lt 1 || $# -gt 2 ]]; then
  usage >&2
  exit 2
fi

for command in curl helm ruby; do
  if ! command -v "${command}" >/dev/null 2>&1; then
    echo "Required command not found: ${command}" >&2
    exit 1
  fi
done

input_version=$1
chart_version=${input_version#v}
upstream_version="v${chart_version}"

if [[ ! ${chart_version} =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]]; then
  echo "Invalid release version: ${input_version}" >&2
  exit 2
fi

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repository_root=$(cd -- "${script_directory}/.." && pwd)
chart_source="${repository_root}/charts/gateway-api-inference-extension-crds"
output_directory=${2:-"${repository_root}/dist"}
mkdir -p "${output_directory}"
output_directory=$(cd -- "${output_directory}" && pwd)

temporary_directory=$(mktemp -d)
trap 'rm -rf -- "${temporary_directory}"' EXIT

staged_chart="${temporary_directory}/gateway-api-inference-extension-crds"
mkdir -p "${staged_chart}/files"
cp -R "${chart_source}/." "${staged_chart}/"

manifest="${staged_chart}/files/manifests.yaml"
source_repository=${UPSTREAM_REPOSITORY:-kubernetes-sigs/gateway-api-inference-extension}
source_url="https://github.com/${source_repository}/releases/download/${upstream_version}/manifests.yaml"

if [[ -n ${MANIFEST_FILE:-} ]]; then
  cp -- "${MANIFEST_FILE}" "${manifest}"
else
  echo "Downloading ${source_url}"
  curl --fail --location --silent --show-error \
    --retry 5 --retry-all-errors --retry-delay 2 \
    --output "${manifest}" "${source_url}"
fi

"${script_directory}/validate_manifest.rb" \
  --expected-version "${upstream_version}" \
  "${manifest}"

"${script_directory}/split_manifest.rb" "${manifest}" "${staged_chart}"

if command -v sha256sum >/dev/null 2>&1; then
  manifest_checksum=$(sha256sum "${manifest}" | awk '{print $1}')
else
  manifest_checksum=$(shasum -a 256 "${manifest}" | awk '{print $1}')
fi

printf '%s  %s\n' "${manifest_checksum}" "manifests.yaml" >"${staged_chart}/files/manifests.yaml.sha256"
printf '%s\n' "${source_url}" >"${staged_chart}/files/manifests.yaml.url"

helm lint "${staged_chart}"

rendered_manifest="${temporary_directory}/rendered.yaml"
helm template validation "${staged_chart}" --include-crds >"${rendered_manifest}"
"${script_directory}/validate_manifest.rb" \
  --compare-to "${manifest}" \
  "${rendered_manifest}"

helm package "${staged_chart}" \
  --destination "${output_directory}" \
  --version "${chart_version}" \
  --app-version "${upstream_version}"

echo "Upstream SHA-256: ${manifest_checksum}"
