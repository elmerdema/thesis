#ifndef _MARINA_TYPES_P4_
#define _MARINA_TYPES_P4_

#define ETHERTYPE_IPV4 0x0800
#define PROTOCOL_TCP 0x06
#define PROTOCOL_UDP 0x11

#define DTA_PORT_NUMBER 40040

typedef bit<48> mac_addr_t;
typedef bit<32> ipv4_addr_t;
typedef bit<32> telemetry_key_t;
typedef bit<20> flow_id_t;

//Handling metadata bridging
typedef bit<8>  pkt_type_t;
const pkt_type_t PKT_TYPE_NORMAL = 1;
const pkt_type_t PKT_TYPE_MIRROR = 2;

//Handling mirror type
typedef bit<4> mirror_type_t;
const mirror_type_t MIRROR_TYPE_I2E = 1;

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
    bit<8>  classification_result;          //Classification result      8 bit | 1 B
    bit<32> used_features_bitmap;           //Used features bitmap      32 bit | 4 B
}

header ethernet_h
{
    mac_addr_t dstAddr;
    mac_addr_t srcAddr;
    bit<16> etherType;
}

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

header udp_h
{
    bit<16> srcPort;
    bit<16> dstPort;
    bit<16> length;
    bit<16> checksum;
}

header dta_base_h
{
    bit<8>  opcode;
    bit<1>  immediate;
    bit<7>  reserverd;
}

header dta_keywrite_static_h
{
    bit<8> redundancyLevel;
    telemetry_key_t telemetry_key;
}

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

#endif
