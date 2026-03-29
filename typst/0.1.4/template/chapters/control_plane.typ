#import "../lib.typ": *
#let control_plane_configuration() = [
  #set par(first-line-indent: 1em, spacing: 1.2em, justify: true)

  === Control Plane Configuration:  Forwarding
  In a Software-Defined Networking (#abbr("sdn")) architecture using P4, compiling and loading the program onto the Tofino #abbr("asic") only defines the pipeline's structure. Upon initialization, the match-action tables within the data plane are entirely empty, meaning the switch will default to dropping all incoming packets. To establish connectivity within the hardware-in-the-loop testbed, a control plane application is required to populate the forwarding tables.

  For this evaluation, a Python script was developed utilizing the Barefoot Runtime (#abbr("bfrt")) gRPC interface. Unlike full deployment scripts that initialize the entire #abbr("ml") pipeline, telemetry thresholds, and routing logic simultaneously, this script was intentionally decoupled to focus exclusively on the #code("tbl_forward") table.

  === Isolated Forwarding Table Configuration
  The decision to isolate the forwarding logic was driven by the need for modularity during testing. By removing the overhead of configuring the entire P4 pipeline, this script allows for rapid, incremental updates to the routing topology without resetting the switch's telemetry or machine learning states. This is particularly advantageous during debugging or when switching between the "Reporter" and "Translator" testing phases, as it guarantees that basic Layer 3 forwarding remains intact regardless of the data plane's experimental features.

  === #abbr("bfrt") gRPC Implementation
  The script connects to the Tofino's #abbr("bfrt") server on #code("localhost:50052") and binds to the deployed pipeline profile (#code("p4_marina_reporter")). It then targets the #code("SwitchIngress.tbl_forward") table, retrieving the dynamically assigned action IDs directly from the compiler's output, which ensures robustness against P4 code modifications.

  #figure(
    image("../assets/bfrt_flow.svg", width: 85%),
    caption: [#abbr("bfrt") gRPC entry insertion flow: a match key (destination #abbr("ip") prefix) and action data (egress port and #abbr("mac") addresses) are constructed separately and passed to \texttt{entry\_add()}, which writes the forwarding rule into the Tofino match-action table.],
  )

  === Table Logic and Topology Integration
  The hardware testbed consists of the TRex traffic generator communicating with the Tofino switch via an intermediate Arista switch. Because the TRex server generates traffic destined for #code("192.168.100.1"), the Tofino switch must correctly identify these packets, assign them to the correct egress port, and rewrite the Ethernet headers to ensure the Arista switch forwards them back to the TRex RX interface.

  The inserted entry implements Exact Match logic on the IPv4 destination address. When a packet matches, the action parameters (#code("port"), #code("dst_mac"), and #code("src_mac")) are applied natively at line rate by the switch's ALUs. Table 3 outlines the exact mapping programmed by the control plane script.

  #figure(
    table(
      columns: (auto, auto, 1fr),
      inset: 10pt,
      align: left,
      fill: (col, row) => if row == 0 { luma(230) } else { none },

      [*Component*], [*Parameter*], [*Configured Value*],

      [Match Key], [#code("hdr.ipv4.dstAddr")], [#code("192.168.100.1/32") (Exact Match)],
      [Action Data], [#code("port")], [#code("16") (Logical Egress Port to TRex)],
      [Action Data], [#code("src_mac")], [#code("D0:77:CE:2B:20:54") (Tofino Egress #abbr("mac"))],
      [Action Data], [#code("dst_mac")], [#code("10:70:fd:30:80:d1") (TRex RX Interface #abbr("mac"))],
    ),
    caption: [Forwarding rules populated in the data plane by the control plane script.],
  ) <tab:forwarding_rules>

  By successfully executing this script, the control plane ensures that any packet, whether it is raw telemetry traffic or an evaluated packet returning from the #abbr("qoe") #abbr("ml") models, is correctly encapsulated and routed back to the TRex server for statistical analysis and #abbr("pcap") capture. Furthermore, the inclusion of exception handling in the script guarantees that connection failures or missing dependencies are gracefully reported, significantly simplifying the operational workflow of the testbed.

  #pagebreak()

  === Full Control Plane Script
  The following code block contains the complete Python script used to interact with the Barefoot Runtime (#abbr("bfrt")) gRPC interface. This script is responsible for pushing the exact match forwarding rules to the Tofino switch's data plane.

  #block(fill: luma(240), inset: 12pt, radius: 6pt, width: 100%, breakable: true)[
    #set align(left)
    #set text(size: 0.85em)

    To populate the forwarding plane, a BF Runtime gRPC client connects to the
    Tofino's control plane server and inserts a single longest-prefix-match entry
    into #code("SwitchIngress.tbl_forward"). The entry matches all traffic destined for
    the configured target #abbr("ip") (prefix length 32) and rewrites both Ethernet
    addresses before forwarding the packet out the configured egress port toward
    the TRex receive interface. The table below summarises the fixed parameters
    used during this experiment.

    #v(6pt)

    #table(
      columns: (auto, auto, 1fr),
      stroke: none,
      fill: (_, row) => if calc.odd(row) { luma(228) } else { white },
      inset: (x: 8pt, y: 5pt),
      table.header(strong[Parameter], strong[Value], strong[Description]),
      [Destination #abbr("ip")], [#code("192.168.100.1/32")], [Match key in the forward table],
      [Egress port], [#code("16") (physical 24)], [Tofino port toward TRex Rx],
      [Source #abbr("mac")], [#code("D0:77:CE:2B:20:54")], [Tofino port 24 #abbr("mac") (rewritten)],
      [Destination #abbr("mac")], [#code("10:70:fd:30:80:d1")], [TRex port 1 #abbr("mac") (rewritten)],
      [gRPC endpoint], [#code("localhost:50052")], [BF Runtime control-plane server],
      [Pipeline], [#code("p4_marina_reporter")], [P4 program bound at runtime],
    )
  ]
  #figure(
    image("../assets/bfrt_forward_table_flowchart.svg", width: 80%),
    caption: [Control flow of the BF Runtime table insertion script.],
  )
]
