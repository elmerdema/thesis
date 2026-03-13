/*
 * P4_16 for Tofino - Random Forest Classification with DTA-Marina Integration
 * Generated Code - Fixed for Tofino Compiler Constraints
 * Uses ternary tables for feature comparisons and physical stage unrolling
 */

#include <core.p4>
#include <tna.p4>


/*************************************************************************
 ***********************  H E A D E R S  *********************************
 *************************************************************************/

typedef bit<48> mac_addr_t;
typedef bit<32> ipv4_addr_t;
typedef bit<16> ether_type_t;
typedef bit<9>  port_t;
typedef bit<32> timestamp_t;

const ether_type_t ETHERTYPE_IPV4 = 0x0800;
const ether_type_t ETHERTYPE_DTA = 0x1337;

const bit<8> IPv4_PROTO_UDP = 0x11;
const bit<8> IPv4_PROTO_TCP = 0x06;

const bit<16> DTA_PORT_NUMBER = 40040;
const bit<8> DTA_OPCODE_MARINA = 0x05;

header ethernet_h {
    mac_addr_t dst_addr;
    mac_addr_t src_addr;
    ether_type_t ether_type;
}

header ipv4_h {
    bit<4>  version;
    bit<4>  ihl;
    bit<6>  dscp;
    bit<2>  ecn;
    bit<16> total_len;
    bit<16> identification;
    bit<3>  flags;
    bit<13> frag_offset;
    bit<8>  ttl;
    bit<8>  protocol;
    bit<16> hdr_checksum;
    ipv4_addr_t src_addr;
    ipv4_addr_t dst_addr;
}

header udp_h {
    bit<16> src_port;
    bit<16> dst_port;
    bit<16> length;
    bit<16> checksum;
}

header tcp_h {
    bit<16> src_port;
    bit<16> dst_port;
    bit<32> seq_no;
    bit<32> ack_no;
    bit<4>  data_offset;
    bit<4>  res;
    bit<8>  flags;
    bit<16> window;
    bit<16> checksum;
    bit<16> urgent_ptr;
}

header dta_base_h {
    bit<8> opcode;
    bit<1> immediate;
    bit<7> reserved;
}

header dta_keyval_static_h {
    bit<8>  redundancy_level;
    bit<32> key;
}

header keywrite_data_h {
    bit<32> packet_count;           
    bit<32> first_packet_timestamp; 
    bit<32> last_packet_timestamp;  
    bit<32> prev_packet_timestamp;  
    bit<32> iat_sum;                
    bit<32> iat_min;                
    bit<32> iat_max;                
    bit<32> ps_sum;                 
    bit<32> ps_min;                 
    bit<32> ps_max;                 
    bit<32> src_ip_addr;            
    bit<32> dst_ip_addr;            
    bit<16> src_port_num;           
    bit<16> dst_port_num;           
    bit<8>  protocol_type;          
}

header classification_h {
    bit<8>  class_result;           
    bit<8>  confidence;             
    bit<16> tree_votes;             
}

struct classification_features_t {
    bit<32> packet_count;           
    bit<32> ps_sum;                 
    bit<32> iat_sum;                
    bit<32> jitter;                 
}

struct classification_variables_t {
    bit<8>  current_node_tree0;
    bit<8>  current_node_tree1;
    bit<8>  current_node_tree2;
    bit<8>  current_node_tree3;
}

struct local_metadata_t {
    classification_features_t   features;
    classification_variables_t  classification_variables;
    bit<32> current_timestamp;      
    bit<8>  tree0_result;
    bit<8>  tree1_result;
    bit<8>  tree2_result;
    bit<8>  tree3_result;
    bit<16> class_votes_0;
    bit<16> class_votes_1;
    bit<8>  final_class;
    bit<1>  is_dta_packet;
    bit<1>  do_classification;
}

const local_metadata_t DEFAULT_LOCAL_MD = {
    {0, 0, 0, 0},           // features
    {0, 0, 0, 0},           // classification_variables
    0,                      // current_timestamp
    0, 0, 0, 0,             // tree results
    0, 0,                   // class_votes
    0,                      // final_class
    0, 0                    // is_dta_packet, do_classification
};

struct headers {
    ethernet_h      ethernet;
    ipv4_h          ipv4;
    udp_h           udp;
    tcp_h           tcp;
    dta_base_h      dta_base;
    dta_keyval_static_h dta_keyval;
    keywrite_data_h keywrite_data;
    classification_h classification;
}

