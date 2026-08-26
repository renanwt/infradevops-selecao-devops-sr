{{- define "comments-api.name" -}}
{{- .Chart.Name -}}
{{- end -}}

{{- define "comments-api.fullname" -}}
{{- if contains .Chart.Name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "comments-api.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
app.kubernetes.io/name: {{ include "comments-api.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Values.image.tag | default .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "comments-api.selectorLabels" -}}
app.kubernetes.io/name: {{ include "comments-api.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "comments-api.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- include "comments-api.fullname" . -}}
{{- else -}}
default
{{- end -}}
{{- end -}}

{{- define "comments-api.image" -}}
{{- required "image.tag e obrigatorio (ex.: sha-abc1234)" .Values.image.tag | printf "%s:%s" .Values.image.repository -}}
{{- end -}}

{{- define "comments-api.dbSecretName" -}}
{{- include "comments-api.fullname" . }}-db
{{- end -}}

{{/* securityContext do container: compativel com PSS restricted */}}
{{- define "comments-api.containerSecurityContext" -}}
allowPrivilegeEscalation: false
readOnlyRootFilesystem: true
runAsNonRoot: true
runAsUser: 10001
runAsGroup: 10001
capabilities:
  drop: ["ALL"]
seccompProfile:
  type: RuntimeDefault
{{- end -}}
