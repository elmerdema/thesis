#let modeling_pipeline() = [
  #set par(first-line-indent: 1em, spacing: 1.2em, justify: true)

  == Evolution of the Methodology
  The initial phase of this research focused on establishing a baseline classification model using "Marina-style" statistical features @marina_paper, where packet sizes and inter-arrival times were aggregated into isolated 50ms time windows using sums and moments. This earlier approach treated every time window as an independent event, relying on a simplistic labeling strategy that categorized network states solely based on the slope of buffer changes (filling versus depleting) without regard for the absolute buffer level.

  While this established a foundational correlation between traffic volume and buffer trends, the model lacked temporal context. It could not distinguish between a sudden, transient traffic drop and a sustained outage, nor could it differentiate between a benign buffer drop from a high level and a critical depletion event leading to a video stall.

  To address these limitations, the updated pipeline restructured the feature engineering process to introduce *temporal awareness* and stateful logic suitable for deployment on network switches. This shift transitioned the system from a stateless traffic analyzer to a predictive, risk-aware QoE monitor.

  === Advanced Feature Engineering: Rolling Statistics
  A raw 50ms observation is inherently noisy; a single dropped packet or a micro-burst can cause a spike in jitter that does not necessarily reflect the true network state. To smooth these fluctuations and capture the underlying trends (velocity and acceleration) of the traffic, the feature set was augmented using Exponential Moving Averages (EMA).

  EMA is particularly suitable for resource-constrained hardware, such as P4-enabled switches, because it allows for "rolling" trend analysis without requiring the storage of a large historical buffer. The switch only needs to store the previous EMA value. The EMA at time $t$ is calculated as:

  #figure(
    $ "EMA"_t = alpha dot X_t + (1 - alpha) dot "EMA"_(t-1) $,
    caption: [Exponential Moving Average formula, where $X_t$ is the current observation and $alpha$ is the smoothing factor.],
    kind: "formula",
    supplement: "Formula",
  )

  Where $X_t$ is the current observation (e.g., jitter or throughput) and $alpha$ is the smoothing factor. By calculating the EMA over a 20-window span (approx. 1 second), the model gains historical context, allowing it to react to sustained trends rather than transient noise.

  #figure(
    table(
      columns: (auto, 2fr),
      inset: 10pt,
      align: left,
      fill: (col, row) => if row == 0 { luma(230) } else { none },
      [*Derived Feature*], [*Mathematical Definition*],

      [EMA (Trend)], [$"EMA"_t = alpha dot x_t + (1-alpha) dot "EMA"_{t-1}$],

      [Lag (Immediate History)], [$x_"prev" = x_{t-1}$],

      [Rate of Change], [$Delta_"bw" = "BWE"_t - "BWE"_{t-1}$],
    ),
    caption: [Temporal features engineered to capture historical context and trends.],
  )

  === Target Class Definition: Risk-Based QoE State
  A supervised learning approach requires defined target labels. The existing approach defines a **binary classification scheme**. A "Lookahead" mechanism was implemented to inspect the buffer state 10 steps (500ms) into the future. By comparing the future buffer level ($B_{t+10}$) with the current level ($B_t$), a slope was calculated.

  The 'At_Risk' class is defined as a significant depleting trend occurring when the buffer is dropping by more than a set threshold. This allows the model to prioritize the detection of QoE violations over simple fluctuations.

  #figure(
    box(fill: luma(240), inset: 8pt, radius: 4pt, width: 100%)[
      #set align(left)
      ```python
      LOOKAHEAD_STEPS = 10       # Look 500ms into the future
      DROP_THRESHOLD = -200      # Buffer dropping by > 200ms

      # Binary label: At_Risk if buffer is dropping significantly, Steady otherwise
      df['qoe_state'] = np.where(
          (df['buffer_slope'] < DROP_THRESHOLD),
          'At_Risk',
          'Steady'
      )
      ```
    ],
    caption: [Logic used to define the ground-truth QoE target classes.],
  )

  The resulting class distribution represents `At_Risk` instances dominating the dataset (61.3%) compared to `Steady` stable samples (38.7%).

  == Preliminary Modeling and Feature Importance
  To establish a baseline for classification performance, a Random Forest Classifier was trained using 150 estimators and a maximum depth of 12. To mitigate the extreme class imbalance, the model utilized `class_weight='balanced'`, which penalizes misclassification of the minority class ("Steady") more heavily.

  The input feature vector $X$ for this baseline experiment was reduced to four core metrics: `ps_sum`, `ps2_sum`, `ps3_sum`, and `jitter`.#footnote[
    This initial experiment focused on core traffic metrics to establish a performance baseline. Other features can be used as well, however the trained model might not fit on resource-constrained devices like P4 switches.
  ]

  === Performance Evaluation
  The model was evaluated on a stratified test set (25% split). As shown in the classification report, the model demonstrated solid performance, correctly predicting the 'At_Risk' class with an F1-score of 0.80 and the 'Steady' class with an F1-score of 0.69. The overall accuracy reached 0.76.

  #figure(
    table(
      columns: (auto, 1fr, 1fr, 1fr),
      inset: 10pt,
      align: center,
      fill: (col, row) => if row == 0 { luma(230) } else { none },
      [*Class*], [*Precision*], [*Recall*], [*F1-Score*],
      [At_Risk], [0.80], [0.80], [0.80],
      [Steady], [0.69], [0.69], [0.69],
    ),
    caption: [Random Forest performance metrics for QoE state classification.],
  )

  === Feature Importance Analysis
  The Random Forest provided insights into feature relevance. The Gini importance scores revealed that the higher-order statistical moments of traffic volume (`ps2_sum`, `ps3_sum`) and the aggregate traffic volume (`ps_sum`) were the most significant predictors of the buffer's future state, collectively accounting for over 62% of the model's decision-making power.

  #figure(
    table(
      columns: (1fr, auto),
      inset: 10pt,
      align: (col, row) => if col == 0 { left } else { right },
      fill: (col, row) => if row == 0 { luma(230) } else { none },
      [*Feature*], [*Importance Score*],
      [Traffic Volume Squared (`ps2_sum`)], [0.244],
      [Traffic Volume Cubed (`ps3_sum`)], [0.197],
      [Traffic Volume (`ps_sum`)], [0.184],
      [Jitter (`jitter`)], [0.117],
    ),
    caption: [Feature importance ranking derived from the Random Forest model.],
  )

  Finally, the processed feature matrix $X$ and the one-hot encoded target variables $Y$ were exported as NumPy arrays (`.npy`) to facilitate ingestion into deep learning frameworks for subsequent experiments.
]
