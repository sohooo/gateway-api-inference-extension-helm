{{- define "gateway-api-inference-extension-crds.render" -}}
{{- if .enabled }}
{{- $resource := fromYaml .source }}
{{- $metadata := get $resource "metadata" }}
{{- $annotations := default (dict) (get $metadata "annotations") }}
{{- $_ := set $annotations "helm.sh/resource-policy" "keep" }}
{{- $_ := set $metadata "annotations" $annotations }}
{{- $_ := set $resource "metadata" $metadata }}
{{ toYaml $resource }}
{{- end }}
{{- end }}
