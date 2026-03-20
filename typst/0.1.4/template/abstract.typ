#let abstract() = [

  Quality of Experience (QoE) is a crucial metric for multimedia services, as it directly reflects user satisfaction with platforms such as YouTube or Netflix. However, measuring QoE is challenging due to its subjective nature and the difficulty of obtaining real-time user feedback. Traditional methods relying on surveys or manual inputs are not scalable for large-scale network environments.

  While papers, such as ViCrypt , have demonstrated that network statistics can predict user QoE, its reliance on end-host GPUs for processing features makes it impossible for direct implementation in the network data plane @wassermann_vicrypt_video_qoe. To bridge this critical gap, this thesis addresses the following research question: _How can Machine Learning models for QoE prediction be efficiently implemented directly within the network data plane to provide real-time monitoring of encrypted video traffic, while navigating the fundamental trade-offs between predictive accuracy and hardware resource constraints?_ This work hypothesizes that by using time-windowed rolling statistics and mapping a constrained Random Forest classifier into Ternary Match-Action Tables, it is possible to perform accurate, line-rate QoE prediction strictly within the physical memory and pipeline constraints of the Intel Tofino ASIC.

  In order to achieve this, a hybrid architecture is introduced for real-time QoE monitoring that performs line-rate feature extraction and prediction. This design divides the predictive model into two components: a module deployed on a P4/Tofino switch performs initial video flow classification and extracts primitive features at line rate, while the final QoE prediction is made using a lightweight machine learning model on the switch itself. The main contributions include a mapping of Random Forest classifiers to P4 match-action tables and a comprehensive benchmarking framework for evaluating in-network ML performance.
  #figure(
    image("assets/abstract.jpg", width: 80%),
    caption: [
      a network architecture diagram illustrating the data flow from streaming servers to client devices, while highlighting specific stages for measuring Quality of Service (QoS), Quality of Delivery (QoD), and Quality of Experience (QoE).
      #link("https://www.mdpi.com/2079-9292/10/22/2851")[
        Source
      ]
    ],
  )
]
