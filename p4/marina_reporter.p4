//Reporter

#define ETHERTYPE_IPV4 0x0800
#define PROTOCOL_TCP 0x06
#define PROTOCOL_UDP 0x11

#define DTA_PORT_NUMBER 40040

#include <core.p4>
#include <tna.p4>

#include "Marina/config.p4"
#include "Marina/table_sizes.p4"

typedef bit<48> mac_addr_t;
typedef bit<32> ipv4_addr_t;

typedef bit<32> debug_t;
typedef bit<16> random_t;
typedef bit<16> telemetry_checksum_t;
typedef bit<16> telemetry_checksum_cache_index_t; //Make sure this is log(CHECKSUM_CACHE_REGISTER_SIZE)
typedef bit<32> telemetry_key_t;    //32-Bit value for FlowID in packets
typedef bit<32> telemetry_data_t;
typedef bit<8>  collector_hash_t; //Ensure the lookup table is populated with 2^collector_hash_t entries
typedef bit<20> flow_id_t;          //20-Bit value necessary for register index
//45 B
struct marina_data_t
{
    bit<32> packet_count;                   //Packet count              32 bit | 4 B
    bit<32> last_packet_timestamp;          //Last packet timestamp     32 bit | 4 B
    bit<32> sum_of_iat;                     //Sum of IAT                32 bit | 4 B
    bit<32> sum_of_iat_squared;             //Sum of IAT^2              32 bit | 4 B
    bit<32> sum_of_iat_cubed;               //Sum of IAT^3              32 bit | 4 B
    bit<32> sum_of_packet_size;             //Sum of packet size        32 bit | 4 B
    bit<32> sum_of_packet_size_squared;     //Sum of packet size ^2     32 bit | 4 B
    bit<32> sum_of_packet_size_cubed;       //Sum of packet size ^3     32 bit | 4 B
    bit<32> jitter;                         //Latest jitter             32 bit | 4 B
    bit<32> src_ip_addr;                    //src IP addr               32 bit | 4 B
    bit<32> dst_ip_addr;                    //dst IP addr               32 bit | 4 B
    bit<16> src_port_num;                   //src port num              16 bit | 2 B
    bit<16> dst_port_num;                   //dst port num              16 bit | 2 B
    bit<8>  protocol_type;                  //protocol type              8 bit | 1 B
                                            //                  Sum:   392 bit | 49 B
}

//DigestTypes
const DigestType_t DTADigest = 0;
const DigestType_t TrackingDigest = 1;

struct l4_lookup_t
{
    bit<16> srcPort;
    bit<16> dstPort;
}

//Handling metadata bridging
typedef bit<8>  pkt_type_t;
const pkt_type_t PKT_TYPE_NORMAL = 1;
const pkt_type_t PKT_TYPE_MIRROR = 2;

//Handling mirror type
// Tofino2 intrinsic mirror_type is bit<4> (see ingress_intrinsic_metadata_for_deparser_t)
typedef bit<4> mirror_type_t;
const mirror_type_t MIRROR_TYPE_I2E = 1;
const mirror_type_t MIRROR_TYPE_E2E = 2;

//Marina Types
enum bit<8> tracking_t
{
    stop_tracking = 0,
    start_tracking = 1
};

header ethernet_h
{
    mac_addr_t dstAddr;
    mac_addr_t srcAddr;
    bit<16> etherType;
}

//20 B
header ipv4_h
{
    bit<4>  version;
    bit<4>  ihl;
    bit<6>  dscp;
    bit<2>  ecn;
    bit<16> totalLen;
    bit<16> identification;
    bit<4>  flags;
    bit<12> fragOffset;
    bit<8>  ttl;
    bit<8>  protocol;
    bit<16> hdrChecksum;
    ipv4_addr_t srcAddr;
    ipv4_addr_t dstAddr;
}

//24 B
header tcp_h
{
    bit<16> srcPort;
    bit<16> dstPort;
    bit<32> seqNum;
    bit<32> ackNum;
    bit<4>  dataOffset;
    bit<6>  reserved;
    bit<4>  ctrlBits;
    bit<1>  syn;
    bit<1>  fin;
    bit<16> window;
    bit<16> checksum;
    bit<16> urgentPtr;
    bit<24> options;
    bit<8>  padding;
}

//8 B
header udp_h
{
    bit<16> srcPort;
    bit<16> dstPort;
    bit<16> length;
    bit<16> checksum;
}

//2 B
header dta_base_h
{
    bit<8>  opcode;
    bit<1>  immediate;
    bit<7>  reserverd;
}

//split data from keywrite as Tofino max header length is 48 B
//5 B
header dta_keywrite_static_h
{
    bit<8> redundancyLevel;
    telemetry_key_t telemetry_key;
    //marina_data_t telemetry_data;
}

//45 B
header dta_keywrite_data_h
{
    marina_data_t telemetry_data;
}

header mirror_h
{
	pkt_type_t pkt_type;
	telemetry_key_t telemetry_key;
	bit<32> last_timestamp;
}

header mirror_bridged_metadata_h
{
	pkt_type_t pkt_type;
	telemetry_key_t telemetry_key;
	bit<32> last_timestamp;
}

