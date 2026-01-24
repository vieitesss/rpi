{{/*
Validation: Ensure appName is set
*/}}
{{- define "restic-backup.validateAppName" -}}
{{- if not .Values.repository.appName }}
{{- fail "ERROR: repository.appName is required. Please set it in your values file (e.g., appName: \"vaultwarden\")" }}
{{- end }}
{{- end }}
