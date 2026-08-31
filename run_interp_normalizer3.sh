#!/usr/bin/env bash
set -e
cd /projects/PseudoCoupHQ/Research/op_pipeline
python3 canon12_normalize.py feeder_out/canon4_units_interp.json > /out/normalizer.log 2>&1
echo "Done"
