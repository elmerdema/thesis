#let summary() = [
  This thesis has successfully demonstrated the feasibility and performance of predicting Quality of Experience (QoE) from encrypted traffic directly within the data plane using MARINA telemetry on P4-programmable switches (Tofino 2). To evaluate the practical limits of this approach, a comprehensive benchmarking framework was developed. The automated pipeline, driven by the `code/benchmark.py` script, trains Random Forest models with varying hyperparameters, translates them into P4 code, and utilizes the Intel SDE compiler to evaluate architectural resource consumption. The resulting metrics are subsequently analyzed and visualized using `code/plot_benchmarks.py`.

  == Feature Scaling and Hardware Constraints
  The first major experiment evaluates the impact of the number of telemetry features ($k$) on both Machine Learning (ML) performance and hardware resource utilization. As shown in the benchmarking plots, increasing the number of features allows the Random Forest to capture more complex patterns in the traffic, improving accuracy and the F1 score. 

  #figure(
    image("../assets/benchmarks/01_feature_sweep_ml.png", width: 100%),
    caption: [ML performance metrics across a varying number of features ($k$).]
  )
  
  #figure(
    image("../assets/benchmarks/02_feature_sweep_hw.png", width: 100%),
    caption: [Hardware resource consumption (SRAM, TCAM, VLIW instructions, and pipeline stages) relative to the number of features.]
  )

  However, this improvement in ML metrics comes at a steep cost in terms of hardware resources. The compiler reports indicate that SRAM, TCAM, and specifically VLIW instruction slots scale rapidly as $k$ increases. The physical limit of 20 pipeline stages on the Tofino 2 architecture becomes a hard bottleneck, as demonstrated in the stage utilization heatmaps.

  #figure(
    image("../assets/benchmarks/03_stage_utilisation_heatmap.png", width: 100%),
    caption: [Per-stage resource utilization heatmaps showing the rapid consumption of available pipeline stages.]
  )

  == Tree and Depth Configuration Sweep
  The second experiment systematically sweeps the number of trees and the maximum depth of the Random Forest. While larger and deeper forests naturally yield higher test accuracies and better recall, they strain the P4 compiler's ability to fit the logic within the limited hardware stages.

  #figure(
    image("../assets/benchmarks/04_tree_sweep_ml_heatmaps.png", width: 100%),
    caption: [Heatmaps correlating the number of trees and maximum depth with overall ML performance.]
  )
  
  #figure(
    image("../assets/benchmarks/05_tree_sweep_compile.png", width: 100%),
    caption: [Compilation status and estimated pipeline stages for various tree and depth configurations. Configurations exceeding the 20-stage limit fail to compile.]
  )

  The compilation status grid highlights the operational boundaries of in-network ML. Configurations that exceed a certain complexity threshold either time out during compilation or fail completely due to the exhaustion of active pipeline stages and logical table IDs. 

  == Feature Importance and Resource Overview
  To optimize the models for deployment, it is crucial to understand which features contribute most to the classification. The Gini feature importances confirm that a small subset of the MARINA telemetry features provides the majority of the predictive power.

  #figure(
    image("../assets/benchmarks/07_feature_importances.png", width: 100%),
    caption: [Feature importances calculated during the feature sweep experiment.]
  )

  The aggregated resource overview illustrates the complex multi-dimensional trade-off between test accuracy, total SRAM allocated, active pipeline stages, and VLIW instructions. It proves that by carefully tuning the hyperparameters, an optimal configuration can be found that maximizes QoE prediction accuracy while remaining strictly within the hardware bounds of the Tofino 2 ASIC.

  #figure(
    image("../assets/benchmarks/08_resource_overview.png", width: 100%),
    caption: [Combined resource overview mapping accuracy against SRAM usage and active stages.]
  )

  == Conclusion
  In conclusion, this work bridges the gap between high-level machine learning models and low-level data plane programming. By translating decision trees into match-action tables and evaluating them systematically, this thesis confirms that line-rate, in-network QoE prediction is a viable and highly efficient approach. The benchmarking suite confirms that while modern programmable switches impose strict memory and stage limitations, intelligent feature selection and hyperparameter tuning allow robust ML models to operate at terabit speeds directly within the network infrastructure.
]