/*************************************************************************
 ***********************  P A R S E R  ***********************************
 *************************************************************************/

parser TofinoIngressParser(
    packet_in pkt,
    out ingress_intrinsic_metadata_t ig_intr_md)
{
    state start {
        pkt.extract(ig_intr_md);
        transition select(ig_intr_md.resubmit_flag) {
            1: parse_resubmit;
            0: parse_port_metadata;
        }
    }

    state parse_resubmit {
        transition reject;
    }

    state parse_port_metadata {
        pkt.advance(64);  
        transition accept;
    }
}

parser SwitchIngressParser(
    packet_in pkt,
    out headers hdr,
    out local_metadata_t local_md,
    out ingress_intrinsic_metadata_t ig_intr_md)
{
    TofinoIngressParser() tofino_parser;

    state start {
        local_md = DEFAULT_LOCAL_MD;
        tofino_parser.apply(pkt, ig_intr_md);
        transition parse_ethernet;
    }

    state parse_ethernet {
        pkt.extract(hdr.ethernet);
        transition select(hdr.ethernet.ether_type) {
            ETHERTYPE_IPV4: parse_ipv4;
            default: accept;
        }
    }

    state parse_ipv4 {
        pkt.extract(hdr.ipv4);
        transition select(hdr.ipv4.protocol) {
            IPv4_PROTO_UDP: parse_udp;
            IPv4_PROTO_TCP: parse_tcp;
            default: accept;
        }
    }

    state parse_udp {
        pkt.extract(hdr.udp);
        transition select(hdr.udp.dst_port) {
            DTA_PORT_NUMBER: parse_dta_base;
            default: accept;
        }
    }

    state parse_tcp {
        pkt.extract(hdr.tcp);
        transition accept;
    }

    state parse_dta_base {
        pkt.extract(hdr.dta_base);
        transition select(hdr.dta_base.opcode) {
            DTA_OPCODE_MARINA: parse_dta_keyval;
            default: accept;
        }
    }

    state parse_dta_keyval {
        pkt.extract(hdr.dta_keyval);
        transition parse_keywrite_data;
    }

    state parse_keywrite_data {
        pkt.extract(hdr.keywrite_data);
        local_md.is_dta_packet = 1;
        local_md.do_classification = 1;
        transition accept;
    }
}

/*************************************************************************
 ***************  F E A T U R E   E X T R A C T I O N  *******************
 *************************************************************************/

control FeatureExtraction(
    inout headers hdr,
    inout local_metadata_t local_md,
    in ingress_intrinsic_metadata_t ig_intr_md)
{
    action extract_features_from_dta() {
        local_md.features.packet_count = hdr.keywrite_data.packet_count;
        local_md.features.ps_sum = hdr.keywrite_data.ps_sum;
        local_md.features.iat_sum = hdr.keywrite_data.iat_sum;
        local_md.features.jitter = local_md.current_timestamp - hdr.keywrite_data.last_packet_timestamp;
    }

    action capture_current_timestamp() {
        local_md.current_timestamp = ig_intr_md.ingress_mac_tstamp[31:0];
    }

    apply {
        capture_current_timestamp();
        
        if (hdr.keywrite_data.isValid()) {
            extract_features_from_dta();
        }
    }
}

/*************************************************************************
 ***************  C L A S S I F I C A T I O N  ***************************
 *************************************************************************/

