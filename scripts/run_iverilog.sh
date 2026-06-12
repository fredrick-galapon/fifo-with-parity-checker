#!/usr/bin/env bash
set -euo pipefail

TB=${TB:-tb_top}
RTL_DIR=${RTL_DIR:-rtl}
BUILD_DIR=${BUILD_DIR:-build}

echo "[Icarus Verilog] Compiling $TB..."
iverilog -I $RTL_DIR/include -I $RTL_DIR -g2012 \
    -o $BUILD_DIR/$TB.vvp \
    sim/$TB.v \
    $RTL_DIR/*.v

echo "[Icarus Verilog] Running RTL simulation for $TB..."
vvp $BUILD_DIR/$TB.vvp