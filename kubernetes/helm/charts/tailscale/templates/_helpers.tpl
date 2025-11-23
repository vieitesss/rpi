{{- define "tailscale.pvcName" -}}
{{- $ts := .Values.tailscale -}}
{{- $pvc := $ts.pvc | default dict -}}
{{- $pvc.name | default "tailscale-state-pvc" -}}
{{- end -}}


{{- define "tailscale.authKeyName" -}}
{{- $ts := .Values.tailscale -}}
{{- $ts.authKeyName | default "tailscale-auth" -}}
{{- end -}}


{{- define "tailscale.configName" -}}
{{- $ts := .Values.tailscale -}}
{{- $cm := $ts.cm | default dict -}}
{{ $cm.name | default "tailscale-config" }}
{{- end -}}


{{- define "tailscale.pvc" -}}
{{- $ts := .Values.tailscale -}}
{{- $tsPvc := $ts.pvc | default dict -}}
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: {{ include "tailscale.pvcName" . }}
spec:
  {{- with $tsPvc.storageClassName }}
  storageClassName: {{ . }}
  {{- end }}
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
{{- end -}}


{{- define "tailscale.configHttps" -}}
{{ $back := .Values.backendPort | default 80 }}
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ include "tailscale.configName" . }}
data:
  ts.json: |
    {
      "TCP": {
        "443": {
          "HTTPS": true
        }
      },
      "Web": {
        "${TS_CERT_DOMAIN}:443": {
          "Handlers": {
            "/": {
              "Proxy": "http://127.0.0.1:{{ $back }}"
            }
          }
        }
      },
      "AllowFunnel": {
        "${TS_CERT_DOMAIN}:443": false
      }
    }
{{- end -}}


{{- define "tailscale.volumes" -}}
- name: tailscale-config-volume
  configMap:
    name: {{ include "tailscale.configName" . }}
- name: tailscale-pvc-volume
  persistentVolumeClaim:
    claimName: {{ include "tailscale.pvcName" . }}
{{- end -}}


{{- define "tailscale.container" -}}
{{- $ts := .Values.tailscale | default dict -}}
{{- $container := $ts.container | default dict -}}
- name: {{ $container.name | default "tailscale-sidecar" }}
  imagePullPolicy: {{ $container.imagePullPolicy | default "Always" }}
  image: {{ $container.image | default "ghcr.io/tailscale/tailscale:latest" }}
  volumeMounts:
    {{- if $ts.enableHttps }}
    - name: tailscale-config-volume
      mountPath: /config
    {{- end }}
    - name: tailscale-pvc-volume
      mountPath: /var/lib/tailscale
  env:
    - name: TS_HOSTNAME
      value: {{ $ts.hostname | default "dummy-hostname" }}
    {{- if $ts.enableHttps }}
    - name: TS_SERVE_CONFIG
      value: "/config/ts.json"
    {{- end }}
    - name: TS_USERSPACE
      value: {{ $ts.userSpace | default "false" | quote }}
    - name: TS_KUBE_SECRET
      value: ""
    - name: TS_DEBUG_FIREWALL_MODE
      value: auto
    - name: TS_AUTHKEY
      valueFrom:
        secretKeyRef:
          name: {{ include "tailscale.authKeyName" . }}
          key: TS_AUTHKEY
          optional: true
    {{- with $ts.extraArgs }}
    - name: TS_EXTRA_ARGS
      value: {{ . | quote }}
    {{- end }}
  securityContext:
    capabilities:
      add:
        - NET_ADMIN
{{- end -}}
