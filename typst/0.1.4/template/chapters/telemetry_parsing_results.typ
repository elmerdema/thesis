#import "../lib.typ": *
#let telemetry_parsing_results() = [
  #set par(first-line-indent: 1em, spacing: 1.2em, justify: true)

  === Telemetry Generation Results
  Following the execution of the hardware-in-the-loop tests, the captured traffic (`trex_tofino_reply.pcap`) was parsed offline to verify the proper generation of Data-Plane Telemetry Architecture (#abbr("dta")) packets by the Tofino switch. The parser processed approximately 285 MB of traffic, successfully filtering and isolating the telemetry reports from the background traffic.

  #figure(
    table(
      columns: (1fr, auto),
      inset: 10pt,
      align: (col, row) => if col == 0 { left } else { right },
      fill: (col, row) => if row == 0 { luma(230) } else { none },
      [*Traffic Metric*], [*Count*],

      [Total Captured Packets], [20,263],
      [Background / Other Packets], [20,228],
      [#abbr("dta") Telemetry Reports generated], [*350*],
    ),
    caption: [Summary of the captured #abbr("pcap") file during the Reporter testing phase.],
  ) <tab:pcap_summary>

  Of the 20,263 packets captured, the switch successfully emitted 350 dedicated #abbr("dta") telemetry reports (one every 100ms as configured). To validate the hardware logic, the payload of the telemetry reports was fully decoded. Table 2 details the specific fields extracted from Report \#1.

  The values confirm that the Tofino switch correctly tracked the stateful flow metrics, such as accumulated packet counts, #abbr("iat") sums, and jitter directly within the data plane. Additionally, the report appends the #abbr("ml") classification outcome and a bitmap indicating which specific features were utilized during the #abbr("rf") inference step.

  #figure(
    table(
      columns: (auto, 1fr),
      inset: 9pt,
      align: left,
      fill: (col, row) => if row == 0 { luma(230) } else { none },

      [*Telemetry Field*], [*Decoded Hardware Value*],

      // --- Encapsulation ---[*--- Network Encapsulation ---*], [],
      [L2 #abbr("mac") Address], [d0:77:ce:2b:20:54 -> 10:70:fd:30:80:d1],
      [L3 #abbr("ip") Address], [192.168.123.1 -> 192.168.100.2],
      [L4 Protocol], [UDP 49374 -> 40040 (DTA)],

      // --- #abbr("dta") Header ---
      [*--- #abbr("dta") Header Metadata ---*], [],
      [Opcode], [0x05],
      [Redundancy Level], [1],
      [Telemetry Key (Flow ID)], [2980564395],

      // --- Hardware Features ---[*--- Computed Features (Marina) ---*], [],
      [Monitored Flow], [192.168.123.1:1025 -> 192.168.100.1:4500 (UDP)],
      [Packet Count], [198],
      [Last Packet Timestamp], [850,630,301],
      [Sum of #abbr("iat")], [99,952,039],
      [Sum of IAT² / IAT³], [0 / 0],
      [Sum of Packet Size], [272,844],
      [Sum of Packet Size² / Size³], [0 / 0],
      [Jitter], [2,001,694],

      // --- Inference ---[*--- Inference Output ---*], [],
      [Classification Result], [*0* (NON-VIDEO)],
      [Used Features Bitmap], [0x0000000d],
    ),
    caption: [Detailed breakdown of #abbr("dta") Telemetry Report \#1, showcasing the stateful metrics computed by the Tofino hardware],
  ) <tab:dta_report>
]
