#let related_work() = [
  #set par(first-line-indent: 1em, spacing: 1.2em, justify: true)

  == Quality of Experience Modeling
  Traditional approaches to QoE modeling have relied on subjective user studies and objective mathematical models to quantify end-user satisfaction @itu_g1011_qoe_assessment @chikkerur_objective_video_quality_assessment. However, with the adoption of end-to-end encryption (e.g., HTTPS, QUIC) for multimedia delivery, Deep Packet Inspection (DPI) and payload-based video quality analysis are no longer viable. Consequently, recent literature has pivoted towards inferring QoE metrics directly from encrypted network traffic patterns.

  Frameworks such as ViCrypt @wassermann_vicrypt_video_qoe have demonstrated the feasibility of using Machine Learning (ML) to predict video QoE from network-layer features. Further extending this, contemporary studies have utilized ML models to estimate key QoE indicators for encrypted DASH traffic in modern cellular networks @ml_qoe_dash_5g and live video conferencing platforms @estimating_qoe_mdpi. These works collectively establish that statistical network properties such as packet sizes, inter-arrival times (IAT), and jitter are strong predictors of application-level events like buffer depletion and stalling, forming the theoretical basis for the feature engineering in this thesis.

  == In-Network Machine Learning
  While ML-based QoE prediction is well-established, relying on end-host GPUs or external collector servers introduces latency and limits scalability in high-throughput environments. Recent advancements in programmable data planes, specifically using the P4 language, have enabled the displacement of some monitoring and decision-making logic from the control plane to the data plane @marina_paper.

  Executing complex ML models like Random Forests at line rate, however, requires specialized hardware mapping. The pForest architecture @busse_grawitz_pforest_in_network_inference introduced the concept of translating context-dependent decision trees into Match-Action Tables (MATs) for in-network inference. Building upon this paradigm, frameworks like Planter @planter_paper have formalized the automated mapping of ensemble ML models into programmable switches. Other recent works have explored resource-efficient implementations of tree-based models using feature sharing and knowledge distillation @empowering_in_network_classification. These methodologies provide the architectural foundation for our approach of translating a unified Random Forest model into unrolled physical pipeline stages using Ternary Content-Addressable Memory (TCAM).

  #figure(
    image("../assets/pipeline.png", width: 100%),
    caption: [The general architecture of a P4 switch. @empowering_in_network_classification],
  )

  == Benchmarking and Hardware Constraints
  Evaluating the performance of ML models on hardware such as the Intel Tofino requires a deep understanding of its strict physical constraints. As highlighted in recent comprehensive surveys on in-network machine learning @in_network_ml_survey, programmable Application-Specific Integrated Circuits (ASICs) are fundamentally bottlenecked by available SRAM, TCAM, Very Long Instruction Word (VLIW) instruction slots, and a hard limit on physical pipeline stages.

  Studies evaluating hybrid in-network classification frameworks, such as IIsy @iisy_framework, emphasize the complex multi-dimensional trade-offs between an ML model's predictive accuracy and its hardware resource footprint. Furthermore, because the Tofino architecture enforces a strict Directed Acyclic Graph (DAG) for table execution, recursive branching inherent in standard decision trees must be aggressively flattened @in_network_topology_survey. These studies guide our benchmarking approach, showing that feature selection, limited tree depth, and tuning are essential to avoid compiler timeouts and hardware resource exhaustion.
]
