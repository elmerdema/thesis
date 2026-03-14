cd /home/tofino/pforest

# Full benchmark (feature sweep + tree/depth sweep) — default QoE dataset
uv run python3 src/benchmark.py --experiment all --arch t2na

# IDS dataset benchmark
uv run python3 src/benchmark.py --experiment all --arch t2na --dataset ids

# Feature sweep only, skip compilation (ML-only, faster)
uv run python3 src/benchmark.py --experiment features --no-compile

# Tree/depth sweep only, custom timeout
uv run python3 src/benchmark.py --experiment trees --compile-timeout 900

# IDS tree sweep, no compile
uv run python3 src/benchmark.py -e trees --no-compile -d ids