//some information must be bridged from ingress to egress for Marina
header marina_bridged_metadata_h
{
    //ingress_mac_tstamp is only available in ingress_intrinsic_metadata
    bit<32> timestamp;

    //ita
    bit<8>  iat_log;
    bit<16> iat_log_square;
    bit<16> iat_log_cube;

    //jitter
    bit<32> jitter;
}

struct header_t
{
    mirror_bridged_metadata_h bridged_md;
    marina_bridged_metadata_h marina_bridged_md;
    ethernet_h ethernet;
    ipv4_h ipv4;
    tcp_h tcp;
    udp_h udp;
    dta_base_h dta_base;
    dta_keywrite_static_h dta_keywrite;
    dta_keywrite_data_h dta_keywrite_data;
}

struct debug_digest_ingress_t
{
	random_t random;
	debug_t debug;
}

struct debug_digest_egress_t
{
	debug_t debug;
}

struct tracking_digest_t
{
    tracking_t tracking;
    ipv4_addr_t srcAddr;
    ipv4_addr_t dstAddr;
    bit<16> srcPort;
    bit<16> dstPort;
    bit<8>  protocol;
}

struct ingress_metadata_t
{
	debug_t debug; //Used for debug data (included in digest)
	random_t random;
	
	bit<1> generate_report;
	bit<1> detected_change; //If a change was detected
	
	pkt_type_t pkt_type;
	MirrorId_t mirror_session;
	
	telemetry_checksum_t telemetry_checksum;
	telemetry_checksum_cache_index_t telemetry_checksum_cache_index;
	telemetry_checksum_t checksum_to_insert_into_cache;
	telemetry_checksum_t last_telemetry_checksum_cache_element;

    tracking_t tracking;
    l4_lookup_t l4_lookup;

    //Marina metadata
    flow_id_t flow_id;
    bit<1>  ignore_flow;
    bit<32> timestamp;
    bit<32> timestamp_nsec;
    
    bit<32> last_timestamp;
    bit<32> iat;
    bit<32> last_iat;
    bit<32> jitter;
    bit<8>  iat_log;
    bit<16> iat_log_square;
    bit<16> iat_log_cube;

    bit<1> is_in_bloomfiter_1;
    bit<1> is_in_bloomfiter_2;
    bit<1> is_in_bloomfiter_3;
    bit<1> is_in_bloomfiter_4;
}

struct egress_metadata_t
{
	bit<1> is_report_packet;
	debug_t debug;
	
	marina_data_t telemetry_data;
	
	collector_hash_t collector_hash;
	ipv4_addr_t collector_ip;
    mac_addr_t collector_mac;

    l4_lookup_t l4_lookup;

    //Marina metadata
    flow_id_t flow_id;
    bit<32> timestamp_nsec;
    bit<32> timestamp;

    bit<32> last_timestamp;

    //ita
    bit<8>  iat_log;
    bit<16> iat_log_square;
    bit<32> iat_log_cube;
    //jitter
    bit<32> jitter;
    //size
    bit<8>  size_log;
    bit<8>  size_log_square;
    bit<32> size_log_cube;
    //substract from pkt_length because Marina expects size without headers
    bit<16> headers_size;
    bit<16> size;
}

parser TofinoIngressParser(
    packet_in pkt,
    out ingress_intrinsic_metadata_t ig_intr_md)
{
    state start
    {
        pkt.extract(ig_intr_md);
        transition select(ig_intr_md.resubmit_flag)
        {
            1: parse_resubmit;
            0: parse_port_metadata;
        }
    }

    state parse_resubmit
    {
        transition reject;
    }

    state parse_port_metadata
    {
        pkt.advance(PORT_METADATA_SIZE);
        transition accept;
    }
}

@pa_auto_init_metadata
parser SwitchIngressParser(
    packet_in pkt,
    out header_t hdr,
    out ingress_metadata_t ig_md,
    out ingress_intrinsic_metadata_t ig_intr_md)
{
    TofinoIngressParser() tofino_parser;

    state start
    {
        tofino_parser.apply(pkt, ig_intr_md);
        transition parse_ethernet;
    }

    state parse_ethernet
    {
        pkt.extract(hdr.ethernet);
        transition select(hdr.ethernet.etherType)
        {
            ETHERTYPE_IPV4: parse_ipv4;
            default: accept;
        }
    }

    state parse_ipv4
    {
        pkt.extract(hdr.ipv4);
        transition select(hdr.ipv4.protocol)
        {
            PROTOCOL_TCP: parse_tcp;
            PROTOCOL_UDP: parse_udp;
            default: accept;
        }
    }

    state parse_tcp
    {
        pkt.extract(hdr.tcp);
        ig_md.l4_lookup.srcPort = hdr.tcp.srcPort;
        ig_md.l4_lookup.dstPort = hdr.tcp.dstPort;
        transition accept;
    }

    state parse_udp
    {
        pkt.extract(hdr.udp);
        ig_md.l4_lookup.srcPort = hdr.udp.srcPort;
        ig_md.l4_lookup.dstPort = hdr.udp.dstPort;
        transition accept;
    }
}

