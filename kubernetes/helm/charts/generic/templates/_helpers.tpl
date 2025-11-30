{{- define "generic.fullName" -}}
{{ .Release.Namespace }}-{{ .Release.Name }}
{{- end }}
