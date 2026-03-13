#!/usr/bin/env python3
"""
Tofino Verification Script
===========================
Run this on the Tofino via bfrt_python to check if the compiled P4
program and table entries are correct.

Usage (in bfrt_python shell):
  exec(open('/path/to/verify_tofino.py').read())

Or from bash (if bfrt_python is in PATH):
  bfrt_python /path/to/verify_tofino.py
"""

import sys
import os
import glob

# =============================================================================
# Connect to BFRT
# =============================================================================
sde_install = os.environ.get('SDE_INSTALL', '/usr/local/sde')
bfrt_location = '{}/lib/python*/site-packages/tofino'.format(sde_install)
try:
    found_paths = glob.glob(bfrt_location)
    if found_paths:
        sys.path.append(found_paths[0])
    import bfrt_grpc.client as gc
except ImportError:
    print("ERROR: Cannot import bfrt_grpc. Run this on the Tofino or set SDE_INSTALL.")
    sys.exit(1)

print("=" * 70)
print("TOFINO VERIFICATION SCRIPT")
print("=" * 70)

try:
    interface = gc.ClientInterface('localhost:50052', client_id=7, device_id=0)
except Exception as e:
    print(f"Connection failed: {e}")
    sys.exit(1)

try:
    interface.bind_pipeline_config('p4_marina_reporter')
except Exception as e:
    print(f"WARNING: bind_pipeline_config failed: {e}")

bfrt_info = interface.bfrt_info_get('p4_marina_reporter')
target = gc.Target(device_id=0, pipe_id=0xffff)

# =============================================================================
# 1. Check loaded P4 program
# =============================================================================
print("\n[1] P4 PROGRAM INFO")
print("-" * 50)
try:
    p4_name = bfrt_info.p4_name_get()
    print(f"  Loaded P4 program: {p4_name}")
except:
    print("  Could not get P4 program name")

# List all tables to verify program structure
try:
    all_tables = bfrt_info.table_name_list_get()
    marina_tables = [t for t in all_tables if 'Marina' in t or 'marina' in t or 'mirror' in t.lower()]
    print(f"  Total tables: {len(all_tables)}")
    print(f"  Marina/mirror related tables:")
    for t in sorted(marina_tables):
        print(f"    - {t}")
except Exception as e:
    print(f"  Error listing tables: {e}")

# =============================================================================
# 2. Check Mirror Session
# =============================================================================
print("\n[2] MIRROR SESSION CONFIG")
print("-" * 50)
try:
    mirror_cfg = bfrt_info.table_get('$mirror.cfg')
    resp = mirror_cfg.entry_get(
        target,
        [mirror_cfg.make_key([gc.KeyTuple('$sid', 1)])],
        {"from_hw": True}
    )
    for data, key in resp:
        d = data.to_dict()
        print(f"  Session ID: 1")
        for k, v in sorted(d.items()):
            if not k.startswith('$') or k in ['$direction', '$ucast_egress_port',
                '$ucast_egress_port_valid', '$session_enable', '$max_pkt_len']:
                print(f"    {k}: {v}")
except Exception as e:
    print(f"  ERROR reading mirror session: {e}")
    print(f"  >>> Mirror session 1 may NOT be configured!")

# =============================================================================
# 3. Check Forward Table
# =============================================================================
print("\n[3] FORWARD TABLE ENTRIES")
print("-" * 50)
try:
    tbl_forward = bfrt_info.table_get('SwitchIngress.tbl_forward')
    resp = tbl_forward.entry_get(target, None, {"from_hw": True})
    count = 0
    for data, key in resp:
        count += 1
        k = key.to_dict()
        d = data.to_dict()
        print(f"  Entry {count}: {k}")
        print(f"    Action data: {d}")
    if count == 0:
        print("  >>> NO ENTRIES! Forward table is empty!")
except Exception as e:
    print(f"  Error: {e}")

# =============================================================================
# 4. Check Classification Table
# =============================================================================
print("\n[4] CLASSIFICATION TABLE ENTRIES")
print("-" * 50)
try:
    tbl_class = bfrt_info.table_get('SwitchIngress.tbl_classification')
    resp = tbl_class.entry_get(target, None, {"from_hw": True})
    count = 0
    for data, key in resp:
        count += 1
        k = key.to_dict()
        d = data.to_dict()
        print(f"  Entry {count}: {k}")
        print(f"    Action data: {d}")
    if count == 0:
        print("  >>> NO ENTRIES! Classification table is empty!")
        print("  >>> This means flow_id will ALWAYS be 0 => NO mirrors generated!")
except Exception as e:
    print(f"  Error: {e}")

