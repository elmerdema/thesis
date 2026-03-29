#import "../lib.typ": *
#let translator_architecture() = [
  #set par(first-line-indent: 1em, spacing: 1.2em, justify: true)

  == Data Plane Translator Architecture
  The "Translator" is the intelligent core of the proposed in-network telemetry system. While the Reporter component is responsible for aggregating flow statistics, the Translator consumes these statistics, executes a machine learning inference directly within the data plane, and enforces state-dependent routing policies.

  Because standard decision trees rely on recursive branching (#code("if-else") structures) which are incompatible with the strict pipeline constraints of the Intel Tofino #abbr("asic"), the P4 program was automatically generated using a custom script (#link("https://github.com/elmerdema/thesis/blob/main/code/p4_generator_tna.py")[#code("p4_generator_tna.py")]). This generator translates a trained Random Forest model into hardware-compatible Match-Action Tables (#abbrpl("mat")).

  #figure(
    image("../assets/translator.png", width: 100%),
    caption: [
      Translator is a #abbr("dta") translator switch. This switch will intercept #abbr("dta") reports and convert these into #abbr("rdma") traffic. It is in charge of establishing and managing #abbr("rdma") queue-pairs with the collector server.
      #link("https://github.com/jonlanglet/DTA")[
        Source
      ]
    ],
  )


  === Telemetry Parsing and Feature Extraction
  The Translator operates primarily on Data-Plane Telemetry Architecture (#abbr("dta")) packets. Upon ingress, the custom #code("SwitchIngressParser") inspects the packet headers. If it detects a #abbr("udp") packet destined for port #code("40040") with the Marina opcode (#code("0x05")), it transitions into specialized parsing states to extract the #code("dta_keyval_static_h") and #code("keywrite_data_h") headers.

  Once parsed, the #code("FeatureExtraction") control block maps the payload into the #code("local_metadata_t") structure. While features like #code("packet_count"), #code("ps_sum"), and #code("iat_sum") are extracted directly from the payload, the Translator dynamically calculates #code("jitter") on the fly. It does this by subtracting the flow's #code("last_packet_timestamp") (carried in the #abbr("dta") header) from the switch's local hardware ingress timestamp (#code("ig_intr_md.ingress_mac_tstamp")).

  === Random Forest Hardware Mapping
  To execute a Random Forest within the Tofino data plane, the #link("https://github.com/elmerdema/thesis/blob/main/code/src/p4_generator_tna.py")[#code("p4_generator_tna.py")] script employs two critical design patterns: Ternary Match-Action mapping and Physical Stage Unrolling.

  ==== Ternary Range Matching (#abbr("tcam"))
  Decision tree nodes evaluate features using inequalities (e.g., $X_"jitter" < 500$). The Tofino #abbr("asic") evaluates inequalities using Ternary Content-Addressable Memory (#abbr("tcam")). The generator maps the decision thresholds into ternary bitmasks.

  Each tree is represented by a set of tables where the match keys include the #code("current_node") (Exact match) and the four network features (#code("packet_count"), #code("ps_sum"), #code("iat_sum"), #code("jitter")) as Ternary matches. Depending on the matched rule, the ALU executes either #code("action_goto_node") to traverse deeper into the tree, or #code("action_set_leaf") to output a class prediction.

  #figure(
    box(fill: luma(240), inset: 8pt, radius: 4pt, width: 100%)[
      #set align(left)
      ```p4
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
    caption: [P4 representation of a decision tree node using ternary matching for feature threshold evaluation.],
  )

  ==== Physical Stage Unrolling
  The Tofino architecture enforces a strict Directed Acyclic Graph (#abbr("dag")) for table execution; a table cannot recursively call itself, nor can multiple tables modifying the same metadata execute in the same physical pipeline stage.

  To bypass this, the generator "unrolls" the trees. If the Random Forest relies on trees with a maximum depth of 3, the generator creates three distinct tables per tree (e.g., #code("tbl_tree_0_stage_0"), #code("tbl_tree_0_stage_1"), #code("tbl_tree_0_stage_2")). In the #code("apply") block, these tables are executed sequentially, allowing the packet to traverse from the root to the leaf node across consecutive physical ALU stages.

  === Voting Mechanism
  Because a Random Forest consists of multiple independent decision trees (in this implementation, four trees), their individual predictions must be aggregated to form a final classification. This is handled by a dedicated #code("tbl_voting") match-action table.

  To conserve limited Arithmetic Logic Unit (ALU) cycles, the voting logic is pre-computed by the Python generator and hardcoded as exact-match entries. The table takes the four leaf outputs (#code("tree0_result") through #code("tree3_result")) as exact match keys and outputs the majority #code("final_class") alongside a confidence score (the vote tally).



  === State-Dependent Routing and Deparsing
  Once the #code("final_class") is resolved, the Translator uses this result to perform Quality of Experience (#abbr("qoe")) or security routing. This is controlled by the #code("tbl_classification_action") table.

  If the traffic is classified as benign (Class 0), the switch executes #code("forward_benign") and routes the traffic along its normal path (e.g., egress port 36). However, if the traffic is classified as critical or malicious (Class 1), the switch can execute dynamic mitigation strategies, such as #code("forward_to_ids") (redirecting the packet to port 64 for deep packet inspection) or #code("drop_malicious") to quarantine the flow entirely at line rate.

  Finally, during the Deparsing stage, the switch does not strip the telemetry. Instead, it recomputes the IPv4 checksum and emits the packet along with a newly appended #code("classification_h") header. This custom header encapsulates the final class result, the confidence score, and the exact tree vote distribution, allowing downstream analytics servers to verify the Tofino ASIC's in-network inference accuracy.
]
