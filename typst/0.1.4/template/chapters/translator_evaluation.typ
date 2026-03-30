#import "../lib.typ": *
#import "telemetry_parsing_results.typ": telemetry_parsing_results

#let translator_evaluation() = [
  #set par(first-line-indent: 1em, spacing: 1.2em, justify: true)

  == System Evaluation and Translator Testing
  To evaluate the performance and accuracy of the in-network #abbr("qoe") classification model, a hardware-in-the-loop testbed was utilized. The topology consists of a TRex software traffic generator connected to an Intel Tofino programmable switch. The evaluation was conducted in a two-phase approach: first generating the necessary telemetry data, and second, testing the Translator's inference and routing capabilities.

  === Phase 1: Telemetry Data Generation (Reporter)
  The Translator component relies on Data-Plane Telemetry Architecture (#abbr("dta")) packets to perform inference. Because these packets do not exist in the raw public datasets, they had to be synthetically generated using the actual P4 hardware.

  To achieve this, the TRex server was configured to replay raw tcpdump logs from scenario 6 of the Würzburg #abbr("qoe") dataset into the Tofino switch. The switch, loaded with the Reporter P4 program, processed this traffic, forwarded it back to the server, and generated a dedicated #abbr("dta") telemetry packet every 100ms containing the aggregated network features. These #abbr("dta") packets were captured into a #abbr("pcap") file (`trex_tofino_reply.pcap`) to serve as the ground-truth input for the subsequent Translator evaluation.

  #figure(
    image("../assets/pcap.png", width: 80%),
    caption: [
      Pcap file inspected with pcapviewer extension
    ],
  )


  === Phase 2: Translator Inference Testing
  In the second phase, the Tofino switch was reprogrammed with the Translator P4 program, which includes the embedded #abbr("rf") #abbr("ml") tables. The objective was to replay the previously captured #abbr("dta") packets through the Translator to determine whether the switch could correctly classify the #abbr("qoe") state in real-time, append the classification result to the packet header, and execute state-dependent routing decisions.

  To automate this, a custom Python testing framework (#link("https://github.com/elmerdema/thesis/blob/main/code/traffic_gen_translator.py")[traffic_gen_translator.py]) was developed utilizing the TRex Stateless (STL) API and the Scapy packet manipulation library.

  === Packet Manipulation and Topology Adaptation
  When replaying #abbr("pcap") files in a live network testbed, the original Layer 2 addresses are no longer valid for the current topology. The script utilizes Scapy to load the #abbr("dta") packets (filtered by #abbr("udp") port 40040) and rewrites the Source and Destination #abbr("mac") addresses. The Source #abbr("mac") is updated to the TRex TX interface, and the Destination #abbr("mac") is set to the Tofino switch.

  Crucially, because the #abbr("ip") and #abbr("udp") headers are modified, the script explicitly deletes the existing checksums, forcing Scapy to recalculate them before transmission. This ensures the packets are not dropped by the switch due to checksum validation failures.


  === Timing Preservation
  #abbr("ml") models analyzing network traffic, especially those utilizing features like jitter, (#abbr("iat")), and #abbr("ema"), are highly sensitive to temporal dynamics. Replaying the #abbr("pcap") file as a single high-speed burst would compress the time windows and invalidate the #abbr("ml") classification.

  To prevent this, the script computes the exact microsecond gap between consecutive packets from the original #abbr("pcap") timestamps. It then utilizes TRex's `STLStream` objects, specifically utilizing the Inter-Stream Gap (`isg`) parameter and the `next` attribute. This creates a chained loop of packets that perfectly mimics the original 100ms emission rate of the Reporter program.

  === Overcoming Testbed Artifacts: #abbr("mac") Learning
  A significant challenge encountered during testing involved intermediate network equipment (e.g., Arista switches) located between the TRex server and the Tofino switch. Because the TRex RX port only receives traffic and does not natively transmit, the intermediate switch fails to learn the RX port's #abbr("mac") address, resulting in dropped or flooded return traffic.

  To resolve this, a "Keepalive" mechanism was implemented. Before initiating the #abbr("dta") traffic burst, the script instructs TRex to transmit dummy broadcast #abbr("udp") packets from the RX port. This forces the intermediate switch to populate its #abbr("mac") address table, ensuring a clean and reliable return path for the packets evaluated by the Tofino switch.

  #figure(
    box(fill: luma(240), inset: 8pt, radius: 4pt, width: 100%)[
      #set align(left)
      ```python
      # Keepalive on RX port (CRITICAL - prevents intermediate switch drops)
      keepalive_pkt = (
          Ether(src=TREX_RX_MAC, dst="ff:ff:ff:ff:ff:ff") /
          #abbr("ip")(src=TREX_RX_IP, dst="255.255.255.255") /
          #abbr("udp")(sport=12345, dport=12345) / Raw(load="keepalive")
      )
      keepalive_stream = STLStream(
          packet=STLPktBuilder(pkt=keepalive_pkt),
          mode=STLTXCont(pps=5)
      )
      c.add_streams(keepalive_stream, ports=[rx_port])
      c.start(ports=[rx_port], force=True)
      ```
    ],
    caption: [Implementation of the Keepalive mechanism to trigger #abbr("mac") learning on intermediate switches.],
  )

  === Execution and Capture
  With the topology established and timing configured, the TRex server transitions the RX port into a service mode and begins capturing traffic. The #abbr("dta") streams are transmitted from the TX port for a defined duration (10 seconds). As the packets pass through the Tofino switch, the P4 Translator program applies the #abbr("rf") classification, appends the resulting #abbr("qoe") state to the packet, and routes it back.

  The script continually polls and displays the real-time TX/RX statistics to verify that no packets are dropped during inference. Finally, the test concludes by halting transmission, stopping the capture buffer, and saving the evaluated packets into a new output file (`trex_tofino_translator_reply.pcap`) for offline validation of the model's accuracy.

  #telemetry_parsing_results()
]