# =============================================================================
# 5. Check Collector Table
# =============================================================================
print("\n[5] COLLECTOR TABLE ENTRIES")
print("-" * 50)
try:
    tbl_coll = bfrt_info.table_get('Reporting.tbl_hashToCollectorServer')
except:
    try:
        tbl_coll = bfrt_info.table_get('SwitchEgress.Marina.Reporting.tbl_hashToCollectorServer')
    except:
        tbl_coll = None
        print("  Could not find collector table")

if tbl_coll:
    try:
        resp = tbl_coll.entry_get(target, None, {"from_hw": True})
        count = 0
        for data, key in resp:
            count += 1
            k = key.to_dict()
            d = data.to_dict()
            print(f"  Entry {count}: {k}")
            print(f"    Action data: {d}")
        if count == 0:
            print("  >>> NO ENTRIES! Collector table is empty!")
    except Exception as e:
        print(f"  Error: {e}")

# =============================================================================
# 6. Check IAT/Size Log Table entry counts
# =============================================================================
print("\n[6] STATIC TABLE ENTRY COUNTS")
print("-" * 50)
for tbl_name in ['SwitchIngress.Marina.tbl_compute_iat_log',
                  'SwitchEgress.Marina.tbl_compute_size_log']:
    try:
        tbl = bfrt_info.table_get(tbl_name)
        resp = tbl.entry_get(target, None, {"from_hw": True})
        count = sum(1 for _ in resp)
        print(f"  {tbl_name}: {count} entries")
        if count == 0:
            print(f"  >>> EMPTY! Need to run deploy_marina.py")
    except Exception as e:
        print(f"  {tbl_name}: Error - {e}")

# =============================================================================
# 7. Try to read the egress parser info from context.json
# =============================================================================
print("\n[7] CHECKING P4 PARSER STRUCTURE")
print("-" * 50)
import json
context_paths = glob.glob(os.path.join(sde_install, 'share/p4/targets/tofino*/p4_marina_reporter/*/context.json'))
if not context_paths:
    context_paths = glob.glob('/home/*/p4_marina_reporter/*/context.json')
if not context_paths:
    context_paths = glob.glob('/root/p4_marina_reporter/*/context.json')
if not context_paths:
    # Search more broadly
    import subprocess
    try:
        result = subprocess.run(['find', '/', '-name', 'context.json', '-path', '*marina*'],
                                capture_output=True, text=True, timeout=10)
        context_paths = result.stdout.strip().split('\n') if result.stdout.strip() else []
    except:
        pass

if context_paths:
    print(f"  Found context.json: {context_paths[0]}")
    try:
        with open(context_paths[0]) as f:
            ctx = json.load(f)
        # Look for parser states
        for parser in ctx.get('parser', []):
            parser_name = parser.get('name', '')
            if 'egress' in parser_name.lower() or 'Egress' in parser_name:
                print(f"  Parser: {parser_name}")
                for state in parser.get('states', []):
                    state_name = state.get('name', '')
                    if 'mirror' in state_name.lower():
                        transitions = state.get('transitions', [])
                        for t in transitions:
                            next_state = t.get('next_state', 'END')
                            print(f"    State '{state_name}' -> '{next_state}'")
    except Exception as e:
        print(f"  Error reading context.json: {e}")
else:
    print("  Could not find context.json - check manually:")
    print("  find / -name 'context.json' -path '*marina*' 2>/dev/null")

# =============================================================================
# 8. Check port counters
# =============================================================================
print("\n[8] PORT COUNTERS")
print("-" * 50)
try:
    port_stat = bfrt_info.table_get('$PORT_STAT')
    for port_id in [8, 16]:
        resp = port_stat.entry_get(
            target,
            [port_stat.make_key([gc.KeyTuple('$DEV_PORT', port_id)])],
            {"from_hw": True}
        )
        for data, key in resp:
            d = data.to_dict()
            rx = d.get('$OctetsReceived', d.get('$FramesReceivedAll', '?'))
            tx = d.get('$OctetsTransmittedTotal', d.get('$FramesTransmittedAll', '?'))
            print(f"  Port {port_id}: RX={rx}  TX={tx}")
except Exception as e:
    print(f"  Error reading port stats: {e}")

# =============================================================================
# Summary
# =============================================================================
print("\n" + "=" * 70)
print("VERIFICATION COMPLETE")
print("=" * 70)
print("""
KEY CHECKS:
  - Mirror session 1 must show: session_enable=True, ucast_egress_port=16
  - Classification table must have at least 1 entry with flow_id=1
  - Forward table must have entry for 192.168.100.1 -> port 16
  - Collector table must have at least 1 entry
  - IAT log table should have ~3327 entries
  - Size log table should have ~1279 entries

If the parser structure shows parse_mirror_md -> parse_ethernet
(instead of -> parse_bridged_md), the P4 binary is OLD and needs recompilation!
""")
