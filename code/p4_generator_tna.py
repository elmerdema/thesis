#!/usr/bin/env python3
"""
P4 Code Generator for Tofino Native Architecture (TNA)
Generates pForest random forest classifier for Intel Tofino switches

This generator creates P4-16 code targeting TNA with Marina reporter integration.
Supports 2-forest architecture for model switching and experimentation.
Features are dynamically configurable via bitmap matching Marina's telemetry struct.
"""

import os
import sys
from jinja2 import Environment, FileSystemLoader

# Marina features with their indices (matching marina_data_t struct order) and bit widths
# The index determines the bit position in used_features_bitmap
MARINA_FEATURES = {
    "packet_count":               {"index": 0,  "width": 32, "p4_field": "packet_count"},
    "last_packet_timestamp":      {"index": 1,  "width": 32, "p4_field": "last_packet_timestamp"},
    "sum_of_iat":                 {"index": 2,  "width": 32, "p4_field": "sum_of_iat"},
    "sum_of_iat_squared":         {"index": 3,  "width": 32, "p4_field": "sum_of_iat_squared"},
    "sum_of_iat_cubed":           {"index": 4,  "width": 32, "p4_field": "sum_of_iat_cubed"},
    "sum_of_packet_size":         {"index": 5,  "width": 32, "p4_field": "sum_of_packet_size"},
    "sum_of_packet_size_squared": {"index": 6,  "width": 32, "p4_field": "sum_of_packet_size_squared"},
    "sum_of_packet_size_cubed":   {"index": 7,  "width": 32, "p4_field": "sum_of_packet_size_cubed"},
    "jitter":                     {"index": 8,  "width": 32, "p4_field": "jitter"},
    "src_ip_addr":                {"index": 9,  "width": 32, "p4_field": "src_ip_addr"},
    "dst_ip_addr":                {"index": 10, "width": 32, "p4_field": "dst_ip_addr"},
    "src_port_num":               {"index": 11, "width": 16, "p4_field": "src_port_num"},
    "dst_port_num":               {"index": 12, "width": 16, "p4_field": "dst_port_num"},
    "protocol_type":              {"index": 13, "width": 8,  "p4_field": "protocol_type"},
}

MARINA_TELEMETRY_FEATURES = [
    "packet_count",
    "sum_of_iat",
    "sum_of_iat_squared",
    "sum_of_iat_cubed",
    "sum_of_packet_size",
    "sum_of_packet_size_squared",
    "sum_of_packet_size_cubed",
    "jitter",
]