control Classification(
    inout headers hdr,
    inout local_metadata_t local_md)
{
    // Tree actions and tables

    action action_goto_node_tree_0(bit<8> next_node) {
        local_md.classification_variables.current_node_tree0 = next_node;
    }

    action action_set_leaf_tree_0(bit<8> class_id) {
        local_md.tree0_result = class_id;
    }

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
        size = 256;
        default_action = NoAction;
    }

    table tbl_tree_0_stage_1 {
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
        size = 256;
        default_action = NoAction;
    }

    table tbl_tree_0_stage_2 {
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
        size = 256;
        default_action = NoAction;
    }

    action action_goto_node_tree_1(bit<8> next_node) {
        local_md.classification_variables.current_node_tree1 = next_node;
    }

    action action_set_leaf_tree_1(bit<8> class_id) {
        local_md.tree1_result = class_id;
    }

    table tbl_tree_1_stage_0 {
        key = {
            local_md.classification_variables.current_node_tree1: exact;
            local_md.features.packet_count: ternary;
            local_md.features.ps_sum: ternary;
            local_md.features.iat_sum: ternary;
            local_md.features.jitter: ternary;
        }
        actions = {
            action_goto_node_tree_1;
            action_set_leaf_tree_1;
            NoAction;
        }
        size = 256;
        default_action = NoAction;
    }

    table tbl_tree_1_stage_1 {
        key = {
            local_md.classification_variables.current_node_tree1: exact;
            local_md.features.packet_count: ternary;
            local_md.features.ps_sum: ternary;
            local_md.features.iat_sum: ternary;
            local_md.features.jitter: ternary;
        }
        actions = {
            action_goto_node_tree_1;
            action_set_leaf_tree_1;
            NoAction;
        }
        size = 256;
        default_action = NoAction;
    }

    table tbl_tree_1_stage_2 {
        key = {
            local_md.classification_variables.current_node_tree1: exact;
            local_md.features.packet_count: ternary;
            local_md.features.ps_sum: ternary;
            local_md.features.iat_sum: ternary;
            local_md.features.jitter: ternary;
        }
        actions = {
            action_goto_node_tree_1;
            action_set_leaf_tree_1;
            NoAction;
        }
        size = 256;
        default_action = NoAction;
    }

    action action_goto_node_tree_2(bit<8> next_node) {
        local_md.classification_variables.current_node_tree2 = next_node;
    }

    action action_set_leaf_tree_2(bit<8> class_id) {
        local_md.tree2_result = class_id;
    }

    table tbl_tree_2_stage_0 {
        key = {
            local_md.classification_variables.current_node_tree2: exact;
            local_md.features.packet_count: ternary;
            local_md.features.ps_sum: ternary;
            local_md.features.iat_sum: ternary;
            local_md.features.jitter: ternary;
        }
        actions = {
            action_goto_node_tree_2;
            action_set_leaf_tree_2;
            NoAction;
        }
        size = 256;
        default_action = NoAction;
    }

    table tbl_tree_2_stage_1 {
        key = {
            local_md.classification_variables.current_node_tree2: exact;
            local_md.features.packet_count: ternary;
            local_md.features.ps_sum: ternary;
            local_md.features.iat_sum: ternary;
            local_md.features.jitter: ternary;
        }
        actions = {
            action_goto_node_tree_2;
            action_set_leaf_tree_2;
            NoAction;
        }
        size = 256;
        default_action = NoAction;
    }

    table tbl_tree_2_stage_2 {
        key = {
            local_md.classification_variables.current_node_tree2: exact;
            local_md.features.packet_count: ternary;
            local_md.features.ps_sum: ternary;
            local_md.features.iat_sum: ternary;
            local_md.features.jitter: ternary;
        }
        actions = {
            action_goto_node_tree_2;
            action_set_leaf_tree_2;
            NoAction;
        }
        size = 256;
        default_action = NoAction;
    }

    action action_goto_node_tree_3(bit<8> next_node) {
        local_md.classification_variables.current_node_tree3 = next_node;
    }

    action action_set_leaf_tree_3(bit<8> class_id) {
        local_md.tree3_result = class_id;
    }

    table tbl_tree_3_stage_0 {
        key = {
            local_md.classification_variables.current_node_tree3: exact;
            local_md.features.packet_count: ternary;
            local_md.features.ps_sum: ternary;
            local_md.features.iat_sum: ternary;
            local_md.features.jitter: ternary;
        }
        actions = {
            action_goto_node_tree_3;
            action_set_leaf_tree_3;
            NoAction;
        }
        size = 256;
        default_action = NoAction;
    }

    table tbl_tree_3_stage_1 {
        key = {
            local_md.classification_variables.current_node_tree3: exact;
            local_md.features.packet_count: ternary;
            local_md.features.ps_sum: ternary;
            local_md.features.iat_sum: ternary;
            local_md.features.jitter: ternary;
        }
        actions = {
            action_goto_node_tree_3;
            action_set_leaf_tree_3;
            NoAction;
        }
        size = 256;
        default_action = NoAction;
    }

    table tbl_tree_3_stage_2 {
        key = {
            local_md.classification_variables.current_node_tree3: exact;
            local_md.features.packet_count: ternary;
            local_md.features.ps_sum: ternary;
            local_md.features.iat_sum: ternary;
            local_md.features.jitter: ternary;
        }
        actions = {
            action_goto_node_tree_3;
            action_set_leaf_tree_3;
            NoAction;
        }
        size = 256;
        default_action = NoAction;
    }


    // Voting Table and Action

    action resolve_vote(bit<8> result_class, bit<16> v0, bit<16> v1) {
        local_md.final_class = result_class;
        local_md.class_votes_0 = v0;
        local_md.class_votes_1 = v1;
    }

    table tbl_voting {
        key = {
            local_md.tree0_result : exact;
            local_md.tree1_result : exact;
            local_md.tree2_result : exact;
            local_md.tree3_result : exact;
        }
        actions = {
            resolve_vote;
            NoAction;
        }
        const entries = {
            (0, 0, 0, 0) : resolve_vote(0, 4, 0);
            (1, 0, 0, 0) : resolve_vote(0, 3, 1);
            (0, 1, 0, 0) : resolve_vote(0, 3, 1);
            (1, 1, 0, 0) : resolve_vote(0, 2, 2);
            (0, 0, 1, 0) : resolve_vote(0, 3, 1);
            (1, 0, 1, 0) : resolve_vote(0, 2, 2);
            (0, 1, 1, 0) : resolve_vote(0, 2, 2);
            (1, 1, 1, 0) : resolve_vote(1, 1, 3);
            (0, 0, 0, 1) : resolve_vote(0, 3, 1);
            (1, 0, 0, 1) : resolve_vote(0, 2, 2);
            (0, 1, 0, 1) : resolve_vote(0, 2, 2);
            (1, 1, 0, 1) : resolve_vote(1, 1, 3);
            (0, 0, 1, 1) : resolve_vote(0, 2, 2);
            (1, 0, 1, 1) : resolve_vote(1, 1, 3);
            (0, 1, 1, 1) : resolve_vote(1, 1, 3);
            (1, 1, 1, 1) : resolve_vote(1, 0, 4);
        }
        default_action = NoAction;
    }


    action init_classification() {
        local_md.classification_variables.current_node_tree0 = 0;
        local_md.classification_variables.current_node_tree1 = 0;
        local_md.classification_variables.current_node_tree2 = 0;
        local_md.classification_variables.current_node_tree3 = 0;
        local_md.tree0_result = 0;
        local_md.tree1_result = 0;
        local_md.tree2_result = 0;
        local_md.tree3_result = 0;
    }

    action write_classification_result() {
        hdr.classification.setValid();
        hdr.classification.class_result = local_md.final_class;
        hdr.classification.confidence = (bit<8>)(local_md.class_votes_0 + local_md.class_votes_1);
        hdr.classification.tree_votes = local_md.class_votes_0[7:0] ++ local_md.class_votes_1[7:0];
    }

    apply {
        if (local_md.do_classification == 1) {
            init_classification();
            
            // Run Trees using physically unrolled stages

            // Tree 0 execution (max depth 3)
            tbl_tree_0_stage_0.apply();
            tbl_tree_0_stage_1.apply();
            tbl_tree_0_stage_2.apply();
            // Tree 1 execution (max depth 3)
            tbl_tree_1_stage_0.apply();
            tbl_tree_1_stage_1.apply();
            tbl_tree_1_stage_2.apply();
            // Tree 2 execution (max depth 3)
            tbl_tree_2_stage_0.apply();
            tbl_tree_2_stage_1.apply();
            tbl_tree_2_stage_2.apply();
            // Tree 3 execution (max depth 3)
            tbl_tree_3_stage_0.apply();
            tbl_tree_3_stage_1.apply();
            tbl_tree_3_stage_2.apply();
            
            // Resolve Votes (Majority) using Match-Action Table
            tbl_voting.apply();
            
            // Write Result
            write_classification_result();
        }
    }
}

