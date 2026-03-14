#!/usr/bin/env python3
"""
Marina Reporter Deploy Script (Fixed)
======================================
Deploys table entries and mirror config to Tofino for Marina Reporter P4 program.

Fixes applied:
  - Forward table now includes dst_mac and src_mac (required by P4 action)
  - Removed 192.168.100.2 from forward table (was causing packet loop on port 24)
  - Mirror session direction changed from BOTH to INGRESS (only I2E needed)

Physical Topology:
  TRex Port 0 (10:70:fd:30:80:d0) --> Arista --> Tofino Port 23 (Logical 8, MAC D0:77:CE:2B:20:50)
  Tofino Port 24 (Logical 16, MAC D0:77:CE:2B:20:54) --> Arista --> TRex Port 1 (10:70:fd:30:80:d1)
"""

import sys
import os
import itertools
import math
import time
import glob

# =============================================================================
# CONFIGURATION
# =============================================================================

# Tofino logical port numbers (from bf_shell "pm show" D_P column)
TOFINO_INGRESS_PORT = 8    # Logical port 8  (Physical 23) - receives from TRex
TOFINO_EGRESS_PORT = 16    # Logical port 16 (Physical 24) - sends to TRex

# Tofino port MACs
TOFINO_INGRESS_MAC = "D0:77:CE:2B:20:50"  # Port 23 / Logical 8
TOFINO_EGRESS_MAC  = "D0:77:CE:2B:20:54"  # Port 24 / Logical 16

# TRex interface MACs
TREX_TX_MAC = "10:70:fd:30:80:d0"  # TRex Port 0 (TX to Tofino)
TREX_RX_MAC = "10:70:fd:30:80:d1"  # TRex Port 1 (RX from Tofino)

# Traffic IPs (must match traffic_gen.py)
TRAFFIC_SRC_IP = "192.168.123.1"
TRAFFIC_DST_IP = "192.168.100.1"
COLLECTOR_IP   = "192.168.100.2"   # DTA telemetry destination IP

# Traffic ports (must match traffic_gen.py)
TRAFFIC_SRC_PORT = 1025
TRAFFIC_DST_PORT = 4500
TRAFFIC_PROTOCOL = 17  # UDP

# =============================================================================
# Try to load precomputed static tables
# =============================================================================
STATIC_IAT = None
STATIC_SIZE = None
try:
    marina_dir = os.path.join(os.path.dirname(__file__), 'Marina')
    if marina_dir not in sys.path:
        sys.path.append(marina_dir)
    from static_tables import iat_log_square as STATIC_IAT, size_log_square as STATIC_SIZE
except Exception:
    pass

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


# =============================================================================
# Port configuration (replaces manual bfshell ucli/pm commands)
# =============================================================================
# Ports to enable: (logical_dev_port, speed, fec, autoneg)
PORTS_CONFIG = [
    # Physical 23/0 (Logical 8)  - Ingress from Arista/TRex
    (TOFINO_INGRESS_PORT, "BF_SPEED_100G", "BF_FEC_TYP_REED_SOLOMON", "PM_AN_FORCE_DISABLE"),
    # Physical 24/0 (Logical 16) - Egress to Arista/TRex
    (TOFINO_EGRESS_PORT,  "BF_SPEED_100G", "BF_FEC_TYP_REED_SOLOMON", "PM_AN_FORCE_DISABLE"),
]


def configure_ports(bfrt_info, target_dev):
    """Enable physical ports via the $PORT fixed-function table.

    This is equivalent to the bfshell ucli/pm commands:
        port-add 23/0 100G RS
        an-set 23/0 2          # PM_AN_FORCE_DISABLE
        port-enb 23/0
    """
    port_table = bfrt_info.table_get('$PORT')

    for dev_port, speed, fec, autoneg in PORTS_CONFIG:
        print(f"  Enabling port {dev_port} ({speed}, {fec}, {autoneg})...")
        try:
            port_table.entry_add(
                target_dev,
                [port_table.make_key([gc.KeyTuple('$DEV_PORT', dev_port)])],
                [port_table.make_data([
                    gc.DataTuple('$SPEED', str_val=speed),
                    gc.DataTuple('$FEC', str_val=fec),
                    gc.DataTuple('$AUTO_NEGOTIATION', str_val=autoneg),
                    gc.DataTuple('$PORT_ENABLE', bool_val=True),
                ])]
            )
            print(f"    Port {dev_port} added and enabled.")
        except Exception as e:
            # Port may already exist
            try:
                port_table.entry_mod(
                    target_dev,
                    [port_table.make_key([gc.KeyTuple('$DEV_PORT', dev_port)])],
                    [port_table.make_data([
                        gc.DataTuple('$SPEED', str_val=speed),
                        gc.DataTuple('$FEC', str_val=fec),
                        gc.DataTuple('$AUTO_NEGOTIATION', str_val=autoneg),
                        gc.DataTuple('$PORT_ENABLE', bool_val=True),
                    ])]
                )
                print(f"    Port {dev_port} modified and enabled.")
            except Exception as e2:
                print(f"    WARNING: Could not configure port {dev_port}: {e2}")


