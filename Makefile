SHELL := /bin/bash
TOPO  := lab.clab.yml
CLAB  := sudo containerlab

.PHONY: import deploy redeploy destroy inspect save endpoints capabilities

# cEOS-lab is free but gated behind an arista.com account, so it isn't in this
# repo. Download cEOS-lab-<version>.tar.xz (the 32-bit build), then:
#   make import IMAGE=cEOS-lab-4.34.8M.tar.xz VERSION=4.34.8M
import:
	@test -n "$(IMAGE)" -a -n "$(VERSION)" || { echo "usage: make import IMAGE=cEOS-lab-<v>.tar.xz VERSION=<v>"; exit 1; }
	docker import $(IMAGE) ceos:$(VERSION)

deploy:
	$(CLAB) deploy -t $(TOPO)

# Re-apply the topology and configs from this repo, discarding live changes.
redeploy:
	$(CLAB) deploy -t $(TOPO) --reconfigure

destroy:
	$(CLAB) destroy -t $(TOPO) --cleanup

inspect:
	$(CLAB) inspect -t $(TOPO)

# Write each switch's running-config to its startup-config inside the lab
# directory, so live changes survive a container restart (not a --reconfigure).
save:
	$(CLAB) save -t $(TOPO)

endpoints:
	@echo "leaf1  172.20.20.11:6030"
	@echo "leaf2  172.20.20.12:6030"
	@echo
	@echo "gnmic --config gnmic/gnmic.yaml capabilities"

capabilities:
	gnmic --config gnmic/gnmic.yaml capabilities
