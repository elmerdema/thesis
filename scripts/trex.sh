#!/bin/bash

cd ../../../opt/trex/v3.04
sudo ./t-rex-64 -i -c 24

# nano /etc/trex_cfg.yaml
# interfaces: ['17:00.0', '17:00.1','31:00.0', '31:00.1']