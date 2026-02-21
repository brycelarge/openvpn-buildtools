# openvpn-buildtools

A file-only repository containing **OpenVPN + Privoxy** s6-overlay service definitions, provider config scripts, and helper scripts. Consumed by downstream Docker images via `git clone` at build time — no Docker image is published.


## Downstream projects

| Project | Image |
|---|---|
| [brycelarge/tuliprox-vpn](https://github.com/brycelarge/tuliprox-vpn) | `ghcr.io/brycelarge/tuliprox-vpn` |
| [brycelarge/m3u-manager](https://github.com/brycelarge/m3u-manager) | `ghcr.io/brycelarge/m3u-manager` |


## How downstream images consume this repo

In the downstream `Dockerfile`, during the final stage:

```dockerfile
ARG OPENVPN_TOOLS_REF=main

RUN apk add --no-cache git && \
    git clone --depth 1 --branch "${OPENVPN_TOOLS_REF}" \
        https://github.com/brycelarge/openvpn-buildtools.git /tmp/openvpn-buildtools && \
    cp -r /tmp/openvpn-buildtools/root/. / && \
    cp -r /tmp/openvpn-buildtools/scripts/. /scripts/ && \
    rm -rf /tmp/openvpn-buildtools
```

Pin to a specific tag for reproducible builds:

```dockerfile
ARG OPENVPN_TOOLS_REF=v1.0.0
```


## What's included

- Provider config download scripts: **PIA**, **NordVPN**, **Surfshark**, **IPVanish**, **VyprVPN**, **ProtonVPN**, **Custom**
- s6-overlay service definitions:
  - `init-openvpn-config` — downloads provider configs, sets up credentials, adds `LOCAL_NETWORK` routes
  - `svc-openvpn` — runs the OpenVPN daemon with sensible defaults
  - `init-privoxy-config` — configures Privoxy listen address
  - `svc-privoxy` — runs Privoxy (only when `PRIVOXY_ENABLED=true`)
- Helper scripts in `/scripts/`:
  - `openvpn-config-validation.sh` — resolves and validates the `.ovpn` config + auth file
  - `openvpn-config-clean.sh` — normalises `.ovpn` files (line endings, deprecated options)
  - `vpntest.sh` — quick VPN connectivity check (IP, DNS, routing)
  - `speedtest.sh` — runs `speedtest-cli` or falls back to `iperf3`
  - `logging.sh` — shared `log` / `debug_log` helpers
  - `dos2unix.sh` — CRLF → LF conversion


## Environment variables

| Variable | Default | Description |
|---|---|---|
| `VPN_ENABLED` | `false` | Set `true` to enable OpenVPN |
| `VPN_DIR` | `/app/config/openvpn` | Where `.ovpn` configs and credentials are stored. Override in downstream images that use a different data path. |
| `OPENVPN_PROVIDER` | `CUSTOM` | `CUSTOM`, `PIA`, `SURFSHARK`, `IPVANISH`, `NORDVPN`, `VYPRVPN`, `PROTONVPN` |
| `OPENVPN_CONFIG` | _(first `.ovpn` found)_ | Specific config filename (with or without `.ovpn`) |
| `OPENVPN_PROTOCOL` | `udp` | `udp` or `tcp` |
| `OPENVPN_USERNAME` | | VPN username — written to credentials file at startup |
| `OPENVPN_PASSWORD` | | VPN password — written to credentials file at startup |
| `OPENVPN_OPTIONS` | | Extra openvpn CLI flags appended verbatim |
| `OPENVPN_FORCE_UPDATE` | `false` | Set `true` to delete and re-download provider configs on next start |
| `NAME_SERVERS` | | Comma-separated DNS servers — overwrites `/etc/resolv.conf` |
| `LOCAL_NETWORK` | | ⚠️ Comma-separated CIDRs to route **outside** the tunnel. Required to keep LAN/UI ports reachable when VPN is up. |
| `PRIVOXY_ENABLED` | `false` | Enable Privoxy HTTP proxy (requires `VPN_ENABLED=true`) |
| `PRIVOXY_PORT` | `8118` | Privoxy listen port |
| `PRIVOXY_STARTUP_DELAY_SECS` | `30` | Seconds to wait for `tun0` before starting Privoxy |
| `VPN_LOG_DIR` | `/app/config/logs/openvpn` | OpenVPN log directory |
| `PRIVOXY_LOG_DIR` | `/app/config/logs/privoxy` | Privoxy log directory |
| `DEBUG` | `false` | Verbose logging |


## Required Docker flags

When `VPN_ENABLED=true` the container needs:

```yaml
cap_add:
  - NET_ADMIN
devices:
  - /dev/net/tun
```


## Integrating into a downstream image

The final image must be based on `brycelarge/alpine-baseimage` (which provides s6-overlay) and must install `openvpn` + `privoxy` via `apk` (dynamically linked — only scripts/configs come from this repo).

```dockerfile
ARG OPENVPN_TOOLS_REF=main

FROM brycelarge/alpine-baseimage:3.21

RUN apk add --no-cache git openvpn privoxy iproute2 iptables jq moreutils dos2unix && \
    git clone --depth 1 --branch "${OPENVPN_TOOLS_REF}" \
        https://github.com/brycelarge/openvpn-buildtools.git /tmp/openvpn-buildtools && \
    cp -r /tmp/openvpn-buildtools/root/. / && \
    cp -r /tmp/openvpn-buildtools/scripts/. /scripts/ && \
    rm -rf /tmp/openvpn-buildtools
```

Register the services in your `user` bundle (`root/etc/s6-overlay/s6-rc.d/user/contents.d/`):

```
init-openvpn-config
svc-openvpn
init-privoxy-config
svc-privoxy
```

If your data path differs from `/app/config/openvpn`, set `VPN_DIR` in your environment:

```yaml
environment:
  - VPN_DIR=/data/config/openvpn
```


## Provider setup

### Custom `.ovpn`

Mount your `.ovpn` file(s) into `$VPN_DIR` (default `/app/config/openvpn`):

```yaml
volumes:
  - ./data/config/openvpn:/app/config/openvpn
environment:
  - VPN_ENABLED=true
  - OPENVPN_PROVIDER=CUSTOM
  - OPENVPN_CONFIG=my-server.ovpn
  - OPENVPN_USERNAME=user
  - OPENVPN_PASSWORD=pass
```

### Built-in providers (NordVPN, PIA, Surfshark, etc.)

Configs are downloaded automatically on first start into `$VPN_DIR/<provider>/` and cached across restarts.

```yaml
environment:
  - VPN_ENABLED=true
  - OPENVPN_PROVIDER=NORDVPN
  - OPENVPN_CONFIG=us9196.nordvpn.com.udp
  - OPENVPN_USERNAME=your_service_user
  - OPENVPN_PASSWORD=your_service_pass
  - LOCAL_NETWORK=192.168.1.0/24
```

For NordVPN, service credentials (not your account password) are at:
https://my.nordaccount.com/dashboard/nordvpn/manual-configuration/

#### Force re-download of provider configs

```yaml
- OPENVPN_FORCE_UPDATE=true
```

Or delete the cached directory and restart:

```sh
rm -rf ./data/config/openvpn/nordvpn
docker compose restart
```

### Surfshark friendly-name mapping

```sh
docker exec <container> /etc/openvpn/surfshark/map.sh
```

Writes `$VPN_DIR/surfshark_map.json`. Then `OPENVPN_CONFIG` can be a friendly key like `za_johannesburg`.


## LOCAL_NETWORK — keeping your UI reachable

When OpenVPN connects it takes over the default route. Without `LOCAL_NETWORK`, all traffic (including your app's port) goes through the tunnel and your host can no longer reach the container.

```yaml
- LOCAL_NETWORK=192.168.1.0/24
```

Multiple subnets:

```yaml
- LOCAL_NETWORK=192.168.1.0/24,10.0.0.0/8
```


## Privoxy

An optional HTTP proxy that routes traffic through the VPN tunnel. Only starts when both `VPN_ENABLED=true` and `PRIVOXY_ENABLED=true`.

```yaml
- PRIVOXY_ENABLED=true
- PRIVOXY_PORT=8118
```

Expose the port:

```yaml
ports:
  - "8118:8118"
```


## Logs

All services log via `s6-log` with rotation (20 files × 1 MB). Log directories are created at runtime — mount your data volume to persist them.

| Service | Env var | Default path |
|---|---|---|
| OpenVPN | `VPN_LOG_DIR` | `/app/config/logs/openvpn` |
| Privoxy | `PRIVOXY_LOG_DIR` | `/app/config/logs/privoxy` |


## Testing VPN inside a container

```bash
docker exec <container> /scripts/vpntest.sh
```

Checks: tun0 interface, public IP, country/ASN, DNS resolution, default route, and optionally runs a speed test.


## Contributing

Changes to scripts or s6 service definitions here automatically flow into all downstream images on their next build — no per-project changes needed. When adding a new provider:

1. Add `root/etc/openvpn/<provider>/update.sh`
2. Handle the provider in `scripts/openvpn-config-validation.sh` and `root/etc/s6-overlay/s6-rc.d/init-openvpn-config/run`
