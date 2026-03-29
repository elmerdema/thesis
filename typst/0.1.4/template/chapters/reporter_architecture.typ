#import "../lib.typ": *
#let reporter_architecture(image_path) = [
  == REPORTER System Architecture

  The foundation of the  solution builds upon the Reporter #footnote[#abbr("dta") is a system consisting of several components, each in their own directories.#link("https://github.com/jonlanglet/DTA")[Reporter] is a #abbr("dta") reporter switch. This switch can generate telemetry reports through #abbr("dta")."] framework, a programmable switch architecture designed for real-time traffic classification. As illustrated in @fig-reporter, the system operates on a decoupled *Control Plane* and *Data Plane* model to handle high-throughput video traffic.

  The processing flow begins in the Data Plane when raw packets enter the ingress pipeline. For every incoming packet, the REPORTER updates Feature Registries with new telemetry data. A subset of these extracted features is then used by a *Random Forest (#abbr("rf")) Classifier*, which is encoded directly into the reporter's hardware. This classifier determines if a packet belongs to a video flow.

  If a packet is classified as a video packet, the REPORTER sends a *telemetry packet* to a downstream Translator Switch at a specific time interval. This telemetry packet carries the extracted features and the classification result. The Translator Switch then receives this packet and uses it to perform further *Quality of Experience (#abbr("qoe")) classification* by running a specific, potentially different, model on the incoming classified video packets.

  In parallel, the Control Plane oversees model lifecycle management. It handles the offline training of Random Forest models, encodes them into hardware table entries via the #code("TofinoForestManager").

  #figure(
    image(image_path, width: 100%),
    caption: [Architecture of the REPORTER framework, showcasing the interaction between Control Plane model management and Data Plane telemetry generation.]
  ) <fig-reporter>
  #pagebreak()
]