control MarinaIngress(
    inout header_t hdr,
    inout ingress_metadata_t ig_md,
    in ingress_intrinsic_metadata_t ig_intr_md,
    in ingress_intrinsic_metadata_from_parser_t ig_intr_prsr_md,
    inout ingress_intrinsic_metadata_for_deparser_t ig_intr_dprsr_md,
    inout ingress_intrinsic_metadata_for_tm_t ig_intr_md_for_tm)
{
    //iat_last_timestamp_reg is used in Ingress and Egress
    Register<bit<32>, flow_id_t>(MAX_FLOWS) iat_last_timestamp_reg;
    Register<bit<32>, flow_id_t>(MAX_FLOWS) last_iat_reg;

    //Retrieve old timestamp, write new timestamp
    RegisterAction<bit<32>, flow_id_t, bit<32>>(iat_last_timestamp_reg) read_update_last_timestamp = {
        void apply(inout bit<32> stored_timestamp, out bit<32> output)
        {
            output = stored_timestamp;
            stored_timestamp = ig_md.timestamp_nsec;
        }
    };

    //Retrieve old IAT, write new IAT
    RegisterAction<bit<32>, flow_id_t, bit<32>>(last_iat_reg) read_update_last_iat = {
        void apply(inout bit<32> stored_iat, out bit<32> output)
        {
            output = stored_iat;
            stored_iat = ig_md.iat;
        }
    };

    action compute_iat_log(bit<8> log, bit<16> log_square, bit<16> log_cube)
    {
        ig_md.iat_log = log;
        ig_md.iat_log_square = log_square;
        ig_md.iat_log_cube = log_cube;
    }

    table tbl_compute_iat_log
    {
        key = {
            ig_md.iat: lpm;
        }
        actions = {
            compute_iat_log;
        }
        //no default_action
        size=IAT_LOG_TABLE_SIZE;        //3327: size is dependent on python3 create_static_tables.py table_sizes.p4 static_tables.py
    }

    apply
    {
        // Keep bridged jitter deterministic on all paths.
        // (Tofino2: computing abs(iat-last_iat) here can exceed single-stage action limits.)
        ig_md.jitter = 0;

        ig_md.timestamp_nsec = (bit<32>)ig_intr_md.ingress_mac_tstamp;
        ig_md.last_timestamp = read_update_last_timestamp.execute(ig_md.flow_id);

        if(ig_md.last_timestamp != 0)
        {
            ig_md.iat = ig_md.timestamp_nsec - ig_md.last_timestamp;

            tbl_compute_iat_log.apply();

            ig_md.last_iat = read_update_last_iat.execute(ig_md.flow_id);
        }
    }
}

//multiple different controls needed because of CRCPolynomial
control BloomFilter1(
    inout header_t hdr,
    inout ingress_metadata_t ig_md)
{
    //BLOOMFILTER_BITS = 20, BLOOMFILTER_WIDTH = 1048576
    Register<bit<1>, flow_id_t>(BLOOMFILTER_WIDTH) bloomfilter_reg;
    RegisterAction<bit<1>, flow_id_t, bit<1>>(bloomfilter_reg) read_bloomfilter_entry = {
        void apply(inout bit<1> stored_value, out bit<1> output)
        {
            output = stored_value;
        }
    };

    //ignore Warning https://community.intel.com/t5/Intel-Connectivity-Research/CRC-custom-support-in-Tofino/m-p/1221709
    // Coeff must fit in 32 bits (drop the implicit x^32 term / leading 1)
    CRCPolynomial<bit<32>>(coeff    = 32w0x04c11db7,
                           reversed = true,
                           msb      = false,
                           extended = false,
                           init     = 0x0,
                           xor      = 0xffffffff
                           ) crc32;

    Hash<flow_id_t>(HashAlgorithm_t.CUSTOM, crc32) bloom_hash;

    apply
    {
        flow_id_t hash = bloom_hash.get({hdr.ipv4.srcAddr,
                                         hdr.ipv4.dstAddr,
                                         ig_md.l4_lookup.srcPort,
                                         ig_md.l4_lookup.dstPort,
                                         hdr.ipv4.protocol});
        @stage(6)   //put alle bloom filter regs into stage 6 to increase size of data registers
        {
        ig_md.is_in_bloomfiter_1 = read_bloomfilter_entry.execute(hash);
        }
    }
}

control BloomFilter2(
    inout header_t hdr,
    inout ingress_metadata_t ig_md)
{
    //BLOOMFILTER_BITS = 20, BLOOMFILTER_WIDTH = 1048576
    Register<bit<1>, flow_id_t>(BLOOMFILTER_WIDTH) bloomfilter_reg;
    RegisterAction<bit<1>, flow_id_t, bit<1>>(bloomfilter_reg) read_bloomfilter_entry = {
        void apply(inout bit<1> stored_value, out bit<1> output)
        {
            output = stored_value;
        }
    };

    CRCPolynomial<bit<32>>(coeff    = 32w0x1edc6f41,
                           reversed = true,
                           msb      = false,
                           extended = false,
                           init     = 0x0,
                           xor      = 0xffffffff
                           ) crc32c;

    Hash<flow_id_t>(HashAlgorithm_t.CUSTOM, crc32c) bloom_hash;

    apply
    {
        flow_id_t hash = bloom_hash.get({hdr.ipv4.srcAddr,
                                         hdr.ipv4.dstAddr,
                                         ig_md.l4_lookup.srcPort,
                                         ig_md.l4_lookup.dstPort,
                                         hdr.ipv4.protocol});
        @stage(6)
        {
        ig_md.is_in_bloomfiter_2 = read_bloomfilter_entry.execute(hash);
        }
    }
}

