#import "../lib.typ": *
#let pforest_implementation() = [
  #set par(first-line-indent: 1em, spacing: 1.2em, justify: true)

  == Model Training via pForest
  Following the feature engineering chapter,  a simplified version of the **pForest** @busse_grawitz_pforest_in_network_inference architecture was adopted to enable in-network inference on the Intel Tofino switch.

  This phase uses the pre-processed datasets (`np_data.npy` (features) and `np_dummies.npy` (labels)) from the previous step.
  These files contain the  statistical snapshots required to train the decision trees.

  #figure(
    caption: [Files for the #abbr("rf") training logic],
    raw(
      block: true,
      lang: "terminal",
      "├── p4_generator_tna.py
├── randomforest
│   ├── randomForestEncode.py
│   ├── rf_model.py
│   ├── storage
│   │   ├── np_data.npy
│   │   └── np_dummies.npy
│   ├── tester.py
│   └── voting_table_gen.py",
    ),
  )


  === The Training Pipeline (#link("https://github.com/elmerdema/thesis/blob/main/code/rf_model.py")[rf_model.py])
  The training logic is found in the #link("https://github.com/elmerdema/thesis/blob/main/code/src/randomforest/rf_model.py")[rf_model.py] script. While it imports the standard `scikit` library, the pipeline is constrained by the hardware limitations of the Tofino architecture,
  specifically the available Match-Action Table (#abbr("mat")) resources and #abbr("sram") capacity.#footnote[#link("https://www.intel.com/content/www/us/en/products/sku/218647/intel-tofino-2-6-4-tbps-4-pipelines/specifications.html")[Intel Tofino 1] has around 10 Mbit of SRAM per stage, while Tofino 2 explicitly includes 16 Mbit per stage. ]

  To ensure the trained model can be compiled to the P4 data plane, the script performs two critical adaptations:

  + *Hardware-Constrained Feature Selection:* Although the initial dataset contains a rich set of features, the Tofino switch cannot efficiently track high-dimensional state vectors for every flow without exhausting memory. Consequently, the training script explicitly reduces the feature space to the four most impactful metrics identified during the preliminary analysis:
    - Index 1: `ps_sum` (Traffic Volume)
    - Index 2: `ps2_sum` (Traffic Volume Squared)
    - Index 3: `ps3_sum` (Traffic Volume Cubed)
    - Index 7: `jitter`

  + *Hyperparameter Tying:* The model complexity is controlled via `num_trees` and `max_depth`. In this context, `max_depth` dictates the number of pipeline stages required for a decision, while `num_trees` impacts the parallel lookup width.

  #figure(
    raw(
      lang: "python",
      block: true,
      "def build_and_train_random_forest(num_trees, max_depth):
    features = np.load(\".../storage/np_data.npy\", allow_pickle=True)
    labels = np.load(\".../storage/np_dummies.npy\", allow_pickle=True)

    # REDUCED: Select only top 4 features to fit Tofino constraints
    # Indices: 1=ps_sum, 2=ps2_sum, 3=ps3_sum, 7=jitter
    feature_indices = [1, 2, 3, 7]
    features = features[:, feature_indices]

    rf = RandomForestClassifier(n_estimators=num_trees, max_depth=max_depth)
    rf.fit(train_features, train_labels)
    return rf",
    ),
    caption: [Excerpt from #link("https://github.com/elmerdema/thesis/blob/main/code/rf_model.py")[rf_model.py] demonstrating the loading of exported NumPy data and hardware-specific feature pruning.],
  )

  === Deviation from Original pForest Architecture
  A significant architectural distinction exists between the original pForest code @roxennnn_pforest_src and our implementation. The original paper proposes *context-dependent* #abbr("rf")s, where distinct models are trained for different phases of a flow (e.g., one model for the first 5 packets, another for packets 6-10). This allows for highly specialized early detection. @busse_grawitz_pforest_in_network_inference

  In contrast, our implementation deploys a **Single Unified #abbr("rf")**. This model is trained on the features of *completed* flows (whole-flow statistics) but is applied to live traffic where features accumulate incrementally.

  === Automated P4 Code Generation (#link("https://github.com/elmerdema/thesis/blob/main/code/p4_generator_tna.py")[p4_generator_tna.py])
  To bridge the gap between the trained model and the hardware implementation, the system uses #link("https://github.com/elmerdema/thesis/blob/main/code/p4_generator_tna.py")[p4_generator_tna.py]. This script builds the P4 program, ensuring compliance with Tofino's strict resource constraints,such as Ternary Content Addressable Memory (#abbr("tcam")) usage and stage limitations.

  The pForest script is managed by a single main function, `generate_full_p4_code`. This function accepts the model's structural hyperparameters (`num_trees`, `max_depth`) and sequentially assembles the pipeline components: identifying necessary headers, generating the "physically unrolled" match-action tables for the decision trees, and constructing the static voting logic.


  The final output is written to `rf_classifier_dta_marina.p4`, producing a fully compilable network program that integrates the specific #abbr("rf") logic into the switch's standard forwarding behavior.
]