def generate_pforest_tna(num_trees, max_depth, certainty, output_file="p4src/pforest.p4", 
                         enable_drift=True, arch="tna", features=None, mode="reporter"):
    """
    Generate complete pForest P4 code for TNA using Jinja2 template
    
    Args:
        num_trees: Number of decision trees
        max_depth: Maximum depth of trees
        certainty: Certainty threshold (scaled, e.g., 750 for 75%)
        output_file: Output file path
        enable_drift: Enable drift detection (default True, requires >= 2 trees)
        arch: Target architecture ("tna" or "t2na")
        features: List of Marina feature names to use for classification (optional)
        mode: "reporter" (feature extraction + classification) or
              "translator" (DTA packet classification only)
    """
    
    # Default features depend on mode
    if features is None:
        features = list(MARINA_TELEMETRY_FEATURES)

    # Translator can use any MARINA_FEATURES; reporter is limited to telemetry-only
    if mode == "reporter":
        disallowed = [f_name for f_name in features if f_name not in MARINA_TELEMETRY_FEATURES]
        if disallowed:
            raise ValueError(
                f"Unsupported features for Marina reporter classifier: {disallowed}. "
                f"Allowed features: {MARINA_TELEMETRY_FEATURES}"
            )
    else:
        disallowed = [f_name for f_name in features if f_name not in MARINA_FEATURES]
        if disallowed:
            raise ValueError(
                f"Unknown features: {disallowed}. "
                f"Available features: {list(MARINA_FEATURES.keys())}"
            )
    
    # Process features and build bitmap
    processed_features = []
    used_features_bitmap = 0
    
    for f_name in features:
        if f_name not in MARINA_FEATURES:
            raise ValueError(f"Feature '{f_name}' not found in MARINA_FEATURES")
        
        f_info = MARINA_FEATURES[f_name]
        processed_features.append({
            "name": f_name,
            "p4_field": f_info["p4_field"],
            "width": f_info["width"],
            "index": f_info["index"]
        })
        used_features_bitmap |= (1 << f_info["index"])
    
    print(f"[P4 Generator] Using {len(processed_features)} features:")
    for f in processed_features:
        print(f"  - {f['name']} (bit {f['index']}, {f['width']} bits)")
    print(f"  Bitmap: 0x{used_features_bitmap:08X} ({used_features_bitmap})")

    # Precompute all vote patterns for table-based majority/unanimity logic.
    # This avoids complex conditional expressions that can fail placement on Tofino2.
    vote_patterns = []
    majority_threshold = (num_trees // 2) + 1
    for mask in range(1 << num_trees):
        labels = [(mask >> i) & 1 for i in range(num_trees)]
        ones = sum(labels)
        vote_patterns.append({
            "labels": labels,
            "majority": 1 if ones >= majority_threshold else 0,
            "unanimous": 1 if (ones == 0 or ones == num_trees) else 0,
        })
    
    # Setup Jinja2 environment
    # Assuming this script is in src/ and templates are in src/templates/
    script_dir = os.path.dirname(os.path.abspath(__file__))
    template_dir = os.path.join(script_dir, "templates")
    
    try:
        env = Environment(loader=FileSystemLoader(template_dir))
        
        # Select template based on mode
        if mode == "translator":
            template = env.get_template("pforest_translator.p4.j2")
        else:
            template = env.get_template("pforest.p4.j2")
        
        # Render template
        generated_code = template.render(
            num_trees=num_trees,
            max_depth=max_depth,
            certainty=certainty,
            enable_drift=enable_drift and mode == "reporter",
            features=processed_features,
            used_features_bitmap=used_features_bitmap,
            arch=arch,
            vote_patterns=vote_patterns,
        )
        
        # Write to file
        # Ensure directory exists
        output_dir = os.path.dirname(output_file)
        if output_dir and not os.path.exists(output_dir):
            os.makedirs(output_dir)
            
        with open(output_file, "w+") as f:
            f.write(generated_code)
        
        print(f"[P4 Generator TNA] Generated {output_file}")
        print(f"  Mode: {mode}")
        print(f"  Trees: {num_trees}, Depth: {max_depth}, Certainty: {certainty}")
        print(f"  Architecture: {arch.upper()}")
        print(f"  Features bitmap: 0x{used_features_bitmap:08X}")
        if enable_drift and mode == "reporter" and num_trees >= 2:
            print(f"  Drift Detection: ENABLED (EWMA threshold: 25%)")
        else:
            print(f"  Drift Detection: DISABLED")
        return True
        
    except Exception as e:
        print(f"Error generating P4 code: {e}")
        import traceback
        traceback.print_exc()
        return False

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: python3 p4_generator_tna.py <num_trees> <max_depth> [certainty] [arch] [features]")
        print("  features: comma-separated list of Marina feature names")
        print("  Available features:", ", ".join(MARINA_FEATURES.keys()))
        sys.exit(1)
        
    num_trees = int(sys.argv[1])
    max_depth = int(sys.argv[2])
    certainty = int(sys.argv[3]) if len(sys.argv) > 3 else 750
    arch = sys.argv[4] if len(sys.argv) > 4 else "tna"
    
    # Parse optional features list
    feature_list = None
    if len(sys.argv) > 5:
        feature_list = [f.strip() for f in sys.argv[5].split(",")]
    
    generate_pforest_tna(num_trees, max_depth, certainty, arch=arch, features=feature_list)