/*************************************************************************
 ***********************  I N G R E S S  *********************************
 *************************************************************************/

control SwitchIngress(
    inout headers hdr,
    inout local_metadata_t local_md,
    in ingress_intrinsic_metadata_t ig_intr_md,
    in ingress_intrinsic_metadata_from_parser_t ig_intr_prsr_md,
    inout ingress_intrinsic_metadata_for_deparser_t ig_dprsr_md,
    inout ingress_intrinsic_metadata_for_tm_t ig_tm_md)
{
    FeatureExtraction() feature_extraction;
    Classification() classification;

    action forward(port_t egress_port) {
        ig_tm_md.ucast_egress_port = egress_port;
    }

    action drop() {
        ig_dprsr_md.drop_ctl = 1;
    }

    action send_to_cpu() {
        ig_tm_md.ucast_egress_port = 64;
    }

    table tbl_forward {
        key = {
            hdr.ipv4.dst_addr: exact;
        }
        actions = {
            forward;
            send_to_cpu;
            drop;
        }
        default_action = send_to_cpu;
        size = 1024;
    }

    action forward_benign(port_t egress_port) {
        ig_tm_md.ucast_egress_port = egress_port;
    }

    action forward_to_ids(port_t ids_port) {
        ig_tm_md.ucast_egress_port = ids_port;
    }

    action drop_malicious() {
        ig_dprsr_md.drop_ctl = 1;
    }

    table tbl_classification_action {
        key = {
            local_md.final_class: exact;
        }
        actions = {
            forward_benign;
            forward_to_ids;
            drop_malicious;
            NoAction;
        }
        const entries = {
            0: forward_benign(36);
            1: forward_to_ids(64);
        }
        default_action = NoAction;
        size = 16;
    }

    apply {
        if (local_md.is_dta_packet == 1) {
            feature_extraction.apply(hdr, local_md, ig_intr_md);
            classification.apply(hdr, local_md);
            tbl_classification_action.apply();
        } else {
            if (hdr.ipv4.isValid()) {
                tbl_forward.apply();
            }
        }
    }
}

