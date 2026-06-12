#!/usr/bin/env bash
set -euo pipefail

TB=${TB:-tb_top}
RTL_DIR=${RTL_DIR:-rtl}
FINAL_DIR=${FINAL_DIR:-final}
LIB_DIR=${LIB_DIR:-lib}
SCRIPTS_DIR=${SCRIPTS_DIR:-scripts}
BUILD_DIR=${BUILD_DIR:-build}

echo "[CVC] Running post-layout simulation for $TB..."
./$SCRIPTS_DIR/cvc +interp \
    +define+FUNCTIONAL \
    +define+USE_POWER_PINS \
    +define+ENABLE_SDF \
    +typdelays \
    +dump2fst \
    +fst+parallel2=on \
    +incdir+$RTL_DIR/include \
    sim/$TB.v \
    $FINAL_DIR/*.pnl.v \
    -v $LIB_DIR/primitives_hd.v \
    $LIB_DIR/sky130_fd_sc_hd.v