# =============================================================================
# Static table computation (fallback if precomputed tables not available)
# =============================================================================
def basetwo(x):
    return int(x, base=2)

def compute_square_table(N, m):
    table = []
    for n in range(N):
        repeat_count = min(m - 1, N - n - 1)
        for permutation in itertools.product('01', repeat=repeat_count):
            bitmatch = '0' * n + '1' + ''.join(permutation)
            mask_bits = max(0, N - n - m)
            match_val = basetwo(bitmatch) << mask_bits
            prefix_len = N - mask_bits

            min_log_val = basetwo(bitmatch + '0' * mask_bits)
            max_log_val = basetwo(bitmatch + '1' * mask_bits)
            if min_log_val == 0:
                min_log_val = 1

            values = [math.log2(x) for x in range(min_log_val, max_log_val + 1)]
            squares = [v ** 2 for v in values]
            cubes = [v ** 3 for v in values]

            cube = round(sum(cubes) / len(cubes))
            square = min(round(sum(squares) / len(squares)), 2**(N >> 1) - 1)
            value = round(sum(values) / len(values))

            table.append((match_val, prefix_len, value, square, cube))
    return table


def pick_action_name(tbl, candidates):
    try:
        action_names = list(tbl.info.action_dict.keys())
    except Exception:
        action_names = []
    for name in candidates:
        if name in action_names:
            return name
    if action_names:
        return action_names[0]
    return None


