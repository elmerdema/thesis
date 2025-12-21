#set page("us-letter", margin: 1in)
#set text(12pt)

#show heading: set text(weight: "bold")
#show heading.where(level: 1): set text(size: 18pt)
#show heading.where(level: 2): set text(size: 14pt)

#align(center)[
  #text(size: 20pt, weight: "bold")[QoE Prediction from Encrypted Traffic with MARINA on P4/Tofino]

  #v(1cm)
  Elmer Dema(22211551) \
  Faculty of Applied Informatics \
  TH Deggendorf \
  Supervisor: Prof. Dr. Andreas Kassler \
  #datetime.today().display()
]



#heading(level: 1)[Abstract]

Quality of Experience (QoE) is a crucial metric for multimedia services, as it directly reflects user satisfaction with platforms such as YouTube or Netflix. However, measuring QoE is challenging due to its subjective nature and the difficulty of obtaining real-time user feedback. Traditional methods relying on surveys or manual inputs are not scalable for large-scale network environments. 

While papers, such as ViCrypt , have demonstrated that network statistics can predict user QoE, its reliance on end-host GPUs for processing features makes it impossible for direct implementation in the network data plane[2]. The computational and memory constraints of programmable switches prohibit such resource-intensive tasks. To bridge this critical gap, this thesis introduces a split-inference architecture for real-time QoE monitoring. This design divides the predictive model into two components: a module deployed on a P4/Tofino switch performs initial video flow classification and extracts primitive features at line rate, while the control plane computes extra parameters for the QoE (jitter,throughput,etc). After this, the final QoE prediction is made using a lightweight machine learning model on the switch itself.
This hybrid design avoids the limitations of the switch hardware while utilizing its real-time flow visibility.


#heading(level: 1)[Introduction]

The increasing demand for high-quality video streaming services has made Quality of Experience (QoE) a key focus for network operators. Unlike traditional Quality of Service (QoS) metrics, QoE reflects the end user’s perception of service quality. Accurately measuring QoE is essential for optimizing network performance and ensuring user satisfaction. 

However, collecting subjective feedback at scale is infeasible. Therefore, researchers have focused on developing objective QoE estimation models that use measurable network parameters to predict user satisfaction. 

This thesis explores how MARINA parameters, extracted directly from P4/Tofino switches, can be used to predict QoE for video streaming services without direct user involvement.

#heading(level: 1)[Related Work]

Previous research in QoE estimation has primarily relied on application-layer data or end-user feedback. Traditional approaches use metrics such as buffer underruns, startup delay, and bitrate variations. While effective, these methods require access to application-level data or client-side instrumentation, which may not be feasible for network operators. [1]


#heading(level:1)[Methodology]


#heading(level:2)[Video Flow Classification]

Before QoE prediction, we implement a video flow classifier that distinguishes video traffic from other flows. This classifier is trained using labeled data and relies solely on MARINA features, ensuring a scalable and network-only approach.

#heading(level:2)[QoE Prediction Model]

After video flows are identified, an ML model (e.g., Random Forest) is trained to estimate QoE scores on the switch. The model learns to map MARINA features to subjective QoE indicators, approximated through known datasets.



#heading(level:1)[Conclusion and Future Work]

This thesis presents an approach for QoE estimation using only MARINA parameters from P4/Tofino switches. By eliminating the need for user feedback or application-level data, this method enhances scalability and deployability for real-world network monitoring.


#heading(level:1)[References]
1. Hamidi, M. A., Bingöl, G., Floris, A., Porcu, S., and Atzori, L., "Analysis of Application-layer Data to Estimate the QoE of WebRTC-based Audiovisual Conversations," in Proceedings of DIEE, University of Cagliari, and CNIT, University of Cagliari, Cagliari, Italy.

2. Wassermann, S et al., "ViCrypt to the Rescue: Real-Time, Machine-Learning-Driven Video-QoE Monitoring for Encrypted Streaming  Traffic," *in IEEE Transactions* on Network and Service Management

#heading(level:1)[Bibliography]


Karagkioules, Th. et Al., "A public Dataset for Youtube's Mobile Streaming Client"
