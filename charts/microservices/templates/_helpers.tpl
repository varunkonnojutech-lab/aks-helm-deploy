{{/*
Common labels for every object the chart creates.
*/}}
{{- define "microservices.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: {{ .Release.Name }}
{{- end }}

{{/*
Selector labels — these must never change for a released object, or
Kubernetes will refuse the update.
*/}}
{{- define "microservices.selectorLabels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Labels for one component, e.g. (dict "root" . "component" "catalog").
*/}}
{{- define "microservices.componentLabels" -}}
{{ include "microservices.labels" .root }}
app.kubernetes.io/component: {{ .component }}
{{- end }}

{{- define "microservices.componentSelectorLabels" -}}
{{ include "microservices.selectorLabels" .root }}
app.kubernetes.io/component: {{ .component }}
{{- end }}

{{/*
Full image reference, honouring global.imageRegistry when set.
Usage: {{ include "microservices.image" (dict "root" . "image" .Values.catalog.image) }}
*/}}
{{- define "microservices.image" -}}
{{- if .root.Values.global.imageRegistry -}}
{{ printf "%s/%s:%s" .root.Values.global.imageRegistry .image.repository .image.tag }}
{{- else -}}
{{ printf "%s:%s" .image.repository .image.tag }}
{{- end -}}
{{- end }}

{{/*
Object name: <release>-<component>, e.g. shop-catalog.
*/}}
{{- define "microservices.fullname" -}}
{{ printf "%s-%s" .root.Release.Name .component }}
{{- end }}
