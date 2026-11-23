#!/usr/bin/env bash
# A tour of gNMI against the lab. Run after `make deploy`; each step prints
# what it's about to do. Ctrl-C ends the final subscription.
set -euo pipefail
cd "$(dirname "$0")"
g() { echo; echo "\$ gnmic $*"; gnmic --config gnmic.yaml "$@"; }

# What the switches support: gNMI version, encodings, OpenConfig models.
g capabilities

# One-shot reads of OpenConfig state.
g get --path /system/state/hostname
g get --path '/interfaces/interface[name=Ethernet1]/state/oper-status'
g get --path '/interfaces/interface[name=Ethernet1]/subinterfaces/subinterface[index=0]/ipv4/addresses'

# Streaming telemetry: interface counters every 10 seconds.
g subscribe --path '/interfaces/interface[name=Ethernet1]/state/counters' \
  --mode stream --stream-mode sample --sample-interval 10s
