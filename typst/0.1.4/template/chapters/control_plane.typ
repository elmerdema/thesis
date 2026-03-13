#let control_plane_configuration() = [
  #set par(first-line-indent: 1em, spacing: 1.2em, justify: true)

  === Control Plane Configuration: Streamlined Forwarding
  In a Software-Defined Networking (SDN) architecture using P4, compiling and loading the program onto the Tofino ASIC only defines the pipeline's structure. Upon initialization, the match-action tables within the data plane are entirely empty, meaning the switch will default to dropping all incoming packets. To establish connectivity within the hardware-in-the-loop testbed, a control plane application is required to populate the forwarding tables.

  For this evaluation, a streamlined Python script was developed utilizing the Barefoot Runtime (BFRT) gRPC interface. Unlike full deployment scripts that initialize the entire ML pipeline, telemetry thresholds, and routing logic simultaneously, this script was intentionally decoupled to focus exclusively on the `tbl_forward` table.

  === Isolated Forwarding Table Configuration
  The decision to isolate the forwarding logic was driven by the need for modularity during testing. By removing the overhead of configuring the entire P4 pipeline, this script allows for rapid, incremental updates to the routing topology without resetting the switch's telemetry or machine learning states. This is particularly advantageous during debugging or when switching between the "Reporter" and "Translator" testing phases, as it guarantees that basic Layer 3 forwarding remains intact regardless of the data plane's experimental features.

  === BFRT gRPC Implementation
  The script connects to the Tofino's BFRT server on `localhost:50052` and binds to the deployed pipeline profile (`p4_marina_reporter`). It then targets the `SwitchIngress.tbl_forward` table, retrieving the dynamically assigned action IDs directly from the compiler's output, which ensures robustness against P4 code modifications.

  #figure(
    block(fill: luma(240), inset: 8pt, radius: 4pt, width: 100%)[
      #set align(left)
      ```python
      # Construct the Match Key (Destination IP)
      key =[
          tbl_forward.make_key([
              gc.KeyTuple('hdr.ipv4.dstAddr',
                          gc.ipv4_to_bytes('192.168.100.1'),
                          prefix_len=32)
          ])
      ]

      # Construct the Action Data (Egress Port and MAC rewrite)
      data = [
          tbl_forward.make_data([
              gc.DataTuple('port', 16), # Logical Port 16 (Physical 24)
              gc.DataTuple('dst_mac', mac_to_bytes('10:70:fd:30:80:d1')),
              gc.DataTuple('src_mac', mac_to_bytes('D0:77:CE:2B:20:54')),
          ], action_forward)
      ]

      # Insert into Tofino hardware
      tbl_forward.entry_add(target, key, data)
      ```
    ],
    caption: [BFRT gRPC snippet demonstrating the insertion of a match-action entry into the Tofino hardware.],
  )

  === Table Logic and Topology Integration
  The hardware testbed consists of the TRex traffic generator communicating with the Tofino switch via an intermediate Arista switch. Because the TRex server generates traffic destined for `192.168.100.1`, the Tofino switch must correctly identify these packets, assign them to the correct egress port, and rewrite the Ethernet headers to ensure the Arista switch forwards them back to the TRex RX interface.

  The inserted entry implements Exact Match logic on the IPv4 destination address. When a packet matches, the action parameters (`port`, `dst_mac`, and `src_mac`) are applied natively at line rate by the switch's ALUs. Table 3 outlines the exact mapping programmed by the control plane script.

  #figure(
    table(
      columns: (auto, auto, 1fr),
      inset: 10pt,
      align: left,
      fill: (col, row) => if row == 0 { luma(230) } else { none },

      [*Component*], [*Parameter*], [*Configured Value*],

      [Match Key], [`hdr.ipv4.dstAddr`], [`192.168.100.1/32` (Exact Match)],
      [Action Data], [`port`], [`16` (Logical Egress Port to TRex)],
      [Action Data], [`src_mac`], [`D0:77:CE:2B:20:54` (Tofino Egress MAC)],
      [Action Data], [`dst_mac`], [`10:70:fd:30:80:d1` (TRex RX Interface MAC)],
    ),
    caption: [Forwarding rules populated in the data plane by the control plane script.],
  ) <tab:forwarding_rules>

  By successfully executing this script, the control plane ensures that any packet, whether it is raw telemetry traffic or an evaluated packet returning from the QoE ML models, is correctly encapsulated and routed back to the TRex server for statistical analysis and PCAP capture. Furthermore, the inclusion of exception handling in the script guarantees that connection failures or missing dependencies are gracefully reported, significantly simplifying the operational workflow of the testbed.

  #pagebreak()

  === Full Control Plane Script
  The following code block contains the complete Python script used to interact with the Barefoot Runtime (BFRT) gRPC interface. This script is responsible for pushing the exact match forwarding rules to the Tofino switch's data plane.

  #block(fill: luma(240), inset: 12pt, radius: 6pt, width: 100%, breakable: true)[
    #set align(left)
    #set text(size: 0.85em)
    ```python
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

    # CONFIGURATION

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
        tbl_forward = bfrt_info.table_get('SwitchIngress.tbl_forward')

        # Resolve action name (varies by SDE version / P4 compilation)
        try:
            action_forward = next(iter(tbl_forward.info.action_dict.keys()))
        except Exception:
            print("CRITICAL: Could not resolve action name for forward table.")
            return

        # =========================================================================
        # Insert Forward Table Entry
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
    ```
  ]
]
