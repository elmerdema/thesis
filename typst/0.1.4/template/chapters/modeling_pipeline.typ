#let modeling_pipeline() = [
  #set par(first-line-indent: 1em, spacing: 1.2em, justify: true)

  === Advanced Feature Engineering and Temporal Context
  While the initial processing aggregated raw packet statistics into 50ms windows, network conditions are inherently temporal. A single 50ms snapshot lacks the context of preceding traffic trends. To address this, the feature set was augmented with historical context using Exponential Moving Averages (EMA) and Lag features.

  The dataset was first sorted by `video_id` and `timestamp` to ensure chronological integrity. For every window $t$, the EMA was calculated with a span of 20 periods (approx. 1 second of history), simulating a "running average" state that a network switch might maintain. Additionally, lag features ($x_{t-1}$) and the rate of change (first-order difference) were computed to capture immediate fluctuations in bandwidth and jitter.

  #figure(
    table(
      columns: (auto, 2fr),
      inset: 10pt,
      align: left,
      fill: (col, row) => if row == 0 { luma(230) } else { none },
      [*Derived Feature*], [*Mathematical Definition*],
      
      [EMA (20-span)], 
      [$"EMA"_t = alpha dot x_t + (1-alpha) dot "EMA"_{t-1}$],

      [Lag (History)], 
      [$x_"prev" = x_{t-1}$],

      [Rate of Change], 
      [$Delta_"bw" = "BWE"_t - "BWE"_{t-1}$]
    ),
    caption: [Temporal features engineered to capture historical context and trends.]
  )

  === Target Class Definition: QoE State
  A supervised learning approach requires well-defined target labels. Instead of predicting the raw buffer level (a regression task), it defines discrete "Quality of Experience (QoE) States" based on the future trajectory of the playback buffer.

  A "Lookahead" mechanism was implemented to inspect the buffer state 10 steps (500ms) into the future. By comparing the future buffer level ($B_{t+10}$) with the current level ($B_t$), a slope was calculated. This slope, combined with a critical safety threshold (2000ms), categorized the network state into three distinct classes:

  #figure(
    box(fill: luma(240), inset: 8pt, radius: 4pt, width: 100%)[
      #set align(left)
      ```python
      LOOKAHEAD_STEPS = 10       # 500ms into the future
      CRITICAL_BUFFER_MS = 2000  # Safety threshold
      DROP_THRESHOLD = -200      # Significant drain rate

      # Logic for labeling QoE States
      if slope < -200 and buffer < 2000:
          state = "Critical"      # Immediate danger of stalling
      elif slope < -200 and buffer >= 2000:
          state = "Safe_Drain"    # Draining, but reserve exists
      else:
          state = "Steady"        # Stable or growing buffer
      ```
    ],
    caption: [Logic used to define the ground-truth QoE target classes.]
  )

  The resulting class distribution was highly imbalanced, with "Safe_Drain" dominating the dataset (61.3%) and "Critical" instances, the most important cases to detect, representing only 0.04% of the samples.

  == Preliminary Modeling and Feature Importance
  To establish a baseline for classification performance, a Random Forest Classifier was trained. The model utilized 150 estimators with a maximum depth of 12. To mitigate the extreme class imbalance observed in the target variable, the model was initialized with `class_weight='balanced'`, which penalizes misclassification of the minority class ("Critical") more heavily.

  The input feature vector $X$ for this baseline experiment was reduced to four core metrics: `packet_count`, `ps_sum`, `iat_sum`, and `jitter`.#footnote[
    This initial experiment focused on core traffic metrics to establish a performance baseline. Other features can be used as well, however the trained model might not fit on resource-constrained devices like P4 switches.
  ]
  === Performance Evaluation
  The model was evaluated on a stratified test set (25% split). As shown in the classification report, the model struggled significantly with the "Critical" class due to the scarcity of samples (only 19 support instances in the test set). While Recall for "Critical" cases was high (0.95), the Precision was near zero, indicating a high false-positive rate.

  #figure(
    table(
      columns: (auto, 1fr, 1fr, 1fr),
      inset: 10pt,
      align: center,
      fill: (col, row) => if row == 0 { luma(230) } else { none },
      [*Class*], [*Precision*], [*Recall*], [*F1-Score*],
      [Critical], [0.00], [0.95], [0.00],
      [Safe_Drain], [0.78], [0.02], [0.03],
      [Steady], [0.69], [0.69], [0.69],
    ),
    caption: [Baseline Random Forest performance metrics showing the impact of class imbalance.]
  )

  === Feature Importance Analysis
  Despite the classification challenges, the Random Forest provided insights into feature relevance. The Gini importance scores revealed that traffic volume (`ps_sum`) and instantaneous jitter (`jitter`) were the most significant predictors of the buffer's future state, collectively accounting for over 65% of the model's decision-making power.

  #figure(
    table(
      columns: (1fr, auto),
      inset: 10pt,
      align: (col, row) => if col == 0 { left } else { right },
      fill: (col, row) => if row == 0 { luma(230) } else { none },
      [*Feature*], [*Importance Score*],
      [Traffic Volume (`ps_sum`)], [0.354],
      [Jitter (`jitter`)], [0.302],
      [IAT Sum (`iat_sum`)], [0.186],
      [Packet Count], [0.158],
    ),
    caption: [Feature importance ranking derived from the Random Forest model.]
  )
  
  Finally, the processed feature matrix $X$ and the one-hot encoded target variables $Y$ were exported as NumPy arrays (`.npy`) to be ingested into deep learning frameworks for other experiments.
]