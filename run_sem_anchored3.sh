#!/usr/bin/env bash
set -e
python3 -m pip install --quiet --disable-pip-version-check pyvex archinfo angr
cp /projects/PseudoCoupHQ/Research/op_pipeline/sem_anchored.py /work/
cp /projects/PseudoCoupHQ/Research/op_pipeline/sem_anchored_spill.py /work/
# It also needs arch_sem.py, arch_read.py, and the probe_manifests and op_units!
cp /projects/PseudoCoupHQ/Research/op_pipeline/op_units_*.json /work/
cp /projects/PseudoCoupHQ/Research/op_pipeline/probe_manifest_*.json /work/
cp -r /projects/PseudoCoupHQ/Research/kind_fuzz_clustering/arch_sem.py /work/
cp -r /projects/PseudoCoupHQ/Research/kind_fuzz_clustering/arch_read.py /work/
cd /work
python3 sem_anchored.py > /out/sem_anchored.log 2>&1
cp sem_anchored_*.json /out/
echo "Done"
