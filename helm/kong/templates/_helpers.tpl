{{/* vim: set filetype=mustache: */}}
{{/*
Expand the name of the chart.
*/}}

{{/*
Create a default fy qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "kong.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}


{{/*
Selector labels
*/}}
{{- define "kong.podSelectorLabels" -}}
app: {{ .Release.Name }}
helm/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end }}

{{- define "kong.deploymentSelectorLabels" -}}
app: {{ .Release.Name }}
{{- end }}


{{- define "kong.defaultEnvVars" -}}
{{- end }}


{{- define "kong.imageURL" -}}
image: "{{ $.Values.deployment.template.containers.spec.repositoryUrl }}/{{ $.Release.Namespace }}:{{ $.Values.deployment.template.containers.spec.image }}"
{{- end }}

{{- define "kong.healthCheckExec" -}}
{{ with .healthcheck }}
livenessProbe:
  exec:
    {{- with .exec.command }}
    command:
    {{ toYaml . | nindent 4 }}
    {{- end }}
  initialDelaySeconds: {{ .initialDelaySeconds }}
  timeoutSeconds: {{ .timeoutSeconds }}
  failureThreshold: {{ .failureThreshold }}
readinessProbe:
  exec:
    {{- with .exec.command }}
    command:
    {{ toYaml . | nindent 4 }}
    {{- end }}
  initialDelaySeconds: {{ .initialDelaySeconds }}
  timeoutSeconds: {{ .timeoutSeconds }}
  failureThreshold: {{ .failureThreshold }}
{{ end }}
{{- end }}


{{- define "kong.healthCheck" -}}
{{ with .healthcheck }}
livenessProbe:
  httpGet:
    path: {{ .path }}
    port: {{ .port }} 
  initialDelaySeconds: {{ .initialDelaySeconds }}
  timeoutSeconds: {{ .timeoutSeconds }}
  failureThreshold: {{ .failureThreshold }}
readinessProbe:
  httpGet:
    path: {{ .path }}
    port: {{ .port }}
  initialDelaySeconds: {{ .initialDelaySeconds }}
  timeoutSeconds: {{ .timeoutSeconds }}
  failureThreshold: {{ .failureThreshold }}
{{ end }}
{{- end }}