control BloomFilter3(
    inout header_t hdr,
    inout ingress_metadata_t ig_md)
{
    //BLOOMFILTER_BITS = 20, BLOOMFILTER_WIDTH = 1048576
    Register<bit<1>, flow_id_t>(BLOOMFILTER_WIDTH) bloomfilter_reg;
    RegisterAction<bit<1>, flow_id_t, bit<1>>(bloomfilter_reg) read_bloomfilter_entry = {
        void apply(inout bit<1> stored_value, out bit<1> output)
        {
            output = stored_value;
        }
    };

    CRCPolynomial<bit<32>>(coeff    = 32w0xa833982b,
                           reversed = true,
                           msb      = false,
                           extended = false,
                           init     = 0x0,
                           xor      = 0xffffffff
                           ) crc32d;

    Hash<flow_id_t>(HashAlgorithm_t.CUSTOM, crc32d) bloom_hash;

    apply
    {
        flow_id_t hash = bloom_hash.get({hdr.ipv4.srcAddr,
                                         hdr.ipv4.dstAddr,
                                         ig_md.l4_lookup.srcPort,
                                         ig_md.l4_lookup.dstPort,
                                         hdr.ipv4.protocol});
        @stage(6)
        {
        ig_md.is_in_bloomfiter_3 = read_bloomfilter_entry.execute(hash);
        }
    }
}

control BloomFilter4(
    inout header_t hdr,
    inout ingress_metadata_t ig_md)
{
    //BLOOMFILTER_BITS = 20, BLOOMFILTER_WIDTH = 1048576
    Register<bit<1>, flow_id_t>(BLOOMFILTER_WIDTH) bloomfilter_reg;
    RegisterAction<bit<1>, flow_id_t, bit<1>>(bloomfilter_reg) read_bloomfilter_entry = {
        void apply(inout bit<1> stored_value, out bit<1> output)
        {
            output = stored_value;
        }
    };

    CRCPolynomial<bit<32>>(coeff    = 32w0x814141ab,
                           reversed = true,
                           msb      = false,
                           extended = false,
                           init     = 0x0,
                           xor      = 0x0
                           ) crc32q;

    Hash<flow_id_t>(HashAlgorithm_t.CUSTOM, crc32q) bloom_hash;

    apply
    {
        flow_id_t hash = bloom_hash.get({hdr.ipv4.srcAddr,
                                         hdr.ipv4.dstAddr,
                                         ig_md.l4_lookup.srcPort,
                                         ig_md.l4_lookup.dstPort,
                                         hdr.ipv4.protocol});
        @stage(6)
        {
        ig_md.is_in_bloomfiter_4 = read_bloomfilter_entry.execute(hash);
        }
    }
}

control SwitchIngress(
    inout header_t hdr,
    inout ingress_metadata_t ig_md,
    in ingress_intrinsic_metadata_t ig_intr_md,
    in ingress_intrinsic_metadata_from_parser_t ig_intr_prsr_md,
    inout ingress_intrinsic_metadata_for_deparser_t ig_intr_dprsr_md,
    inout ingress_intrinsic_metadata_for_tm_t ig_intr_md_for_tm)
{
    BloomFilter1() Bloomfilter1;
    BloomFilter2() Bloomfilter2;
    BloomFilter3() Bloomfilter3;
    BloomFilter4() Bloomfilter4;
    MarinaIngress() Marina;

    Register<bit<32>, flow_id_t>(MAX_FLOWS) last_telemetry_sent_reg;

    RegisterAction<bit<32>, flow_id_t, bit<1>>(last_telemetry_sent_reg) check_update_last_telemetry_sent = {
        void apply(inout bit<32> stored_timestamp, out bit<1> output)
        {
            output = 0;

            if(ig_md.timestamp > stored_timestamp + 10000) //10 ms
            {
                output = 1;
                stored_timestamp = ig_md.timestamp;
            }
        }
    };

    action classification_hit(flow_id_t flow_id)
    {
        ig_md.flow_id = flow_id;
    }

    action classification_miss() {}

    table tbl_classification
    {
        key = {
            hdr.ipv4.srcAddr: exact;
            hdr.ipv4.dstAddr: exact;
            ig_md.l4_lookup.srcPort: exact;
            ig_md.l4_lookup.dstPort: exact;
            hdr.ipv4.protocol: exact;
        }
        actions = {
            classification_hit;
            @defaultonly classification_miss;
        }
        default_action = classification_miss;
        size = MAX_IP4_FLOWS;
    }

    action forward(PortId_t port, mac_addr_t dst_mac, mac_addr_t src_mac)
    {
        ig_intr_md_for_tm.ucast_egress_port = port;
        hdr.ethernet.dstAddr = dst_mac;
        hdr.ethernet.srcAddr = src_mac;
    }

    action drop()
    {
        ig_intr_dprsr_md.drop_ctl = 1;
    }

    table tbl_forward
	{
		key = {
			hdr.ipv4.dstAddr: lpm;
		}
		actions = {
			forward;
			@defaultonly drop;
		}
		default_action = drop;
		size=1024;
	}

    apply
    {
        tbl_forward.apply();

        tbl_classification.apply();

        ig_md.debug = 0;

        if(hdr.tcp.isValid() && ig_md.flow_id == 0 && hdr.tcp.syn == 1)
        {
            ig_md.tracking = tracking_t.start_tracking;
            ig_intr_dprsr_md.digest_type = TrackingDigest;
        }
        else if(hdr.udp.isValid() && ig_md.flow_id == 0)
        {
            //Bloom filter here is to not create digest messages for ignored flows
            Bloomfilter1.apply(hdr, ig_md);
            Bloomfilter2.apply(hdr, ig_md);
            Bloomfilter3.apply(hdr, ig_md);
            Bloomfilter4.apply(hdr, ig_md);

            if(ig_md.is_in_bloomfiter_1 == 0 || ig_md.is_in_bloomfiter_2 == 0 || ig_md.is_in_bloomfiter_3 == 0 || ig_md.is_in_bloomfiter_4 == 0)
            {
                ig_md.tracking = tracking_t.start_tracking;
                ig_intr_dprsr_md.digest_type = TrackingDigest;
            }
        }
        else if(hdr.tcp.isValid() && hdr.tcp.fin == 1)
        {
            ig_md.tracking = tracking_t.stop_tracking;
            ig_intr_dprsr_md.digest_type = TrackingDigest;
        }

        if(ig_md.flow_id != 0)
        {
            Marina.apply(hdr, ig_md, ig_intr_md, ig_intr_prsr_md, ig_intr_dprsr_md, ig_intr_md_for_tm);
            ig_md.timestamp = (bit<32>)(ig_intr_md.ingress_mac_tstamp >> 16);
            if(check_update_last_telemetry_sent.execute(ig_md.flow_id) == 1)
            {
                ig_intr_dprsr_md.mirror_type = MIRROR_TYPE_I2E;
                ig_md.pkt_type = PKT_TYPE_MIRROR;
                ig_md.mirror_session = 1;
            }
        }

        //Bridging metadata for Marina in Egress
        hdr.marina_bridged_md.setValid();
        hdr.marina_bridged_md.timestamp = ig_md.timestamp;
        hdr.marina_bridged_md.iat_log = ig_md.iat_log;
        hdr.marina_bridged_md.iat_log_square = ig_md.iat_log_square;
        hdr.marina_bridged_md.iat_log_cube = ig_md.iat_log_cube;
        hdr.marina_bridged_md.jitter = ig_md.jitter;

        //Prepare bridging metadata to egress
        hdr.bridged_md.setValid();
        hdr.bridged_md.telemetry_key = (telemetry_key_t)ig_md.flow_id;
        hdr.bridged_md.last_timestamp = ig_md.last_timestamp;
        hdr.bridged_md.pkt_type = PKT_TYPE_NORMAL;  //Mirrors will overwrite this one
    }
}

