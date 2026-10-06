# Tailscale Services on the tagged host; dev on host ports

Pro keeps its `https://<name>.<tailnet>.ts.net` URLs as Tailscale Services
advertised by the host's own tailscaled (`tailscale serve --service`), which
proxies to Compose ports bound to 127.0.0.1. This replaces one Tailscale
Kubernetes-operator proxy pod per hostname, which cost memory per name. A
Service host must be a tagged node, so the Pi is `tag:rpi` and no longer owned
by a user.

Tailscale allows 10 Services per tailnet, so only pro gets them (8 used). Dev
is served on ports of the host name instead:
`https://<host>.<tailnet>.ts.net:<port>`. The Services themselves and the
policy grants are created through the Tailscale API
(`scripts/tailnet-policy.sh`); the host side is `scripts/tailscale-serve.sh`.
