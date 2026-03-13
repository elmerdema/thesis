#let translator_architecture() =[
  #set par(first-line-indent: 1em, spacing: 1.2em, justify: true)

  == Data Plane Translator Architecture
  The "Translator" is the intelligent core of the proposed in-network telemetry system. While the Reporter component is responsible for aggregating flow statistics, the Translator consumes these statistics, executes a machine learning inference directly within the data plane, and enforces state-dependent routing policies. 
  
  Because standard decision trees rely on recursive branching (`if-else` structures) which are incompatible with the strict pipeline constraints of the Intel Tofino ASIC, the P4 program was automatically generated using a custom script (`p4_generator_tna.py`). This generator translates a trained Random Forest model into hardware-compatible Match-Action Tables (MATs).

  === Telemetry Parsing and Feature Extraction
  The Translator operates primarily on Data-Plane Telemetry Architecture (DTA) packets. Upon ingress, the custom `SwitchIngressParser` inspects the packet headers. If it detects a UDP packet destined for port `40040` with the Marina opcode (`0x05`), it transitions into specialized parsing states to extract the `dta_keyval_static_h` and `keywrite_data_h` headers.

  Once parsed, the `FeatureExtraction` control block maps the payload into the `local_metadata_t` structure. While features like `packet_count`, `ps_sum`, and `iat_sum` are extracted directly from the payload, the Translator dynamically calculates `jitter` on the fly. It does this by subtracting the flow's `last_packet_timestamp` (carried in the DTA header) from the switch's local hardware ingress timestamp (`ig_intr_md.ingress_mac_tstamp`).

  === Random Forest Hardware Mapping
  To execute a Random Forest within the Tofino data plane, the `p4_generator_tna.py` script employs two critical design patterns: Ternary Match-Action mapping and Physical Stage Unrolling.

  ==== Ternary Range Matching (TCAM)
  Decision tree nodes evaluate features using inequalities (e.g., $X_"jitter" < 500$). The Tofino ASIC evaluates inequalities using Ternary Content-Addressable Memory (TCAM). The generator maps the decision thresholds into ternary bitmasks. 
  
  Each tree is represented by a set of tables where the match keys include the `current_node` (Exact match) and the four network features (`packet_count`, `ps_sum`, `iat_sum`, `jitter`) as Ternary matches. Depending on the matched rule, the ALU executes either `action_goto_node` to traverse deeper into the tree, or `action_set_leaf` to output a class prediction.

  #figure(
    box(fill: luma(240), inset: 8pt, radius: 4pt, width: 100%)[
      #set align(left)
      ```cpp
      table tbl_tree_0_stage_0 {
          key = {
              local_md.classification_variables.current_node_tree0: exact;
              local_md.features.packet_count: ternary;
              local_md.features.ps_sum: ternary;
              local_md.features.iat_sum: ternary;
              local_md.features.jitter: ternary;
          }
          actions = {
              action_goto_node_tree_0;
              action_set_leaf_tree_0;
              NoAction;
          }
      }
      ```
    ],
    caption:[P4 representation of a decision tree node using ternary matching for feature threshold evaluation.]
  )

  ==== Physical Stage Unrolling
  The Tofino architecture enforces a strict Directed Acyclic Graph (DAG) for table execution; a table cannot recursively call itself, nor can multiple tables modifying the same metadata execute in the same physical pipeline stage. 
  
  To bypass this, the generator "unrolls" the trees. If the Random Forest relies on trees with a maximum depth of 3, the generator creates three distinct tables per tree (e.g., `tbl_tree_0_stage_0`, `tbl_tree_0_stage_1`, `tbl_tree_0_stage_2`). In the `apply` block, these tables are executed sequentially, allowing the packet to traverse from the root to the leaf node across consecutive physical ALU stages.

  === Ensemble Voting Mechanism
  Because a Random Forest consists of multiple independent decision trees (in this implementation, four trees), their individual predictions must be aggregated to form a final classification. This is handled by a dedicated `tbl_voting` match-action table.

  Instead of complex arithmetic averaging, which consumes valuable ALU cycles, the voting logic is pre-computed by the Python generator and hardcoded as exact-match entries. The table takes the four leaf outputs (`tree0_result` through `tree3_result`) as exact match keys and outputs the majority `final_class` alongside a confidence score (the vote tally).

  #figure(
    box(fill: luma(240), inset: 8pt, radius: 4pt, width: 100%)[
      #set align(left)
      ```cpp
      table tbl_voting {
          key = {
              local_md.tree0_result : exact;
              local_md.tree1_result : exact;
              local_md.tree2_result : exact;
              local_md.tree3_result : exact;
          }
          actions = { resolve_vote; NoAction; }
          const entries = {
              (0, 0, 0, 0) : resolve_vote(0, 4, 0); // 4 votes for class 0
              (1, 1, 1, 0) : resolve_vote(1, 1, 3); // 3 votes for class 1
              // ... exhaustively generated permutations
          }
      }
      ```
    ],
    caption: [Hardcoded ensemble voting logic utilizing an Exact Match table for instantaneous majority resolution.]
  )

  === State-Dependent Routing and Deparsing
  Once the `final_class` is resolved, the Translator leverages this intelligence to perform Quality of Experience (QoE) or security routing. This is governed by the `tbl_classification_action` table. 
  
  If the traffic is classified as benign (Class 0), the switch executes `forward_benign` and routes the traffic along its normal path (e.g., egress port 36). However, if the traffic is classified as critical or malicious (Class 1), the switch can execute dynamic mitigation strategies, such as `forward_to_ids` (redirecting the packet to port 64 for deep packet inspection) or `drop_malicious` to quarantine the flow entirely at line rate.

  Finally, during the Deparsing stage, the switch does not strip the telemetry. Instead, it recomputes the IPv4 checksum and emits the packet along with a newly appended `classification_h` header. This custom header encapsulates the final class result, the confidence score, and the exact tree vote distribution, allowing downstream analytics servers to verify the Tofino ASIC's in-network inference accuracy.
]