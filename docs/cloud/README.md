# Running the lab in the cloud, privately

The lab runs fine on any x86_64 Linux box. This is how to run it on AWS so
that it's reachable from your laptop but **not from the internet** — no public
IP on the lab, no open inbound ports anywhere, no SSH, no VPN appliance — and
so that it costs very little when you're not using it.

```
                          your laptop (Tailscale)
                                   │  WireGuard, outbound-initiated
                                   ▼
 ┌──────────────────────────── VPC 10.0.0.0/16 ─────────────────────────────┐
 │  public subnet                     private subnet (per project)           │
 │  ┌─────────────────────┐           ┌────────────────────────────────┐     │
 │  │ subnet router        │  default  │ lab host (x86_64, 8 GB)        │     │
 │  │  • NAT for the VPC   │◄──route───│  Docker + containerlab         │     │
 │  │  • advertises        │           │  advertises 172.20.20.0/24 ──► │──┐  │
 │  │    10.0.0.0/16       │           │  ┌──────┐  ┌──────┐           │  │  │
 │  └─────────┬───────────┘           │  │leaf1 │──│leaf2 │  gNMI 6030 │  │  │
 │            │ only public IP        │  └──────┘  └──────┘           │  │  │
 │            ▼                       └────────────────────────────────┘  │  │
 │        internet egress ◄── DNS Firewall allowlist (Route 53 Resolver)   │  │
 └─────────────────────────────────────────────────────────────────────────┘  │
           gnmic -a 172.20.20.11:6030 … from the laptop, directly  ◄───────────┘
```

## The pieces

**One VPC, carved per project.** A hub VPC owns all the networking; each lab
gets a private subnet. Private addresses are free, so be generous with sizes.

**A subnet router that is also the NAT.** One small instance (a `t4g.nano` is
plenty) in a public subnet does two jobs: it's the NAT for every private subnet,
and it's a [Tailscale subnet router](https://tailscale.com/kb/1019/subnets)
advertising the whole VPC. That replaces both a NAT Gateway (~$32/month before
any traffic) and a VPN. It needs source/destination checking disabled, and the
private route tables point `0.0.0.0/0` at its network interface.
[`subnet-router.sh`](subnet-router.sh) sets it up.

**Nothing listens on the internet.** Tailscale connects outbound, so the
security groups have no inbound rules at all. Shell access is AWS Systems
Manager Session Manager — no SSH, no key pairs.

**Egress allowlisting for pennies.** Route 53 Resolver DNS Firewall with an
allowlist of domains (package mirrors, Docker Hub, Tailscale's control plane,
containerlab's installer) and a catch-all rule. Start it in ALERT mode, read
the query logs, then switch the catch-all to BLOCK. AWS Network Firewall would
do this too, at roughly $280/month before allowing a single domain.

**The lab host advertises the switches.** [`lab-host.sh`](lab-host.sh) installs
Docker and containerlab and advertises the containerlab management subnet
(`172.20.20.0/24`) to the tailnet, so each switch's gNMI port is reachable from
your laptop by its own address — no jump host, no port-forwarding.

**Tailscale policy first.** Paste
[`tailscale-policy.hujson`](tailscale-policy.hujson) into the admin console
*before* either instance registers. It auto-approves both advertised routes
for a tag, and tagged devices don't expire. Register first and you'll approve
routes by hand — again after every rebuild — and an untagged server quietly
drops off the tailnet when its key expires after 180 days.

**Secrets at boot, never in user data.** Both scripts take the Tailscale auth
key from the environment; fetch it from SSM Parameter Store (SecureString) at
boot. And never run `tailscale up --authkey=…` under `set -x`: the trace lands
in the boot log, which EC2 serves to anyone with console-output access.

## Why the lab host needs its own SNAT

This one costs an evening, so it gets its own section.

Symptom: the route is advertised and approved, the lab host can reach
`172.20.20.11`, gNMI is listening — and every request from your laptop times
out. Nothing in any log.

Tailscale already masquerades subnet-route traffic, but only packets carrying
mark `0x40000`, which it sets in its `ts-forward` chain. containerlab inserts
its own ACCEPT rules into Docker's `DOCKER-USER` chain, which sits *before*
`ts-forward` in `FORWARD`. So the packet is accepted before Tailscale ever marks
it, Tailscale's MASQUERADE matches nothing, and the SYN reaches the switch with
your laptop's raw `100.x` tailnet address. cEOS has a route for its management
subnet and no default route, so it silently drops the reply.

The fix is one explicit SNAT rule for tailnet → management-subnet traffic,
re-applied on every boot (`lab-snat` in [`lab-host.sh`](lab-host.sh)). It's
matched on the destination subnet rather than the bridge interface, because
containerlab's bridge name changes whenever the lab is reconfigured. The
tempting alternative — a default route on the switches — would quietly distort
the very routing behaviour the lab exists to test.

## Sizing

- **x86_64 only.** cEOS-lab images are amd64; a Graviton host fails with
  exec-format errors.
- **~2 GB per node**, plus ~1 GB for the OS and Docker. An 8 GB instance runs
  three nodes comfortably.

## Keeping the cost down

A running 8 GB instance is the expensive part (~$65/month around the clock);
stopped, you pay only for its disk (~$3/month) and it's back in minutes with
the lab redeploying itself on boot. The router and VPC are ~$7–8/month. In
order of how much to rely on them:

1. **An idle auto-stop alarm.** A CloudWatch alarm that stops the instance
   after 4 hours under 5% CPU. Native to AWS, needs nothing else running —
   this is the real backstop.
2. **A nightly park.** A scheduled job that stops the host at 01:00. Useful,
   but if it's a GitHub Actions cron, note GitHub disables those after 60 days
   of repo inactivity.
3. **Stop/start by hand** when you're done for the day.
4. **Delete the host** (keep its image bucket) when you're done for weeks — the
   2 GB cEOS image shouldn't need re-uploading.

Keep "is it running?" out of your infrastructure-as-code. A committed
`running = true` flag gets re-asserted by every unrelated deploy, undoing the
nightly park and the auto-stop alike. Parking is an action, not a setting.

## Persistence

| Where a change lives | Survives stop/start | Survives deleting the host |
|---|---|---|
| `configs/*.partial.cfg` in this repo | yes | yes |
| `make save` (on the host's disk) | yes | no |
| typed into a switch, not saved | no | no |

Deploy on boot *without* `--reconfigure`, so the middle row holds: a
reconfigure-on-boot discards a day's saved work while logging a perfectly
healthy deploy.