def main():
    print("=" * 60)
    print("Marina Reporter - Deploy Script")
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

    # Two targets: one for P4 tables (all pipes), one for fixed-function tables
    target = gc.Target(device_id=0, pipe_id=0xffff)   # P4 pipe tables
    target_dev = gc.Target(device_id=0)                # Fixed-function tables ($PORT, $mirror.cfg)

    # =========================================================================
    # 0. Enable Physical Ports
    # =========================================================================
    print("\nConfiguring physical ports...")
    configure_ports(bfrt_info, target_dev)
    print("Waiting 3 seconds for ports to come up...")
    time.sleep(3)

    # =========================================================================
    # Get Tables
    # =========================================================================
    tbl_forward = bfrt_info.table_get('SwitchIngress.tbl_forward')
    tbl_classification = bfrt_info.table_get('SwitchIngress.tbl_classification')
    tbl_hashToCollector = bfrt_info.table_get('Reporting.tbl_hashToCollectorServer')
    tbl_compute_iat_log = bfrt_info.table_get('SwitchIngress.Marina.tbl_compute_iat_log')
    tbl_compute_size_log = bfrt_info.table_get('SwitchEgress.Marina.tbl_compute_size_log')
    mirror_cfg_table = bfrt_info.table_get('$mirror.cfg')

    # Resolve action names (varies by SDE version / P4 compilation)
    action_iat = pick_action_name(tbl_compute_iat_log, [
        'MarinaIngress.compute_iat_log',
        'SwitchIngress.Marina.compute_iat_log',
        'Marina.compute_iat_log',
        'compute_iat_log'
    ])
    action_size = pick_action_name(tbl_compute_size_log, [
        'MarinaEgress.compute_size_log',
        'SwitchEgress.Marina.compute_size_log',
        'Marina.compute_size_log',
        'compute_size_log'
    ])
    action_forward = pick_action_name(tbl_forward, [
        'SwitchIngress.forward',
        'forward'
    ])
    action_collector = pick_action_name(tbl_hashToCollector, [
        'Reporting.set_collector_info',
        'Marina.Reporting.set_collector_info',
        'SwitchEgress.Marina.Reporting.set_collector_info',
        'set_collector_info'
    ])

    if not all([action_iat, action_size, action_forward, action_collector]):
        print("CRITICAL: Could not resolve one or more action names.")
        print(f"  action_iat={action_iat}")
        print(f"  action_size={action_size}")
        print(f"  action_forward={action_forward}")
        print(f"  action_collector={action_collector}")
        return

    # =========================================================================
    # 1. Clear Tables
    # =========================================================================
    print("\nClearing tables...")
    for table in [tbl_forward, tbl_classification, tbl_hashToCollector,
                  tbl_compute_iat_log, tbl_compute_size_log]:
        try:
            table.entry_del(target)
        except Exception:
            pass

    # =========================================================================
    # 2. Configure Mirror Session 1
    #    The pipe layer REQUIRES $direction but the BFRT schema may not
    #    expose it under action_dict (actionless table on some Tofino2 SDEs).
    #    We introspect BOTH action_dict AND top-level data_dict, then
    #    brute-force all parameter combos, catching make_data errors.
    # =========================================================================
    print("\nConfiguring Mirror Session 1 -> Port 16...")
    mirror_sess_id = 1

    # --- Introspect mirror table schema (both action-based and actionless) ---
    mirror_fields_by_action = {}   # action_name -> set(field_names)
    mirror_fields_top = set()      # top-level fields (actionless tables)

    try:
        if hasattr(mirror_cfg_table.info, 'action_dict'):
            for aname, ainfo in mirror_cfg_table.info.action_dict.items():
                flds = set()
                if hasattr(ainfo, 'data_dict'):
                    flds = set(ainfo.data_dict.keys())
                mirror_fields_by_action[aname] = flds
                print(f"  Action '{aname}' fields: {sorted(flds)}")
    except Exception as e:
        print(f"  action_dict introspection error: {e}")

    try:
        if hasattr(mirror_cfg_table.info, 'data_dict'):
            mirror_fields_top = set(mirror_cfg_table.info.data_dict.keys())
            if mirror_fields_top:
                print(f"  Top-level (actionless) fields: {sorted(mirror_fields_top)}")
    except Exception as e:
        print(f"  data_dict introspection error: {e}")

    all_known_fields = mirror_fields_top.copy()
    for flds in mirror_fields_by_action.values():
        all_known_fields.update(flds)
    print(f"  All discovered fields: {sorted(all_known_fields)}")
    print(f"  Actions: {list(mirror_fields_by_action.keys()) or ['(none. actionless table)']}")

    # --- Action names to attempt (action-based and actionless) ---
    action_names_to_try = []
    if '$normal' in mirror_fields_by_action:
        action_names_to_try.append('$normal')
    for a in mirror_fields_by_action:
        if a != '$normal':
            action_names_to_try.append(a)
    action_names_to_try.append(None)   # actionless , make_data without action

    def try_mirror_config(tgt, data_tuples, action_name):
        """Try to add mirror session. Catches make_data validation errors."""
        try:
            key = [mirror_cfg_table.make_key([gc.KeyTuple('$sid', mirror_sess_id)])]
        except Exception as e:
            return False, f"make_key: {e}"

        try:
            if action_name is not None:
                data = [mirror_cfg_table.make_data(data_tuples, action_name)]
            else:
                data = [mirror_cfg_table.make_data(data_tuples)]
        except Exception as e:
            return False, f"make_data: {e}"

        # Delete stale session
        try:
            mirror_cfg_table.entry_del(tgt, key)
        except Exception:
            pass

        try:
            mirror_cfg_table.entry_add(tgt, key, data)
            return True, "entry_add OK"
        except Exception as e1:
            try:
                mirror_cfg_table.entry_mod(tgt, key, data)
                return True, "entry_mod OK"
            except Exception as e2:
                return False, f"add:{e1} | mod:{e2}"

    # --- Build ALL configs to try (always include $direction variants) ---
    mirror_configs = []

    # With $direction (various direction values)
    for dir_val in ['INGRESS', 'BOTH', 'EGRESS']:
        mirror_configs.append((f"$direction={dir_val}, max_pkt_len", [
            gc.DataTuple('$direction', str_val=dir_val),
            gc.DataTuple('$ucast_egress_port', TOFINO_EGRESS_PORT),
            gc.DataTuple('$ucast_egress_port_valid', bool_val=True),
            gc.DataTuple('$session_enable', bool_val=True),
            gc.DataTuple('$max_pkt_len', 16384),
        ]))

    for dir_val in ['INGRESS', 'BOTH']:
        mirror_configs.append((f"$direction={dir_val}, no max_pkt_len", [
            gc.DataTuple('$direction', str_val=dir_val),
            gc.DataTuple('$ucast_egress_port', TOFINO_EGRESS_PORT),
            gc.DataTuple('$ucast_egress_port_valid', bool_val=True),
            gc.DataTuple('$session_enable', bool_val=True),
        ]))

    # Without direction (will fail at pipe layer but try anyway)
    mirror_configs.append(("no direction, max_pkt_len", [
        gc.DataTuple('$ucast_egress_port', TOFINO_EGRESS_PORT),
        gc.DataTuple('$ucast_egress_port_valid', bool_val=True),
        gc.DataTuple('$session_enable', bool_val=True),
        gc.DataTuple('$max_pkt_len', 16384),
    ]))

    mirror_configs.append(("minimal: port + enable", [
        gc.DataTuple('$ucast_egress_port', TOFINO_EGRESS_PORT),
        gc.DataTuple('$ucast_egress_port_valid', bool_val=True),
        gc.DataTuple('$session_enable', bool_val=True),
    ]))

    # --- Try each config × each action × each target ---
    targets = [(target_dev, "dev_target"), (target, "pipe_target(0xffff)")]
    mirror_ok = False
    attempt = 0

    for desc, data_tuples in mirror_configs:
        if mirror_ok:
            break
        for action_name in action_names_to_try:
            if mirror_ok:
                break
            for tgt, tgt_name in targets:
                attempt += 1
                act_desc = action_name if action_name else "no_action"
                ok, msg = try_mirror_config(tgt, data_tuples, action_name)
                status = "SUCCESS" if ok else "FAILED"
                print(f"  [{attempt:2d}] {status}: {desc} | action={act_desc} | {tgt_name} — {msg}")
                if ok:
                    mirror_ok = True
                    break

    if not mirror_ok:
        print("=" * 60)
        print("CRITICAL: All mirror session configurations failed!")
        print("All discovered fields:", sorted(all_known_fields))
        print("Actions:", list(mirror_fields_by_action.keys()))
        print("=" * 60)
        print("Run fix_mirror.py on Tofino for full schema dump, then try manually:")
        print("  bfrt_python")
        print(f"  bfrt.mirror.cfg.add_with_normal(sid={mirror_sess_id},")
        print(f"      direction='INGRESS', ucast_egress_port={TOFINO_EGRESS_PORT},")
        print(f"      ucast_egress_port_valid=True, session_enable=True)")
        print("=" * 60)

    # =========================================================================
    # 3. Populate Static Tables (IAT log, Size log)
    # =========================================================================
    print("Populating IAT Log Table (this may take a moment)...")
    iat_entries = STATIC_IAT if STATIC_IAT is not None else compute_square_table(32, 8)
    for i, (match_val, p_len, val, sq, cube) in enumerate(iat_entries):
        tbl_compute_iat_log.entry_add(
            target,
            [tbl_compute_iat_log.make_key([gc.KeyTuple('ig_md.iat', match_val, prefix_len=p_len)])],
            [tbl_compute_iat_log.make_data([
                gc.DataTuple('log', val),
                gc.DataTuple('log_square', sq),
                gc.DataTuple('log_cube', cube)
            ], action_iat)]
        )
        if i % 1000 == 0 and i > 0:
            print(f"  Inserted {i} IAT entries...")

    print("Populating Size Log Table...")
    size_entries = STATIC_SIZE if STATIC_SIZE is not None else compute_square_table(16, 8)
    for i, (match_val, p_len, val, sq, cube) in enumerate(size_entries):
        tbl_compute_size_log.entry_add(
            target,
            [tbl_compute_size_log.make_key([gc.KeyTuple('eg_md.size', match_val, prefix_len=p_len)])],
            [tbl_compute_size_log.make_data([
                gc.DataTuple('log', val),
                gc.DataTuple('log_square', sq),
                gc.DataTuple('log_cube', cube)
            ], action_size)]
        )

    # =========================================================================
    # 4. Forwarding Table
    #    ONLY forward test traffic (192.168.100.1) to port 16
    #    DO NOT add 192.168.100.2 , that caused the packet loop!
    #    (DTA report packets with dst=192.168.100.2 already reach port 16
    #     via the mirror session; adding a forward entry re-forwards them
    #     when they loop back from the Arista, creating millions of frames)
    #
    #    The P4 forward action requires: port, dst_mac, src_mac
    # =========================================================================
    print("Populating Forwarding Table...")
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
    print(f"  192.168.100.1/32 -> port {TOFINO_EGRESS_PORT} "
          f"(dst={TREX_RX_MAC}, src={TOFINO_EGRESS_MAC})")

    # NOTE: 192.168.100.2 intentionally NOT added to prevent loop.
    # DTA reports already exit via mirror session on port 16.
    # Any looped-back reports will hit default drop action.

    # =========================================================================
    # 5. Classification Table (TRex test flow)
    # =========================================================================
    print("Populating Classification Table...")
    tbl_classification.entry_add(
        target,
        [tbl_classification.make_key([
            gc.KeyTuple('hdr.ipv4.srcAddr', gc.ipv4_to_bytes(TRAFFIC_SRC_IP)),
            gc.KeyTuple('hdr.ipv4.dstAddr', gc.ipv4_to_bytes(TRAFFIC_DST_IP)),
            gc.KeyTuple('ig_md.l4_lookup.srcPort', TRAFFIC_SRC_PORT),
            gc.KeyTuple('ig_md.l4_lookup.dstPort', TRAFFIC_DST_PORT),
            gc.KeyTuple('hdr.ipv4.protocol', TRAFFIC_PROTOCOL)
        ])],
        [tbl_classification.make_data([
            gc.DataTuple('flow_id', 1)
        ], 'SwitchIngress.classification_hit')]
    )
    print(f"  Flow 1: {TRAFFIC_SRC_IP}:{TRAFFIC_SRC_PORT} -> "
          f"{TRAFFIC_DST_IP}:{TRAFFIC_DST_PORT} (proto={TRAFFIC_PROTOCOL})")

    # =========================================================================
    # 6. Collector Table (Hash -> Collector IP + MAC)
    #    The collector_mac field was added in the latest P4 revision.
    #    Fall back to ip-only if the binary predates that change.
    # =========================================================================
    print("Populating Collector Table...")

    # Probe whether the compiled binary has the collector_mac field
    _has_mac_field = False
    try:
        tbl_hashToCollector.info.data_field_size_get('collector_mac', action_collector)
        _has_mac_field = True
    except Exception:
        pass

    if _has_mac_field:
        data_fields = [
            gc.DataTuple('collector_ip', gc.ipv4_to_bytes(COLLECTOR_IP)),
            gc.DataTuple('collector_mac', mac_to_bytes(TREX_RX_MAC)),
        ]
        print(f"  All flows -> collector {COLLECTOR_IP} ({TREX_RX_MAC})  [ip+mac]")
    else:
        data_fields = [
            gc.DataTuple('collector_ip', gc.ipv4_to_bytes(COLLECTOR_IP)),
        ]
        print(f"  All flows -> collector {COLLECTOR_IP}  [ip only,will recompile P4 to include MAC]")
        print(f"  WARNING: collector_mac not in binary. DTA Ethernet dst will be unset.")
        print(f"  Fix: scp marina_reporter.p4 to Tofino, recompile, restart switchd, redeploy.")

    tbl_hashToCollector.entry_add(
        target,
        [tbl_hashToCollector.make_key([gc.KeyTuple('eg_md.collector_hash', 0, 0)])],
        [tbl_hashToCollector.make_data(data_fields, action_collector)]
    )

    # =========================================================================
    # Done
    # =========================================================================
    print("\n" + "=" * 60)
    print("DEPLOYMENT COMPLETE")
    print("=" * 60)
    print(f"\nTopology:")
    print(f"  TRex Port 0 ({TREX_TX_MAC}) --> Tofino Port 8  (ingress)")
    print(f"  Tofino Port 16 ({TOFINO_EGRESS_MAC}) --> TRex Port 1 ({TREX_RX_MAC})")
    print(f"\nExpected packets on TRex RX:")
    print(f"  1. Forwarded originals: {TRAFFIC_SRC_IP}:{TRAFFIC_SRC_PORT} -> {TRAFFIC_DST_IP}:{TRAFFIC_DST_PORT}")
    print(f"  2. DTA telemetry reports: {TRAFFIC_SRC_IP}:0xc0de -> {COLLECTOR_IP}:40040")
    print(f"\nPort 24 frame counts should now be stable (no more loop)")


if __name__ == "__main__":
    main()
