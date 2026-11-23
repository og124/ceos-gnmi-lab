#!/bin/bash
# Subnet router for a private lab VPC: one small instance that is both
#   - the VPC's internet egress (NAT for the private subnets), and
#   - the only way in (a Tailscale subnet router for the whole VPC CIDR).
#
# Run as root at first boot (e.g. EC2 user data) on an instance in a PUBLIC
# subnet with source/destination checking DISABLED, and point the private
# subnets' default route at its network interface. No inbound security-group
# rules are needed: Tailscale connects outbound.
#
#   VPC_CIDR=10.0.0.0/16 TS_AUTHKEY=... ./subnet-router.sh
#
# Get TS_AUTHKEY from a secret store at boot rather than baking it into user
# data, e.g.:
#   TS_AUTHKEY=$(aws ssm get-parameter --name /lab/tailscale/authkey \
#                  --with-decryption --query Parameter.Value --output text)
#
# No `set -e`: one failed step shouldn't skip the rest, and SSM Session Manager
# stays available for recovery whatever happens here.
set -uo pipefail
: "${VPC_CIDR:?set VPC_CIDR}" "${TS_AUTHKEY:?set TS_AUTHKEY}"
TS_HOSTNAME=${TS_HOSTNAME:-lab-router}
TS_TAG=${TS_TAG:-tag:lab-infra}
FAILED=""

cat >/etc/sysctl.d/99-lab-nat.conf <<'SYSCTL'
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
SYSCTL
sysctl --system || FAILED="$FAILED sysctl"

dnf install -y iptables-nft || dnf install -y iptables || FAILED="$FAILED iptables"

# NAT: masquerade the VPC out of whatever interface holds the default route.
# A systemd unit so it's re-applied on every boot, not just the first.
cat >/usr/local/sbin/lab-nat.sh <<NAT
#!/bin/bash
set -euo pipefail
WAN=\$(ip route show default | awk '/default/ {print \$5; exit}')
[ -n "\$WAN" ] || { echo "lab-nat: no default route" >&2; exit 1; }
iptables -t nat -C POSTROUTING -s $VPC_CIDR -o "\$WAN" -j MASQUERADE 2>/dev/null \\
  || iptables -t nat -A POSTROUTING -s $VPC_CIDR -o "\$WAN" -j MASQUERADE
NAT
chmod +x /usr/local/sbin/lab-nat.sh
cat >/etc/systemd/system/lab-nat.service <<'UNIT'
[Unit]
Description=NAT masquerade for the lab VPC
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/lab-nat.sh

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable --now lab-nat.service || FAILED="$FAILED nat"

curl -fsSL https://tailscale.com/install.sh | sh || FAILED="$FAILED tailscale-install"
systemctl enable --now tailscaled || FAILED="$FAILED tailscaled"

# Never trace this line: `set -x` would print the auth key into the boot log,
# which on EC2 is readable through the console output API.
tailscale up \
  --authkey="$TS_AUTHKEY" \
  --advertise-routes="$VPC_CIDR" \
  --advertise-tags="$TS_TAG" \
  --hostname="$TS_HOSTNAME" \
  --accept-dns=false \
  --ssh=false || FAILED="$FAILED tailscale-up"
unset TS_AUTHKEY

if [ -n "$FAILED" ]; then echo "subnet-router: FAILED:$FAILED" >&2; exit 1; fi
echo "subnet-router: up"
