#import "lib.typ": *
#let abstract() = [

  Quality of Experience (#abbr("qoe")) is a crucial metric for multimedia services, as it directly reflects user satisfaction with platforms such as YouTube or Netflix. However, measuring #abbr("qoe") is challenging due to its subjective nature and the difficulty of obtaining real-time user feedback. Traditional methods relying on surveys or manual inputs are not scalable for large-scale network environments.

  While papers, such as ViCrypt, have demonstrated that network statistics can predict user #abbr("qoe"), its reliance on end-host GPUs for processing features makes it incompatible for direct implementation in the network data plane @wassermann_vicrypt_video_qoe. To bridge this critical gap, this thesis investigates the possibility of implementing Machine Learning (#abbr("ml")) models for #abbr("qoe") prediction directly within the network data plane to provide real-time monitoring of encrypted video traffic.
  This work hypothesizes that by using time-windowed rolling statistics and mapping a constrained Random Forest (#abbr("rf")) classifier into Match-Action Tables (#abbr("mat")), it is possible to perform accurate, line-rate #abbr("qoe") prediction strictly within the physical memory and pipeline constraints of the Intel Tofino #abbr("asic").

  To achieve this, a hybrid architecture is introduced for real-time #abbr("qoe") monitoring that performs line-rate feature extraction and prediction. This design divides the predictive model into two components: a module deployed on a P4/Tofino switch performs initial video flow classification and extracts primitive features at line rate, while the final #abbr("qoe") prediction is made using a lightweight machine learning model on the switch itself. The main contributions include a mapping of #abbr("rf") classifiers to P4 match-action tables and a comprehensive benchmarking framework for evaluating in-network #abbr("ml") performance.
  #figure(
    image("assets/abstract.jpg", width: 80%),
    caption: [
      a network architecture diagram illustrating the data flow from streaming servers to client devices, while highlighting specific stages for measuring Quality of Service (#abbr("qos")), Quality of Delivery (#abbr("qod")), #abbr("qoe").
      #link("https://www.mdpi.com/2079-9292/10/22/2851")[
        Source
      ]
    ],
  )
]
