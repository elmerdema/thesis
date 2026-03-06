"""
Insert Forward Table Entries
============================
This script inserts entries into the forward table for the Marina Reporter P4 program.

Physical Topology:
  TRex Port 0 (10:70:fd:30:80:d0) --> Arista --> Tofino Port 23 (Logical 8, MAC D0:77:CE:2B:20:50)
  Tofino Port 24 (Logical 16, MAC D0:77:CE:2B:20:54) --> Arista --> TRex Port 1 (10:70:fd:30:80:d1)
"""

import sys
import glob
import os

# =============================================================================
# CONFIGURATION
# =============================================================================

# Tofino logical port numbers (from bf_shell "pm show" D_P column)
TOFINO_EGRESS_PORT = 16    # Logical port 16 (Physical 24) - sends to TRex

# Tofino port MACs
TOFINO_EGRESS_MAC = "D0:77:CE:2B:20:54"  # Port 24 / Logical 16

# TRex interface MACs
TREX_RX_MAC = "10:70:fd:30:80:d1"  # TRex Port 1 (RX from Tofino)

# Traffic IPs
TRAFFIC_DST_IP = "192.168.100.1"

# =============================================================================
# BF Runtime gRPC setup
# =============================================================================
sde_install = os.environ.get('SDE_INSTALL', '/usr/local/sde')
bfrt_location = '{}/lib/python*/site-packages/tofino'.format(sde_install)

try:
    found_paths = glob.glob(bfrt_location)
    if found_paths:
        sys.path.append(found_paths[0])
    else:
        print(f"WARNING: Could not find SDE python libraries at {bfrt_location}")
    import bfrt_grpc.client as gc
except ImportError as e:
    print(f"CRITICAL: Could not import bfrt_grpc. Error: {e}")
    print(f"SDE_INSTALL: {sde_install}")
    sys.exit(1)


def mac_to_bytes(mac_str):
    """Convert MAC string like 'AA:BB:CC:DD:EE:FF' to bytearray."""
    return bytearray(int(x, 16) for x in mac_str.split(':'))


def main():
    print("=" * 60)
    print("Insert Forward Table Entries")
    print("=" * 60)

    print("\nConnecting to BFRT Server (localhost:50052)...")
    try:
        interface = gc.ClientInterface('localhost:50052', client_id=0, device_id=0)
    except Exception as e:
        print(f"Connection failed: {e}")
        return

    try:
        interface.bind_pipeline_config('p4_marina_reporter')
    except Exception as e:
        print(f"WARNING: bind_pipeline_config failed: {e}")

    bfrt_info = interface.bfrt_info_get('p4_marina_reporter')

    # Target for P4 tables (all pipes)
    target = gc.Target(device_id=0, pipe_id=0xffff)

    # =========================================================================
    # Get Forward Table
    # =========================================================================
    tbl_forward = bfrt_info.table_get('SwitchIngress.tbl_forward')

    # Resolve action name (varies by SDE version / P4 compilation)
    try:
        action_forward = next(iter(tbl_forward.info.action_dict.keys()))
    except Exception:
        print("CRITICAL: Could not resolve action name for forward table.")
        return

    # =========================================================================
    # Insert Forward Table Entry
    # =========================================================================
    print("Inserting Forwarding Table Entry...")
    tbl_forward.entry_add(
        target,
        [tbl_forward.make_key([
            gc.KeyTuple('hdr.ipv4.dstAddr', gc.ipv4_to_bytes(TRAFFIC_DST_IP), prefix_len=32)
        ])],
        [tbl_forward.make_data([
            gc.DataTuple('port', TOFINO_EGRESS_PORT),
            gc.DataTuple('dst_mac', mac_to_bytes(TREX_RX_MAC)),
            gc.DataTuple('src_mac', mac_to_bytes(TOFINO_EGRESS_MAC)),
        ], action_forward)]
    )
    print(f"  {TRAFFIC_DST_IP}/32 -> port {TOFINO_EGRESS_PORT} "
          f"(dst={TREX_RX_MAC}, src={TOFINO_EGRESS_MAC})")

    print("\n" + "=" * 60)
    print("FORWARD TABLE ENTRY INSERTED")
    print("=" * 60)


if __name__ == "__main__":
    main()