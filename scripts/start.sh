# pForest Tofino Quick Start Script
# Generates P4 code for 2-forest experimentation

set -e

echo "=========================================="
echo "  pForest for Tofino - Quick Start"
echo "=========================================="
echo ""

if [ -z "$SDE_INSTALL" ]; then
    echo "ERROR: SDE_INSTALL environment variable not set"
    echo ""
    echo "Please set it and source the SDE environment:"
    echo "  export SDE_INSTALL=/path/to/bf-sde-9.13.1"
    echo "  source \$SDE_INSTALL/set_sde.bash"
    echo ""
    exit 1
fi

echo "✓ SDE_INSTALL: $SDE_INSTALL"
echo ""

if ! command -v p4c &> /dev/null; then
    echo "ERROR: p4c compiler not found"
    echo "Please source the SDE environment:"
    echo "  source $SDE_INSTALL/set_sde.bash"
    exit 1
fi

echo "✓ p4c compiler found"
echo ""

# Parse arguments
NUM_TREES=${1:-5}
MAX_DEPTH=${2:-5}
CERTAINTY=${3:-75}

echo "Configuration:"
echo "  Trees per forest: $NUM_TREES"
echo "  Max depth: $MAX_DEPTH"
echo "  Certainty: $CERTAINTY%"
echo ""

# Generate P4 code
echo "=========================================="
echo "  Step 1: Generating P4 Code"
echo "=========================================="
echo ""

uv run python3 src/generate_pforest.py $NUM_TREES $MAX_DEPTH $CERTAINTY t2na

if [ $? -ne 0 ]; then
    echo ""
    echo "✗ Generation failed!"
    exit 1
fi

echo ""
echo "=========================================="
echo "  Step 2: Compilation Instructions"
echo "=========================================="
echo ""

echo "To compile the generated P4 code:"
echo "  cd p4src"
echo "  ./compile.sh"
echo ""

echo "=========================================="
echo "  Step 3: Deployment Instructions"
echo "=========================================="
echo ""

echo "After compilation, to deploy to Tofino switch:"
echo "  cd p4src"
echo "  python3 deploy.py"
echo ""

echo "=========================================="
echo "  ✓ Quick Start Complete!"
echo "=========================================="
echo ""

echo "Next steps:"
echo "  1. Review generated files in p4src/"
echo "  2. Compile the P4 code (see Step 2 above)"
echo "  3. Deploy to Tofino switch (see Step 3 above)"
echo ""

echo "For detailed instructions, see:"
echo "  docs/README_TOFINO.md"
echo "  docs/TOFINO_DEPLOYMENT.md"
echo ""
