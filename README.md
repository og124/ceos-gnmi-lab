# cEOS gNMI lab

Two Arista cEOS switches under [containerlab](https://containerlab.dev), with
gNMI on port 6030 via [gnmic](https://gnmic.openconfig.net).

```
   leaf1 ─── Ethernet1 ── 10.10.10.0/30 ── Ethernet1 ─── leaf2
 172.20.20.11:6030                                  172.20.20.12:6030
```

And a write-up of [running it in the cloud privately](docs/cloud/README.md):
reachable from your laptop over Tailscale.

## Quick start

You need an **x86_64** Linux host with Docker, containerlab and gnmic, and
~2 GB of RAM per switch.

1. **Get cEOS.** Download `cEOS-lab-<version>.tar.xz`, then import it:

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

## Layout

| File | What it is |
|---|---|
| [`lab.clab.yml`](lab.clab.yml) | Nodes and cabling. `eth1` is `Ethernet1` in EOS; `eth0` is management and never appears in `links`. |
| [`configs/<node>.partial.cfg`](configs) | What goes *on* the interfaces: addresses, descriptions, protocols. |
| [`gnmic/`](gnmic) | gnmic target config and the example tour. |
| [`docs/cloud/`](docs/cloud) | The private-cloud design, plus generic setup scripts for the subnet router and lab host, and a Tailscale policy. |

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