control SwitchIngressDeparser(
    packet_out pkt,
    inout header_t hdr,
    in ingress_metadata_t ig_md,
    in ingress_intrinsic_metadata_for_deparser_t ig_intr_dprsr_md)
{
    Digest<debug_digest_ingress_t>() debug_digest;
    Digest<tracking_digest_t>() tracking_digest;
	Mirror() mirror;

    apply
    {
        //Digest
		if(ig_intr_dprsr_md.digest_type == DTADigest)
		{
			debug_digest.pack({
				ig_md.random,
				ig_md.debug
			});
		}

        //Tofino only supports simple if statement and expects just one call per digest in deparser
        if(ig_intr_dprsr_md.digest_type == TrackingDigest)
        {
            tracking_digest.pack({
                ig_md.tracking,
                hdr.ipv4.srcAddr,
                hdr.ipv4.dstAddr,
                ig_md.l4_lookup.srcPort,
                ig_md.l4_lookup.dstPort,
                hdr.ipv4.protocol
            });
        }
		
		//Mirroring
		if (ig_intr_dprsr_md.mirror_type == MIRROR_TYPE_I2E)
		{
			//Emit mirror with mirror_h header appended.
			mirror.emit<mirror_h>(ig_md.mirror_session, {ig_md.pkt_type, (telemetry_key_t)ig_md.flow_id, ig_md.last_timestamp});
		}
		
		
		pkt.emit(hdr);
    }
}

parser TofinoEgressParser(
    packet_in pkt,
    out egress_intrinsic_metadata_t eg_intr_md)
{
    state start
    {
        pkt.extract(eg_intr_md);
        transition accept;
    }
}

