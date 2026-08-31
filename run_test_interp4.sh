#!/usr/bin/env bash
set -e
cd /projects/PseudoCoupHQ/Research/op_pipeline
python3 test_interp_normalizer.py feeder_out/canon4_units_interp.json > /out/interp_normalizer_results.log 2>&1
echo "Done"
