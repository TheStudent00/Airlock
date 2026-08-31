#!/usr/bin/env bash
set -e
cd /projects/PseudoCoupHQ/Research/op_pipeline
python3 sem_anchored.py > /out/sem_anchored.log 2>&1
echo "Done"
