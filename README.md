# Raspberry Pi Homelab

## Documentation

- [README.md](./system/README.md) in the `system` directory that shows how to set up the services.
- [This post](https://vieitesss.github.io/posts/Deploy-services-with-Tailscale-sidecar/) on how to configure Tailscale and run the Docker Compose version of the services.

## Prerequisites

- Docker
- Docker Compose
- Tailscale account

## Configuration

### Required

Set the environment variables in the `.env` file.

```bash
cp example.env .env
```

### Optional

> [!WARNING]
> If you are not going to use or don't have a B2 backup configured, remove any usage in the docker-compose file of the environment variables that are set in the `backup.env.example` configuration file.

Set the environment variables in the `.backup.env` file.

```bash
cp backup.env.example .backup.env
```