@pa_auto_init_metadata
parser SwitchEgressParser(
    packet_in pkt,
    out header_t hdr,
    out egress_metadata_t eg_md,
    out egress_intrinsic_metadata_t eg_intr_md)
{
    TofinoEgressParser() tofino_parser;

    state start
    {
        tofino_parser.apply(pkt, eg_intr_md);
        transition parse_metadata;
    }

    state parse_metadata
    {
        mirror_h mirror_md = pkt.lookahead<mirror_h>();
		
		eg_md.flow_id = (flow_id_t)mirror_md.telemetry_key;
		//eg_md.telemetry_data = mirror_md.telemetry_data;
		transition select(mirror_md.pkt_type)
		{
			PKT_TYPE_MIRROR: parse_mirror_md;
			PKT_TYPE_NORMAL: parse_bridged_md;
			default: accept;
		}
    }

    state parse_mirror_md
    {
        eg_md.is_report_packet = 1;

        mirror_h mirror_md;
        pkt.extract(mirror_md);
        eg_md.last_timestamp = mirror_md.last_timestamp;
        // Must parse bridged_md and marina_bridged_md before ethernet
        // (ingress deparser emits them even for mirrored packets)
        transition parse_bridged_md;
    }

    state parse_bridged_md
    {
        pkt.extract(hdr.bridged_md);
        eg_md.last_timestamp = hdr.bridged_md.last_timestamp;
        transition parse_marina_bridged_md;
    }

    state parse_marina_bridged_md
    {
        pkt.extract(hdr.marina_bridged_md);

        eg_md.timestamp = hdr.marina_bridged_md.timestamp;

        eg_md.iat_log = hdr.marina_bridged_md.iat_log;
        eg_md.iat_log_square = hdr.marina_bridged_md.iat_log_square;
        eg_md.iat_log_cube = (bit<32>)hdr.marina_bridged_md.iat_log_cube;

        eg_md.jitter = hdr.marina_bridged_md.jitter;

        transition parse_ethernet;
    }

    state parse_ethernet
    {
        pkt.extract(hdr.ethernet);

        transition select(hdr.ethernet.etherType)
        {
            ETHERTYPE_IPV4: parse_ipv4;
            default: accept;
        }
    }

    state parse_ipv4
    {
        pkt.extract(hdr.ipv4);

        transition select(hdr.ipv4.protocol)
        {
            PROTOCOL_TCP: parse_tcp;
            PROTOCOL_UDP: parse_udp;
            default: accept;
        }
    }

    state parse_tcp
    {
        pkt.extract(hdr.tcp);
        eg_md.l4_lookup.srcPort = hdr.tcp.srcPort;
        eg_md.l4_lookup.dstPort = hdr.tcp.dstPort;

        transition accept;
    }

    state parse_udp
    {
        pkt.extract(hdr.udp);
        eg_md.l4_lookup.srcPort = hdr.udp.srcPort;
        eg_md.l4_lookup.dstPort = hdr.udp.dstPort;

        transition accept;
    }
}

/*
 * This control block is processing the report packet (crafting DTA)
 */
control ControlReporting(
    inout header_t hdr,
    inout egress_metadata_t eg_md)
{
	Hash<collector_hash_t>(HashAlgorithm_t.CRC8) hash_collector_hash;

    const mac_addr_t REPORT_SRC_MAC = 48w0xD077CE2B2054;
	
	action setEthernet()
	{
		hdr.ethernet.setValid();
        hdr.ethernet.dstAddr = eg_md.collector_mac;
        hdr.ethernet.srcAddr = REPORT_SRC_MAC;
        hdr.ethernet.etherType = ETHERTYPE_IPV4;
	}

	action setIP()
	{
		hdr.ipv4.setValid();
        hdr.ipv4.version = 4;
		hdr.ipv4.ihl = 5;
        hdr.ipv4.dscp = 0;
		//DSCP field shall be set to the value in the Traffic Class component of the RDMA Address Vector associated with the packet.
		hdr.ipv4.ecn = 0;
		//Total Length field shall be set to the length of the IPv4 packet in bytes including the IPv4 header and up to and including the ICRC.
		hdr.ipv4.totalLen = 92; //20+8+ 2 + 5 + 57 = 92
        hdr.ipv4.identification = 0;
		hdr.ipv4.flags = 0b010;
		hdr.ipv4.fragOffset = 0;
        hdr.ipv4.ttl = 64;
		//Time to Live field shall be set to the value in the Hop Limit component of the RDMA Address Vector associated with the packet.
		hdr.ipv4.protocol = 0x11; //Set IPv4 proto to UDP
		hdr.ipv4.dstAddr = eg_md.collector_ip; //Set address to collector address
	}

	action setUDP()
	{
		hdr.udp.setValid();
		hdr.udp.srcPort = 0xc0de;
		hdr.udp.dstPort = DTA_PORT_NUMBER;
		//The Length field in the UDP header of RoCEv2 packets shall be set to the number of bytes counting from the beginning of the UDP header up to and including the 4 bytes of the ICRC
		hdr.udp.length = 72; //8 + 2 + 5 + 57
		hdr.udp.checksum = 0; //UDP checksum SHOULD be 0
	}
	
	action setDTA_base()
	{
		hdr.dta_base.setValid();
		hdr.dta_base.opcode = 0x05; //Which operation to perform
		hdr.dta_base.immediate = 0; //Specify the Immediate flag in DTA
	}
	
	action setDTA_keywrite()
	{
		hdr.dta_keywrite.setValid();
		hdr.dta_keywrite.redundancyLevel = 1; //Set the level of redundancy for this data
		hdr.dta_keywrite.telemetry_key = (telemetry_key_t)eg_md.flow_id;
	}

    action setDTA_keywriteData()
    {
        hdr.dta_keywrite_data.setValid();
        hdr.dta_keywrite_data.telemetry_data = eg_md.telemetry_data;    //45 B
    }
	
	
    action set_collector_info(ipv4_addr_t collector_ip, mac_addr_t collector_mac)
	{
		eg_md.collector_ip = collector_ip;
        eg_md.collector_mac = collector_mac;
	}
	table tbl_hashToCollectorServer
	{
		key = {
			eg_md.collector_hash: ternary;
		}
		actions = {
			set_collector_info;
		}
		size=512;
	}
	
	apply
	{
		setEthernet();
		
		//Calculate collector hash for this key
		eg_md.collector_hash = hash_collector_hash.get({(telemetry_key_t)eg_md.flow_id});
		
		//Look up server info from the calculated hash
		tbl_hashToCollectorServer.apply();
		
		//Craft DTA headers
		setIP();
		setUDP();
		setDTA_base();
		setDTA_keywrite();
        setDTA_keywriteData();
	}
}

