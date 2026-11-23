# cEOS gNMI lab

Two Arista cEOS switches under [containerlab](https://containerlab.dev), with
gNMI on port 6030, ready to poke with [gnmic](https://gnmic.openconfig.net).
Small on purpose: a working base for streaming-telemetry and model-driven
config experiments that you can grow node by node.

```
   leaf1 ─── Ethernet1 ── 10.10.10.0/30 ── Ethernet1 ─── leaf2
 172.20.20.11:6030                                  172.20.20.12:6030
```

And a write-up of [running it in the cloud privately](docs/cloud/README.md):
reachable from your laptop over Tailscale, unreachable from the internet, no
open ports, and cheap when it's idle.

## Quick start

You need an **x86_64** Linux host with Docker, containerlab and gnmic, and
~2 GB of RAM per switch.

1. **Get cEOS.** cEOS-lab is free but sits behind an arista.com account, so it
   isn't in this repo. Download `cEOS-lab-<version>.tar.xz` (the 32-bit build
   uses less memory), then import it:

   ```console
   $ make import IMAGE=cEOS-lab-4.34.8M.tar.xz VERSION=4.34.8M
   ```

   If you import a different version, match the `image:` tag in
   [`lab.clab.yml`](lab.clab.yml).

2. **Deploy.**

   ```console
   $ make deploy
   ```

3. **Talk gNMI.**

   ```console
   $ gnmic -a 172.20.20.11:6030 --insecure -u admin -p admin capabilities
   ```

   or both switches at once, using [`gnmic/gnmic.yaml`](gnmic/gnmic.yaml):

   ```console
   $ gnmic --config gnmic/gnmic.yaml get --path /system/state/hostname
   ```

[`gnmic/examples.sh`](gnmic/examples.sh) is a short tour: capabilities,
OpenConfig `get`s for hostname, link state and addresses, then a streaming
subscription to interface counters.

## Layout

| File | What it is |
|---|---|
| [`lab.clab.yml`](lab.clab.yml) | Nodes and cabling. `eth1` is `Ethernet1` in EOS; `eth0` is management and never appears in `links`. |
| [`configs/<node>.partial.cfg`](configs) | What goes *on* the interfaces: addresses, descriptions, protocols. |
| [`gnmic/`](gnmic) | gnmic target config and the example tour. |
| [`docs/cloud/`](docs/cloud) | The private-cloud design, plus generic setup scripts for the subnet router and lab host, and a Tailscale policy. |

## Things that will bite you

- **Configs are `.partial` for a reason.** containerlab's default
  startup-config for cEOS is what enables gNMI. A plain `startup-config:`
  *replaces* it — gNMI silently disappears and nothing in the logs says why. A
  `.partial` is merged onto the default instead. The configs here also repeat
  the gNMI stanza, so they work either way.
- **x86_64 only.** cEOS-lab is amd64; ARM hosts (Apple Silicon VMs, Graviton)
  fail with exec-format errors.
- **Memory is the ceiling.** Budget ~2 GB per node and ~1 GB for the host. An
  8 GB box runs three nodes comfortably.
- **`admin`/`admin`, no TLS.** Lab defaults. Fine on a laptop or a private
  network, never on anything reachable from the internet.

## Operating

```
make deploy      # bring the lab up
make redeploy    # re-apply lab.clab.yml + configs/, discarding live changes
make save        # persist live switch configs across container restarts
make inspect     # what's running, and where
make destroy     # tear it down
```

## Licence

MIT. cEOS itself is Arista's, under Arista's licence, and isn't distributed
here.
