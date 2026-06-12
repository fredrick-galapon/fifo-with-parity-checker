#!/usr/bin/env bash
set -euo pipefail

TB=${TB:-tb_top}
RTL_DIR=${RTL_DIR:-rtl}
FINAL_DIR=${FINAL_DIR:-final}
LIB_DIR=${LIB_DIR:-lib}
BUILD_DIR=${BUILD_DIR:-build}

echo "[Icarus Verilog] Compiling $TB..."
iverilog -I $RTL_DIR/include -I $RTL_DIR -g2012 \
    -DFUNCTIONAL \
    -DUSE_POWER_PINS \
    -DUNIT_DELAY=#0 \
    -Ttyp \
    -o $BUILD_DIR/${TB}_pls.vvp \
    sim/$TB.v \
    $FINAL_DIR/*.pnl.v \
    $LIB_DIR/primitives_hd.v \
    $LIB_DIR/sky130_fd_sc_hd.v

echo "[Icarus Verilog] Running post-layout simulation for $TB..."
vvp $BUILD_DIR/${TB}_pls.vvp