{{- define "vaultwarden.fullName" -}}
{{ .Release.Namespace }}-{{ .Chart.Name }}
{{- end -}}
