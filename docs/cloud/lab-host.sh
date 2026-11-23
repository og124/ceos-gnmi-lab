#!/bin/bash
# Lab host: Docker + containerlab + Tailscale, advertising the containerlab
# management subnet so every switch's gNMI endpoint is dialable straight from
# your laptop.
#
# Run as root at first boot on an x86_64 instance in a PRIVATE subnet (cEOS
# images are amd64 only; an arm64 host fails with exec-format errors).
#
#   CLAB_SUBNET=172.20.20.0/24 TAILNET_CIDR=100.64.0.0/10 TS_AUTHKEY=... ./lab-host.sh
#
# Then copy this repo's lab.clab.yml + configs/ to the host, import the cEOS
# image, and `containerlab deploy`.
set -uo pipefail
: "${TS_AUTHKEY:?set TS_AUTHKEY}"
CLAB_SUBNET=${CLAB_SUBNET:-172.20.20.0/24}
TAILNET_CIDR=${TAILNET_CIDR:-100.64.0.0/10}
TS_HOSTNAME=${TS_HOSTNAME:-gnmi-lab}
TS_TAG=${TS_TAG:-tag:lab-infra}
FAILED=""

dnf install -y docker || FAILED="$FAILED docker-install"
systemctl enable --now docker || FAILED="$FAILED docker"

echo 'net.ipv4.ip_forward = 1' >/etc/sysctl.d/99-lab.conf
sysctl --system || FAILED="$FAILED sysctl"

curl -fsSL https://tailscale.com/install.sh | sh || FAILED="$FAILED tailscale-install"
systemctl enable --now tailscaled || FAILED="$FAILED tailscaled"
tailscale up \
  --authkey="$TS_AUTHKEY" \
  --advertise-routes="$CLAB_SUBNET" \
  --advertise-tags="$TS_TAG" \
  --hostname="$TS_HOSTNAME" \
  --accept-dns=false \
  --ssh=false || FAILED="$FAILED tailscale-up"
unset TS_AUTHKEY

curl -fsSL https://get.containerlab.dev | bash || FAILED="$FAILED containerlab"

# THE ONE THAT BITES: without this rule, the switches are unreachable from the
# tailnet even though everything looks healthy. See docs/cloud/README.md
# ("Why the lab host needs its own SNAT") for the full story.
cat >/usr/local/bin/lab-snat <<SNAT
#!/bin/bash
set -uo pipefail
iptables -t nat -C POSTROUTING -s $TAILNET_CIDR -d $CLAB_SUBNET -j MASQUERADE 2>/dev/null \\
  || iptables -t nat -I POSTROUTING 1 -s $TAILNET_CIDR -d $CLAB_SUBNET -j MASQUERADE
SNAT
chmod +x /usr/local/bin/lab-snat
cat >/etc/systemd/system/lab-snat.service <<'UNIT'
[Unit]
Description=SNAT tailnet traffic to the containerlab management subnet
After=docker.service tailscaled.service
Wants=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/bin/lab-snat

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable --now lab-snat.service || FAILED="$FAILED snat"

if [ -n "$FAILED" ]; then echo "lab-host: FAILED:$FAILED" >&2; exit 1; fi
echo "lab-host: ready"