control MarinaEgress(
    inout header_t hdr,
    inout egress_metadata_t eg_md,
    in egress_intrinsic_metadata_t eg_intr_md)
{
    ControlReporting() Reporting;

    Register<bit<32>, flow_id_t>(MAX_FLOWS) pkt_count_reg;
    Register<bit<32>, flow_id_t>(MAX_FLOWS) iat_log_reg;
    Register<bit<32>, flow_id_t>(MAX_FLOWS) iat_log_square_reg;
    Register<bit<32>, flow_id_t>(MAX_FLOWS) iat_log_cube_reg;
    Register<bit<32>, flow_id_t>(MAX_FLOWS) size_log_reg;
    Register<bit<32>, flow_id_t>(MAX_FLOWS) size_log_square_reg;
    Register<bit<32>, flow_id_t>(MAX_FLOWS) size_log_cube_reg;
    // NOTE: jitter_reg removed due to Tofino2 placement failure.

    RegisterAction<bit<32>, flow_id_t, void>(pkt_count_reg) increment_pkt_counter = {
        void apply(inout bit<32> value)
        {
            value = value + 1;
        }
    };

    RegisterAction<bit<32>, flow_id_t, void>(iat_log_reg) add_iat_log = {
        void apply(inout bit<32> stored_iat_log)
        {
            stored_iat_log = stored_iat_log + (bit<32>)eg_md.iat_log;
        }
    };

    RegisterAction<bit<32>, flow_id_t, void>(iat_log_square_reg) add_iat_log_square = {
        void apply(inout bit<32> stored_iat_log_square)
        {
            stored_iat_log_square = stored_iat_log_square + (bit<32>)eg_md.iat_log_square;
        }
    };

    RegisterAction<bit<32>, flow_id_t, void>(iat_log_cube_reg) add_iat_log_cube = {
        void apply(inout bit<32> stored_iat_log_cube)
        {
            stored_iat_log_cube = stored_iat_log_cube + (bit<32>)eg_md.iat_log_cube;
        }
    };

    RegisterAction<bit<32>, flow_id_t, void>(size_log_reg) add_size_log = {
        void apply(inout bit<32> stored_size_log)
        {
            stored_size_log = stored_size_log + (bit<32>)eg_md.size_log;
        }
    };

    RegisterAction<bit<32>, flow_id_t, void>(size_log_square_reg) add_size_log_square = {
        void apply(inout bit<32> stored_size_log_square)
        {
            stored_size_log_square = stored_size_log_square + (bit<32>)eg_md.size_log_square;
        }
    };

    RegisterAction<bit<32>, flow_id_t, void>(size_log_cube_reg) add_size_log_cube = {
        void apply(inout bit<32> stored_size_log_cube)
        {
            stored_size_log_cube = stored_size_log_cube + (bit<32>)eg_md.size_log_cube;
        }
    };

    // jitter_reg removed

    //Read RegisterActions
    RegisterAction<bit<32>, flow_id_t, bit<32>>(pkt_count_reg) read_pkt_counter = {
        void apply(inout bit<32> stored_value, out bit<32> output)
        {
            output = stored_value;
        }
    };

    RegisterAction<bit<32>, flow_id_t, bit<32>>(iat_log_reg) read_iat_log = {
        void apply(inout bit<32> stored_iat_log, out bit<32> output)
        {
            output = stored_iat_log;
        }
    };

    RegisterAction<bit<32>, flow_id_t, bit<32>>(iat_log_square_reg) read_iat_log_square = {
        void apply(inout bit<32> stored_iat_log_square, out bit<32> output)
        {
            output = stored_iat_log_square;
        }
    };

    RegisterAction<bit<32>, flow_id_t, bit<32>>(iat_log_cube_reg) read_iat_log_cube = {
        void apply(inout bit<32> stored_iat_log_cube, out bit<32> output)
        {
            output = stored_iat_log_cube;
        }
    };

    RegisterAction<bit<32>, flow_id_t, bit<32>>(size_log_reg) read_size_log = {
        void apply(inout bit<32> stored_size_log, out bit<32> output)
        {
            output = stored_size_log;
        }
    };

    RegisterAction<bit<32>, flow_id_t, bit<32>>(size_log_square_reg) read_size_log_square = {
        void apply(inout bit<32> stored_size_log_square, out bit<32> output)
        {
            output = stored_size_log_square;
        }
    };

    RegisterAction<bit<32>, flow_id_t, bit<32>>(size_log_cube_reg) read_size_log_cube = {
        void apply(inout bit<32> stored_size_log_cube, out bit<32> output)
        {
            output = stored_size_log_cube;
        }
    };

    // jitter_reg removed

    action compute_size_log(bit<8> log, bit<8> log_square, bit<32> log_cube)
    {
        eg_md.size_log = log;
        eg_md.size_log_square = log_square;
        eg_md.size_log_cube = log_cube;
    }

    //moved to egress as pkt_length field is available
    table tbl_compute_size_log
    {
        key = {
            eg_md.size: lpm;
        }
        actions = {
            compute_size_log;
        }
        //not default_action
        size=BYTE_LOG_TABLE_SIZE;
    }

    apply
    {
        //only 1 RegisterAction per packet per Register
        if(eg_md.is_report_packet == 1)
        {
            eg_md.telemetry_data.packet_count = read_pkt_counter.execute(eg_md.flow_id);
            eg_md.telemetry_data.last_packet_timestamp = eg_md.last_timestamp;
            eg_md.telemetry_data.sum_of_iat = read_iat_log.execute(eg_md.flow_id);
            eg_md.telemetry_data.sum_of_iat_squared = read_iat_log_square.execute(eg_md.flow_id);
            eg_md.telemetry_data.sum_of_iat_cubed = read_iat_log_cube.execute(eg_md.flow_id);
            eg_md.telemetry_data.sum_of_packet_size = read_size_log.execute(eg_md.flow_id);
            eg_md.telemetry_data.sum_of_packet_size_squared = read_size_log_square.execute(eg_md.flow_id);
            eg_md.telemetry_data.sum_of_packet_size_cubed = read_size_log_cube.execute(eg_md.flow_id);
            eg_md.telemetry_data.jitter = 0;
            eg_md.telemetry_data.src_ip_addr = hdr.ipv4.srcAddr;
            eg_md.telemetry_data.dst_ip_addr = hdr.ipv4.dstAddr;
            eg_md.telemetry_data.src_port_num = eg_md.l4_lookup.srcPort;
            eg_md.telemetry_data.dst_port_num = eg_md.l4_lookup.dstPort;
            eg_md.telemetry_data.protocol_type = hdr.ipv4.protocol;

            //eg_intr_md.egress_port = 284;

            eg_md.debug = 1;
            Reporting.apply(hdr, eg_md);
        }
        else
        {
            increment_pkt_counter.execute(eg_md.flow_id);

            eg_md.size = eg_intr_md.pkt_length - eg_md.headers_size;

            if(eg_md.last_timestamp != 0)
            {
                add_iat_log.execute(eg_md.flow_id);
                add_iat_log_square.execute(eg_md.flow_id);
                add_iat_log_cube.execute(eg_md.flow_id);
                // jitter_reg removed (Tofino2 placement)
            }

            tbl_compute_size_log.apply();

            add_size_log.execute(eg_md.flow_id);
            add_size_log_square.execute(eg_md.flow_id);
            add_size_log_cube.execute(eg_md.flow_id);

            //eg_intr_md_for_dprsr.drop_ctl = 1;
        }
    }
}