/*************************************************************************
 ***********************  D E P A R S E R  *******************************
 *************************************************************************/

control SwitchIngressDeparser(
    packet_out pkt,
    inout headers hdr,
    in local_metadata_t local_md,
    in ingress_intrinsic_metadata_for_deparser_t ig_dprsr_md)
{
    Checksum() ipv4_checksum;

    apply {
        hdr.ipv4.hdr_checksum = ipv4_checksum.update({
            hdr.ipv4.version,
            hdr.ipv4.ihl,
            hdr.ipv4.dscp,
            hdr.ipv4.ecn,
            hdr.ipv4.total_len,
            hdr.ipv4.identification,
            hdr.ipv4.flags,
            hdr.ipv4.frag_offset,
            hdr.ipv4.ttl,
            hdr.ipv4.protocol,
            hdr.ipv4.src_addr,
            hdr.ipv4.dst_addr
        });

        pkt.emit(hdr.ethernet);
        pkt.emit(hdr.ipv4);
        pkt.emit(hdr.udp);
        pkt.emit(hdr.tcp);
        pkt.emit(hdr.dta_base);
        pkt.emit(hdr.dta_keyval);
        pkt.emit(hdr.keywrite_data);
        pkt.emit(hdr.classification);
    }
}

parser SwitchEgressParser(
    packet_in pkt,
    out headers hdr,
    out local_metadata_t local_md,
    out egress_intrinsic_metadata_t eg_intr_md)
{
    state start {
        local_md = DEFAULT_LOCAL_MD;
        pkt.extract(eg_intr_md);
        transition parse_ethernet;
    }

    state parse_ethernet {
        pkt.extract(hdr.ethernet);
        transition accept;
    }
}

control SwitchEgress(
    inout headers hdr,
    inout local_metadata_t local_md,
    in egress_intrinsic_metadata_t eg_intr_md,
    in egress_intrinsic_metadata_from_parser_t eg_intr_from_prsr,
    inout egress_intrinsic_metadata_for_deparser_t eg_intr_md_for_dprsr,
    inout egress_intrinsic_metadata_for_output_port_t eg_intr_md_for_oport)
{
    apply { }
}

control SwitchEgressDeparser(
    packet_out pkt,
    inout headers hdr,
    in local_metadata_t local_md,
    in egress_intrinsic_metadata_for_deparser_t eg_dprsr_md)
{
    apply {
        pkt.emit(hdr);
    }
}

/*************************************************************************
 ***********************  P I P E L I N E  *******************************
 *************************************************************************/

Pipeline(
    SwitchIngressParser(),
    SwitchIngress(),
    SwitchIngressDeparser(),
    SwitchEgressParser(),
    SwitchEgress(),
    SwitchEgressDeparser()
) pipe;

Switch(pipe) main;
