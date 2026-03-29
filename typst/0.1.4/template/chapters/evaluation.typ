#import "../lib.typ": *
#import "translator_evaluation.typ": translator_evaluation

#let evaluation() = [
  #set par(first-line-indent: 1em, spacing: 1.2em, justify: true)


  #translator_evaluation()

  == Benchmarking and Performance Analysis
  This section presents the results of the benchmarking framework developed to evaluate the practical limits of in-network #abbr("qoe") prediction. The automated pipeline, which is implemented in the #link("https://github.com/elmerdema/thesis/blob/main/code/benchmark.py")[#code("code/benchmark.py")] script, trains Random Forest models with varying hyperparameters, translates them into P4 code, and utilizes the Intel SDE compiler to evaluate architectural resource consumption.

  === Feature Scaling and Hardware Constraints
  The first major experiment evaluates the impact of the number of telemetry features ($k$) on both Machine Learning (#abbr("ml")) performance and hardware resource utilization. The sweep was conducted using a fixed configuration of 2 trees and depth 2, isolating the effect of feature count from other hyperparameters.

  #figure(
    image("../assets/benchmarks/01_feature_sweep_ml.png", width: 100%),
    caption: [#abbr("ml") performance metrics across a varying number of features ($k$).],
  )

  As shown in Figure 12, the left panel plots overall accuracy, macro F1, ROC-AUC, macro precision, and macro recall as $k$ is increased from 3 to 8. All metrics remain tightly clustered in the range of 0.75--0.76 across the entire sweep, indicating that the model's predictive power is largely saturated already at $k = 3$. The middle panel breaks this down per class: the _Steady_ class consistently achieves a precision and recall of approximately 0.80--0.81, while the _At\_Risk_ class scores approximately 0.69--0.70 throughout. Critically, neither class shows meaningful improvement as more features are added, confirming that the dominant predictive signal is concentrated in a small subset of traffic statistics. The right panel shows that #abbr("rf") training time increases monotonically from 6.0s at $k=3$ to 9.6s at $k=8$, reflecting the additional computational cost of fitting trees over a higher-dimensional feature space. This linear growth in training time, combined with the flat #abbr("ml") performance, strongly motivates restricting the deployed model to the smallest effective feature set.

  #figure(
    image("../assets/benchmarks/02_feature_sweep_hw.png", width: 100%),
    caption: [Hardware resource consumption (SRAM, #abbr("tcam"), VLIW instructions, and pipeline stages) relative to the number of features.],
  )

  Figure 13 reveals the hardware cost of expanding the feature space on the Tofino 2 #abbr("asic"). The top-left memory panel shows that SRAM consumption remains constant at approximately 8 units across all values of $k$, while #abbr("tcam") usage stays flat at roughly 15 units, both well within the device's S8/T16 budget. The number of logical table IDs is also stable at 11 throughout the sweep, meaning the structural topology of the P4 program does not change with feature count. However, the top-center panel tells a different story for VLIW instruction slots: these grow steeply and linearly from 23 at $k=3$ to 50 at $k=8$. Each additional feature introduces new ternary match keys into the decision-tree tables, expanding the instruction word required to evaluate each node. The bottom-left panel confirms that pipeline stage usage remains flat at 8 active stages for all tested values of $k$, staying well below both the soft cap of 16 and the hard maximum of 20, with compilation times growing moderately from 7s to 10s. The bottom-right scatter plot synthesises the accuracy-versus-SRAM trade-off: all configurations occupy approximately the same SRAM footprint (~8.0 units) yet show small but meaningful accuracy differences. Notably, $k=6$ achieves the highest test accuracy of 0.761 with the largest VLIW footprint (bubble size), while $k=4$ drops to only 0.757. This analysis confirms that $k=4$ (the four features ps\_sum, ps2\_sum, ps3\_sum, and jitter selected in the training pipeline) represents the optimal operating point: it delivers near-peak accuracy while minimising VLIW pressure and compilation overhead.

  However, this improvement in #abbr("ml") metrics comes at a steep cost in terms of hardware resources. The compiler reports indicate that SRAM, #abbr("tcam"), and specifically VLIW instruction slots scale rapidly as $k$ increases. The physical limit of 20 pipeline stages on the Tofino 2 architecture becomes a hard bottleneck, as demonstrated in the stage utilization heatmaps.


  === Tree and Depth Configuration Sweep
  The second experiment systematically sweeps the number of trees (3--10) and the maximum depth (d1--d5) of the Random Forest, using the fixed 4-feature set identified in the previous experiment. While larger and deeper forests naturally yield higher test accuracies and better recall, they strain the P4 compiler's ability to fit the logic within the limited hardware stages.

  #figure(
    image("../assets/benchmarks/04_tree_sweep_ml_heatmaps.png", width: 100%),
    caption: [Heatmaps correlating the number of trees and maximum depth with overall #abbr("ml") performance.],
  )

  Figure 14 presents six heatmaps covering accuracy, macro F1, ROC-AUC, macro precision, macro recall, and training time. Cells left blank (white/grey) indicate configurations that failed to compile or were not executed due to hardware infeasibility. Several trends are immediately visible. First, accuracy and F1 scores span a narrow band between approximately 0.756 and 0.763, confirming that the model's predictive ceiling is constrained by the feature set rather than the ensemble size. The highest accuracy of 0.763 is achieved at depth 1 with 7 trees, and at depth 2 with 4 trees. Increasing depth beyond d2 does not improve accuracy and, in fact, produces slight degradations for the configurations that do compile. Second, the ROC-AUC heatmap mirrors this pattern, peaking at 0.765 for depth-1 configurations and declining as depth grows. Third, and most practically significant, the training time heatmap shows that deeper configurations (d3--d5) require substantially more time (up to 21s for d3 with 5 trees), and the compilation grid shrinks dramatically: depth 3 compiles for only 3--5 trees, depth 4 for only 3--4 trees, and depth 5 for only 3 trees. This confirms a fundamental trade-off: marginal accuracy gains from deeper trees are outweighed by the exponential growth in pipeline resource requirements.

  #figure(
    image("../assets/benchmarks/05_tree_sweep_compile.png", width: 100%),
    caption: [Compilation status and estimated pipeline stages for various tree and depth configurations. Configurations exceeding the 20-stage limit fail to compile.],
  )

  Figure 15 directly maps the hardware feasibility boundary. The left panel shows the compilation status grid: all depth-1 configurations compile successfully across the full range of 3--10 trees; depth-2 succeeds for 3--6 trees; depth-3 for 3--5 trees; depth-4 for only 3--4 trees; and depth-5 only for 3 trees. All other entries are marked N/A, meaning they were either aborted due to timeouts or exceeded available resources before compilation completed. The center panel plots actual compilation times for successful runs: depth-1 configurations are fast (7--31s), while depth-4 and depth-5 reach 100s and 357s respectively, reflecting the combinatorial explosion of #abbr("tcam") entries as tree depth increases. The right panel shows the estimated pipeline stage count for each compiled configuration, with the hard cap of 16 stages marked in red. Depth-1 forests fit comfortably between 8 and 20 stages as tree count increases; depth-2 ranges from 11 to 17; depth-3 reaches 14--18; and depth-4 exceeds 17 stages even for the smallest configurations. This confirms that the 20-stage pipeline limit is the dominant hard constraint for in-network Random Forest deployment, and that configurations with depth $> 3$ combined with more than 4 trees are not viable on the current Tofino 2 hardware.

  The compilation status grid highlights the operational boundaries of in-network #abbr("ml"). Configurations that exceed a certain complexity threshold either time out during compilation or fail completely due to the exhaustion of active pipeline stages and logical table IDs.

  === Feature Importance and Resource Overview
  To optimize the models for deployment, it is crucial to understand which features contribute most to the classification. The Gini feature importances confirm that a small subset of the MARINA telemetry features provides the majority of the predictive power.

  #figure(
    image("../assets/benchmarks/07_feature_importances.png", width: 100%),
    caption: [Feature importances calculated during the feature sweep experiment.],
  )

  Figure 16 presents the Gini importance scores for each feature subset tested during the feature sweep. At $k=3$, the model splits its decision-making power almost equally between sum\_of\_packet\_size\_cubed (0.493) and sum\_of\_iat (0.484), with sum\_of\_packet\_size contributing only 0.023. At $k=4$, sum\_of\_packet\_size\_squared becomes the dominant feature (0.509), with sum\_of\_packet\_size\_cubed close behind (0.491), while both sum\_of\_packet\_size and sum\_of\_iat drop to essentially zero importance. A striking pattern emerges at $k=5$: sum\_of\_packet\_size\_cubed alone captures 0.988 of the total Gini importance, effectively collapsing the model into a near-single-feature classifier. This extreme concentration suggests that the third-order moment of the packet size distribution encodes the most discriminative signal for buffer depletion prediction. At $k=6$ and $k=7$, the importance redistributes more evenly between sum\_of\_packet\_size and its higher-order moments (~0.50 each), with all other features near zero. At $k=8$, sum\_of\_packet\_size\_cubed again dominates at 0.995, with jitter (0.001) and sum\_of\_packet\_size (0.005) playing only marginal roles. Across all configurations, IAT-based features (sum\_of\_iat, sum\_of\_iat\_squared, sum\_of\_iat\_cubed) and packet\_count consistently score at or near zero, confirming that throughput volume statistics are far more predictive of #abbr("qoe") state than timing-based features in this dataset.

  The aggregated resource overview illustrates the complex multi-dimensional trade-off between test accuracy, total SRAM allocated, active pipeline stages, and VLIW instructions. It proves that by carefully tuning the hyperparameters, an optimal configuration can be found that maximizes #abbr("qoe") prediction accuracy while remaining strictly within the hardware bounds of the Tofino 2 #abbr("asic").

  #figure(
    image("../assets/benchmarks/08_resource_overview.png", width: 100%),
    caption: [Combined resource overview mapping accuracy against SRAM usage and active stages.],
  )

  Figure 17 consolidates all successfully compiled configurations into a unified resource view. The top-left memory panel shows that feature-sweep configurations (feat\_k3 through feat\_k8) consume a uniformly low SRAM and #abbr("tcam") footprint of roughly 24 units total, while tree/depth sweep configurations scale substantially: 4t\_d4 peaks at approximately 112 units of combined SRAM and #abbr("tcam"). #abbr("tcam") dominates the memory budget in deeper configurations because each additional tree depth doubles the number of ternary match entries required per stage. The top-right panel shows that VLIW instruction counts and logical table IDs track the number of trees and depth closely: configurations such as 4t\_d3 and 5t\_d2 exceed 100 VLIW instructions, creating significant pressure on the instruction word budget. The bottom-left panel plots active pipeline stages and the critical-path length across all configurations. Feature-sweep entries cluster at 8 active stages regardless of $k$, while deeper tree configurations progressively grow toward the 20-stage maximum. The critical path, marked in red, frequently exceeds the 16-stage soft cap for configurations with depth $\geq$ 3, explaining the compiler timeouts observed in the previous analysis. Finally, the bottom-right scatter plot maps test accuracy against total SRAM, with bubble size encoding active pipeline stages and colour encoding VLIW instruction count. The Pareto-optimal region -- highest accuracy at lowest resource cost -- is occupied by configurations feat\_k6 (accuracy 0.761, SRAM ~8) and 4t\_d2 (accuracy 0.763, SRAM ~14). Configurations such as 3t\_d4 (accuracy 0.756, SRAM ~16) and 6t\_d2 (accuracy 0.756, SRAM ~21) represent poor trade-offs, consuming significantly more resources for lower or equal accuracy. This analysis confirms that shallow forests (depth 1--2) with a moderate number of trees (4--7) and a small, high-importance feature set (k=4--6) represent the practical sweet spot for deployable in-network #abbr("qoe") classification on the Tofino 2 #abbr("asic").


  == Conclusion

  This work bridges the gap between high-level machine learning models and low-level
  data plane programming, demonstrating that Quality of Experience prediction from
  encrypted video traffic is not only theoretically possible, but practically achievable within
  the strict physical constraints of modern programmable ASICs.

  === Summary of Contributions

  The central hypothesis of this thesis, that a constrained Random Forest classifier
  mapped to Ternary Match-Action Tables can perform accurate, line-rate #abbr("qoe") prediction
  within Intel Tofino, was confirmed by the experimental results. Three
  concrete contributions support this conclusion:

  First, the MARINA feature pipeline was successfully adapted for in-network deployment.
  By reducing the feature space to four hardware-feasible metrics (#code("ps_sum"), #code("ps2_sum"),
  #code("ps3_sum"), and #code("jitter")) and aggregating them over non-overlapping 50ms windows,
  the system achieved a classification accuracy of 0.76 (15 percentage points above the majority-class baseline) with an F1-score of 0.80 for the
  critical *At\_Risk* class. This demonstrates that a small, carefully selected feature
  subset can retain the majority of predictive power while remaining deployable on hardware.

  Second, the pForest architecture was successfully extended and adapted to the
  Tofino Native Architecture (TNA). The automated pipeline translates a trained scikit-learn Random Forest directly into compilable P4 code,
  unrolling each decision tree across different physical pipeline stages and encoding
  split thresholds as ternary bitmasks in #abbr("tcam"). The voting logic is pre-computed and
  hardcoded as exact-match entries, eliminating the need for costly runtime arithmetic
  in the data plane. This end-to-end automation significantly reduces the
  effort required to deploy new #abbr("ml") models onto programmable switches.

  Lastly, the sweep across tree count, depth, and feature count
  revealed that the 20-stage pipeline limit of the Tofino 2 architecture is the dominant
  bottleneck, not SRAM or #abbr("tcam"). Configurations with depth $d > 3$ and more than
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
  moments of traffic volume, #code("ps2_sum") and #code("ps3_sum"), contribute more
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
  automatic quality selection of scenario 6.

  The hardware-in-the-loop evaluation confirmed that the Tofino switch correctly
  computed stateful flow metrics, including packet counts, #abbr("iat") sums, and jitter,
  entirely within the data plane, without offloading any computation to an external
  server.


  === Limitations and Future Work

  Despite these results, several limitations should be acknowledged. The model was
  trained and evaluated on a single scenario (scenario 6, automatic quality selection) of the Würzburg #abbr("qoe") dataset.
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
  Integrating the #abbr("qoe") prediction result into a dynamic traffic shaping or prioritization
  policy, for example, by signaling the control plane to adjust queue weights for
  flows classified as *At\_Risk*, would complete the vision of a fully autonomous,
  in-network #abbr("qoe") management system.

]
