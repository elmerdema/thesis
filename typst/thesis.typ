#set page("us-letter", margin: 1in)
#set text(12pt)

#show heading: set text(weight: "bold")
#show heading.where(level: 1): set text(size: 18pt)
#show heading.where(level: 2): set text(size: 14pt)

#align(center)[
  #text(size: 20pt, weight: "bold")[Predicting Quality of Experience (QoE) Using MARINA Parameters Extracted from P4/Tofino Switches]

  #v(1cm)
  Elmer Dema(22211551) \
  Faculty of Applied Informatics \
  TH Deggendorf \
  #datetime.today().display()
]



#heading(level: 1)[Abstract]

Quality of Experience (QoE) is a crucial metric for multimedia services, as it directly reflects user satisfaction with platforms such as YouTube or Netflix. However, measuring QoE is challenging due to its subjective nature and the difficulty of obtaining real-time user feedback. Traditional methods relying on surveys or manual inputs are not scalable for large-scale network environments. 

In this work, we propose a machine learning (ML) model that predicts QoE using only MARINA parameters—features extracted directly from a P4/Tofino switch. Before estimating QoE, a video flow classifier is used to identify and separate video traffic from other types of network flows. This approach demonstrates that user experience can be accurately inferred from network-level statistics alone, without relying on direct user feedback.


#heading(level: 1)[Introduction]

The increasing demand for high-quality video streaming services has made Quality of Experience (QoE) a key focus for network operators. Unlike traditional Quality of Service (QoS) metrics, QoE reflects the end user’s perception of service quality. Accurately measuring QoE is essential for optimizing network performance and ensuring user satisfaction. 

However, collecting subjective feedback at scale is infeasible. Therefore, researchers have focused on developing objective QoE estimation models that use measurable network parameters to predict user satisfaction. 

This thesis explores how MARINA parameters, extracted directly from P4/Tofino switches, can be used to predict QoE for video streaming services without direct user involvement.

#heading(level: 1)[Related Work]

Previous research in QoE estimation has primarily relied on application-layer data or end-user feedback. Traditional approaches use metrics such as buffer underruns, startup delay, and bitrate variations. While effective, these methods require access to application-level data or client-side instrumentation, which may not be feasible for network operators.

Recent studies have investigated the use of Software-Defined Networking (SDN) and programmable switches to collect fine-grained traffic statistics. However, the direct use of MARINA parameters for QoE prediction remains relatively unexplored. This thesis builds upon this research gap by developing an ML-based approach that leverages network-level telemetry alone.

#heading(level:1)[Methodology]


#heading(level:2)[Video Flow Classification]

Before QoE prediction, we implement a video flow classifier that distinguishes video traffic from other flows. This classifier is trained using labeled data and relies solely on MARINA features, ensuring a scalable and network-only approach.

#heading(level:2)[QoE Prediction Model]

After video flows are identified, an ML model (e.g., Random Forest) is trained to estimate QoE scores. The model learns to map MARINA features to subjective QoE indicators, approximated through known datasets.



#heading(level:1)[Conclusion and Future Work]

This thesis presents an automated approach for QoE estimation using only MARINA parameters from P4/Tofino switches. By eliminating the need for user feedback or application-level data, this method enhances scalability and deployability for real-world network monitoring.


#heading(level:1)[References]

1. Wassermann, S et al., "ViCrypt to the Rescue: Real-Time, Machine-Learning-Driven Video-QoE Monitoring for Encrypted Streaming  Traffic," *in IEEE Transactions* on Network and Service Management
2. Karagkioules, Th. et Al., "A public Dataset for Youtube's Mobile Streaming Client"
