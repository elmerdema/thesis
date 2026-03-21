#import "translator_evaluation.typ": translator_evaluation

#let evaluation() = [
  #set par(first-line-indent: 1em, spacing: 1.2em, justify: true)


  #translator_evaluation()

  == Benchmarking and Performance Analysis
  This section presents the results of the benchmarking framework developed to evaluate the practical limits of in-network QoE prediction. The automated pipeline, which is implemented in the #link("https://github.com/elmerdema/thesis/blob/main/code/benchmark.py")[`code/benchmark.py`] script, trains Random Forest models with varying hyperparameters, translates them into P4 code, and utilizes the Intel SDE compiler to evaluate architectural resource consumption.

  === Feature Scaling and Hardware Constraints
  The first major experiment evaluates the impact of the number of telemetry features ($k$) on both Machine Learning (ML) performance and hardware resource utilization. As shown in the benchmarking plots, increasing the number of features allows the Random Forest to capture more complex patterns in the traffic, improving accuracy and the F1 score.

  #figure(
    image("../assets/benchmarks/01_feature_sweep_ml.png", width: 100%),
    caption: [ML performance metrics across a varying number of features ($k$).],
  )

  #figure(
    image("../assets/benchmarks/02_feature_sweep_hw.png", width: 100%),
    caption: [Hardware resource consumption (SRAM, TCAM, VLIW instructions, and pipeline stages) relative to the number of features.],
  )

  However, this improvement in ML metrics comes at a steep cost in terms of hardware resources. The compiler reports indicate that SRAM, TCAM, and specifically VLIW instruction slots scale rapidly as $k$ increases. The physical limit of 20 pipeline stages on the Tofino 2 architecture becomes a hard bottleneck, as demonstrated in the stage utilization heatmaps.


  === Tree and Depth Configuration Sweep
  The second experiment systematically sweeps the number of trees and the maximum depth of the Random Forest. While larger and deeper forests naturally yield higher test accuracies and better recall, they strain the P4 compiler's ability to fit the logic within the limited hardware stages.

  #figure(
    image("../assets/benchmarks/04_tree_sweep_ml_heatmaps.png", width: 100%),
    caption: [Heatmaps correlating the number of trees and maximum depth with overall ML performance.],
  )

  #figure(
    image("../assets/benchmarks/05_tree_sweep_compile.png", width: 100%),
    caption: [Compilation status and estimated pipeline stages for various tree and depth configurations. Configurations exceeding the 20-stage limit fail to compile.],
  )

  The compilation status grid highlights the operational boundaries of in-network ML. Configurations that exceed a certain complexity threshold either time out during compilation or fail completely due to the exhaustion of active pipeline stages and logical table IDs.

  === Feature Importance and Resource Overview
  To optimize the models for deployment, it is crucial to understand which features contribute most to the classification. The Gini feature importances confirm that a small subset of the MARINA telemetry features provides the majority of the predictive power.

  #figure(
    image("../assets/benchmarks/07_feature_importances.png", width: 100%),
    caption: [Feature importances calculated during the feature sweep experiment.],
  )

  The aggregated resource overview illustrates the complex multi-dimensional trade-off between test accuracy, total SRAM allocated, active pipeline stages, and VLIW instructions. It proves that by carefully tuning the hyperparameters, an optimal configuration can be found that maximizes QoE prediction accuracy while remaining strictly within the hardware bounds of the Tofino 2 ASIC.

  #figure(
    image("../assets/benchmarks/08_resource_overview.png", width: 100%),
    caption: [Combined resource overview mapping accuracy against SRAM usage and active stages.],
  )

  == Conclusion

  This work bridges the gap between high-level machine learning models and low-level
  data plane programming, demonstrating that Quality of Experience prediction from
  encrypted video traffic is not only theoretically possible, but practically achievable within
  the strict physical constraints of modern programmable ASICs.

  === Summary of Contributions

  The central hypothesis of this thesis, that a constrained Random Forest classifier
  mapped to Ternary Match-Action Tables can perform accurate, line-rate QoE prediction
  within Intel Tofino, was confirmed by the experimental results. Three
  concrete contributions support this conclusion:

  First, the MARINA feature pipeline was successfully adapted for in-network deployment.
  By reducing the feature space to four hardware-feasible metrics (`ps_sum`, `ps2_sum`,
  `ps3_sum`, and `jitter`) and aggregating them over non-overlapping 50ms windows,
  the system achieved a classification accuracy of 0.76 (15 percentage points above the majority-class baseline) with an F1-score of 0.80 for the
  critical *At\_Risk* class. This demonstrates that a small, carefully selected feature
  subset can retain the majority of predictive power while remaining deployable on hardware.

  Second, the pForest architecture was successfully extended and adapted to the
  Tofino Native Architecture (TNA). The automated pipeline translates a trained scikit-learn Random Forest directly into compilable P4 code,
  unrolling each decision tree across different physical pipeline stages and encoding
  split thresholds as ternary bitmasks in TCAM. The voting logic is pre-computed and
  hardcoded as exact-match entries, eliminating the need for costly runtime arithmetic
  in the data plane. This end-to-end automation significantly reduces the
  effort required to deploy new ML models onto programmable switches.

  Lastly, the sweep across tree count, depth, and feature count
  revealed that the 20-stage pipeline limit of the Tofino 2 architecture is the dominant
  bottleneck, not SRAM or TCAM. Configurations with depth $d > 3$ and more than
  six trees consistently exceeded the stage budget and failed to compile.

  #import "@preview/cetz:0.3.4": canvas, draw

  #let radar-data = (
    ("Accuracy", 0.76),
    ("F1 At-Risk", 0.80),
    ("F1 Steady", 0.69),
    ("HW Fit", 0.85),
    ("ROC-AUC", 0.75),
  )

  #let n = radar-data.len()
  #let angles = range(n).map(i => i * 360deg / n - 90deg)

  #figure(
    canvas(length: 3cm, {
      import draw: *

      // Grid rings
      for r in (0.2, 0.4, 0.6, 0.8, 1.0) {
        let pts = range(n).map(i => (
          calc.cos(angles.at(i)) * r,
          calc.sin(angles.at(i)) * r,
        ))
        line(..pts, close: true, stroke: (paint: gray.lighten(40%), thickness: 0.4pt, dash: "dashed"))

        // Ring labels (only on right side)
        content(
          (calc.cos(-90deg) * r, calc.sin(-90deg) * r - 0.07),
          text(size: 5pt, fill: gray)[#str(int(r * 100)) + "%"],
          anchor: "north",
        )
      }

      // Axis lines
      for i in range(n) {
        line((0, 0), (calc.cos(angles.at(i)), calc.sin(angles.at(i))), stroke: (
          paint: gray.lighten(20%),
          thickness: 0.4pt,
        ))
      }

      // Data polygon
      let data-pts = range(n).map(i => {
        let v = radar-data.at(i).at(1)
        (calc.cos(angles.at(i)) * v, calc.sin(angles.at(i)) * v)
      })

      line(..data-pts, close: true, fill: rgb("#3b82f6").transparentize(60%), stroke: (
        paint: rgb("#1d4ed8"),
        thickness: 1.2pt,
      ))

      // Data point dots
      for pt in data-pts {
        circle(pt, radius: 0.03, fill: rgb("#1d4ed8"), stroke: none)
      }

      // Axis labels
      for i in range(n) {
        let angle = angles.at(i)
        let label-r = 1.18
        let x = calc.cos(angle) * label-r
        let y = calc.sin(angle) * label-r

        let anchor = if calc.abs(x) < 0.2 {
          if y > 0 { "south" } else { "north" }
        } else if x > 0 { "west" } else { "east" }

        content((x, y), text(size: 6.5pt, weight: "semibold")[#radar-data.at(i).at(0)], anchor: anchor)
      }

      // Center label
      content((0, 0), text(size: 5pt, fill: gray.darken(20%))[System], anchor: "center")
    }),
    caption: [System performance overview across key evaluation dimensions.
      Hardware Fit reflects the ratio of successful compilations within the
      20-stage limit; Pipeline Efficiency reflects stage utilization headroom; ROC-AUC reflects the model's ability to distinguish between the two classes.],
  ) <fig-radar>

  === Interpretation of Results

  The feature importance analysis consistently confirmed that higher-order statistical
  moments of traffic volume, `ps2_sum` and `ps3_sum`, contribute more
  than 44% of the model's decision-making power. This finding aligns with the broader
  literature on encrypted traffic analysis: because payload content is inaccessible under
  HTTPS and QUIC, the *shape* of the traffic distribution, captured by its second and
  third moments, encodes information about burstiness and asymmetry that correlates
  strongly with application-layer buffer behavior. Jitter, while contributing only 11.7%
  of Gini importance in the baseline model, remains a necessary feature for capturing
  transient network instability that precedes stalling events.

  The risk-based labeling strategy, which uses a 500ms lookahead window to define
  the *At\_Risk* class, proved to be a meaningful design choice. The resulting class imbalance (61.3%
  *At\_Risk* vs. 38.7% *Steady*) reflects the nature of the dataset: video streaming
  sessions frequently operate near buffer depletion thresholds, particularly under the
  automatic quality selection of Scenario 6.

  The hardware-in-the-loop evaluation confirmed that the Tofino switch correctly
  computed stateful flow metrics, including packet counts, IAT sums, and jitter,
  entirely within the data plane, without offloading any computation to an external
  server.


  === Limitations and Future Work

  Despite these results, several limitations should be acknowledged. The model was
  trained and evaluated on a single scenario (Scenario 6, automatic quality selection) of the Würzburg QoE dataset.
  The dataset contains 7 other scenarios (Scenarios 1-5, 7, 8) that introduce various network degradations like rate-limiting and delay. Evaluating on these rate-limited scenarios would likely induce distribution shifts; specifically, rate-limited scenarios trigger more extreme buffer drops, meaning more *At\_Risk* events and potentially inflated recall.
  Generalizability to other platforms (e.g., Netflix, Twitch), transport protocols (e.g.,
  QUIC-based streaming), or network environments (e.g., high-latency satellite links)
  remains to be validated.

  Furthermore, the deployment of a single unified Random Forest introduces a trade-off between model simplicity and classification precision during
  the early phases of a flow, where feature statistics have not yet converged. Future
  work could explore context-dependent models that use a lightweight early-phase
  classifier until sufficient flow statistics have accumulated, transitioning to the full
  model thereafter.

  Finally, the current implementation does not yet close the loop between the
  Translator's classification output and active network management decisions.
  Integrating the QoE prediction result into a dynamic traffic shaping or prioritization
  policy, for example, by signaling the control plane to adjust queue weights for
  flows classified as *At\_Risk*, would complete the vision of a fully autonomous,
  in-network QoE management system.

]