control SwitchEgress(
    inout header_t hdr,
    inout egress_metadata_t eg_md,
    in egress_intrinsic_metadata_t eg_intr_md,
    in egress_intrinsic_metadata_from_parser_t eg_intr_md_from_prsr,
    inout egress_intrinsic_metadata_for_deparser_t eg_intr_md_for_dprsr,
    inout egress_intrinsic_metadata_for_output_port_t eg_intr_md_for_oport)
{
    MarinaEgress() Marina;
    //ControlReporting() Reporting;

    apply
    {
        if(eg_intr_md.egress_port == CPU_PORT)
        {
            //save_ingress_port_to_ethernet_src_table.apply();
        }
        else
        {
            //calculate headers_size in Egress as Parser can't do these calculations
            eg_md.headers_size = 14;
            if(hdr.ipv4.isValid())
            {
                eg_md.headers_size = eg_md.headers_size + 20;
            }
            if(hdr.tcp.isValid())
            {
                eg_md.headers_size = eg_md.headers_size + 20;
            }
            else if(hdr.udp.isValid())
            {
                eg_md.headers_size = eg_md.headers_size + 8;
            }

            Marina.apply(hdr, eg_md, eg_intr_md);

            //move to Marina to only do this once
            /*
            if(eg_md.is_report_packet == 1)
            {
                eg_md.debug = 1;
                //Reporting.apply(hdr, eg_md);
            }
            else
            {
                eg_md.debug = 2;
            }
            */
        }
    }
}

control SwitchEgressDeparser(
    packet_out pkt,
    inout header_t hdr,
    in egress_metadata_t eg_md,
    in egress_intrinsic_metadata_for_deparser_t eg_intr_md_for_dprsr)
{
    Checksum() ipv4_checksum;

    apply
    {
        hdr.ipv4.hdrChecksum = ipv4_checksum.update(
            {hdr.ipv4.version,
             hdr.ipv4.ihl,
             hdr.ipv4.dscp,
             hdr.ipv4.ecn,
             hdr.ipv4.totalLen,
             hdr.ipv4.identification,
             hdr.ipv4.flags,
             hdr.ipv4.fragOffset,
             hdr.ipv4.ttl,
             hdr.ipv4.protocol,
             hdr.ipv4.srcAddr,
             hdr.ipv4.dstAddr});
        
        pkt.emit(hdr.ethernet);
        pkt.emit(hdr.ipv4);
        pkt.emit(hdr.udp);
        pkt.emit(hdr.dta_base);
        pkt.emit(hdr.dta_keywrite);
        pkt.emit(hdr.dta_keywrite_data);
    }
}

Pipeline(SwitchIngressParser(),
         SwitchIngress(),
         SwitchIngressDeparser(),
         SwitchEgressParser(),
         SwitchEgress(),
         SwitchEgressDeparser()) pipe;

Switch(pipe) main;