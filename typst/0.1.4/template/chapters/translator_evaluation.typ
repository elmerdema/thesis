#import "telemetry_parsing_results.typ": telemetry_parsing_results

#let translator_evaluation() =[
  #set par(first-line-indent: 1em, spacing: 1.2em, justify: true)

  == System Evaluation and Translator Testing
  To evaluate the performance and accuracy of the in-network Quality of Experience (QoE) classification model, a hardware-in-the-loop testbed was utilized. The topology consists of a TRex software traffic generator connected to an Intel Tofino programmable switch. The evaluation was conducted in a two-phase approach: first generating the necessary telemetry data, and second, testing the Translator's inference and routing capabilities.

  === Phase 1: Telemetry Data Generation (Reporter)
  The Translator component relies on Data-Plane Telemetry Architecture (DTA) packets to perform inference. Because these packets do not exist in the raw public datasets, they had to be synthetically generated using the actual P4 hardware. 
  
  To achieve this, the TRex server was configured to replay raw TCPdump logs from Scenario 6 of the Würzburg QoE dataset into the Tofino switch. The switch, loaded with the "Reporter" P4 program, processed this traffic, forwarded it back to the server, and generated a dedicated DTA telemetry packet every 100ms containing the aggregated network features. These DTA packets were captured into a PCAP file (`trex_tofino_reply.pcap`) to serve as the ground-truth input for the subsequent Translator evaluation.

  #figure(
  image("../assets/pcap.png", width: 80%),
  caption: [
    Pcap file inspected with pcapviewer extension (VsCode)
  ],
)


  === Phase 2: Translator Inference Testing
  In the second phase, the Tofino switch was reprogrammed with the "Translator" P4 program, which includes the embedded Random Forest ML tables. The objective was to replay the previously captured DTA packets through the Translator to verify if the switch could correctly classify the QoE state in real-time, append the classification result to the packet header, and execute state-dependent routing decisions.

  To automate this, a custom Python testing framework (`traffic_gen_translator.py`) was developed utilizing the TRex Stateless (STL) API and the Scapy packet manipulation library.

  === Packet Manipulation and Topology Adaptation
  When replaying PCAP files in a live network testbed, the original Layer 2 addresses are no longer valid for the current topology. The script utilizes Scapy to load the DTA packets (filtered by UDP port 40040) and rewrites the Source and Destination MAC addresses. The Source MAC is updated to the TRex TX interface, and the Destination MAC is set to the Tofino switch. 
  
  Crucially, because the IP and UDP headers are modified, the script explicitly deletes the existing checksums, forcing Scapy to recalculate them before transmission. This ensures the packets are not dropped by the switch due to checksum validation failures.

  #figure(
    box(fill: luma(240), inset: 8pt, radius: 4pt, width: 100%)[
      #set align(left)
      ```python
      for pkt in packets:
          if UDP in pkt and pkt[UDP].dport == DTA_UDP_PORT:
              # Rewrite MACs for the live testbed topology
              pkt[Ether].src = TREX_TX_MAC
              pkt[Ether].dst = TOFINO_MAC
              
              # Force checksum recalculation after header modification
              if IP in pkt: del pkt[IP].chksum
              del pkt[UDP].chksum
      ```
    ],
    caption:[Scapy packet manipulation logic to adapt saved DTA PCAPs for live replay.]
  )

  === Timing Preservation
  Machine learning models analyzing network traffic, especially those utilizing features like jitter, Inter-Arrival Time (IAT), and Exponential Moving Averages (EMA), are highly sensitive to temporal dynamics. Replaying the PCAP file as a single high-speed burst would compress the time windows and invalidate the ML classification.

  To prevent this, the script computes the exact microsecond gap between consecutive packets from the original PCAP timestamps. It then utilizes TRex's `STLStream` objects, specifically utilizing the Inter-Stream Gap (`isg`) parameter and the `next` attribute. This creates a chained loop of packets that perfectly mimics the original 100ms emission rate of the Reporter program.

  === Overcoming Testbed Artifacts: MAC Learning
  A significant challenge encountered during testing involved intermediate network equipment (e.g., Arista switches) located between the TRex server and the Tofino switch. Because the TRex RX port only receives traffic and does not natively transmit, the intermediate switch fails to learn the RX port's MAC address, resulting in dropped or flooded return traffic.

  To resolve this, a "Keepalive" mechanism was implemented. Before initiating the DTA traffic burst, the script instructs TRex to transmit dummy broadcast UDP packets from the RX port. This forces the intermediate switch to populate its MAC address table (FDB), ensuring a clean and reliable return path for the packets evaluated by the Tofino switch.

  #figure(
    box(fill: luma(240), inset: 8pt, radius: 4pt, width: 100%)[
      #set align(left)
      ```python
      # Keepalive on RX port (CRITICAL - prevents intermediate switch drops)
      keepalive_pkt = (
          Ether(src=TREX_RX_MAC, dst="ff:ff:ff:ff:ff:ff") /
          IP(src=TREX_RX_IP, dst="255.255.255.255") /
          UDP(sport=12345, dport=12345) / Raw(load="keepalive")
      )
      keepalive_stream = STLStream(
          packet=STLPktBuilder(pkt=keepalive_pkt),
          mode=STLTXCont(pps=5)
      )
      c.add_streams(keepalive_stream, ports=[rx_port])
      c.start(ports=[rx_port], force=True)
      ```
    ],
    caption: [Implementation of the Keepalive mechanism to trigger MAC learning on intermediate switches.]
  )

  === Execution and Capture
  With the topology established and timing configured, the TRex server transitions the RX port into a service mode and begins capturing traffic. The DTA streams are transmitted from the TX port for a defined duration (10 seconds). As the packets pass through the Tofino switch, the P4 Translator program applies the Random Forest classification, appends the resulting QoE state to the packet, and routes it back. 

  The script continually polls and displays the real-time TX/RX statistics to verify that no packets are dropped during inference. Finally, the test concludes by halting transmission, stopping the capture buffer, and saving the evaluated packets into a new output file (`trex_tofino_translator_reply.pcap`) for offline validation of the model's accuracy.

  #telemetry_parsing_results()
]