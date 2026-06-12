`timescale 1ns/1ps
`include "defines.vh"
`include "config.vh"

module top #(
    parameter DataWidth  = `DATA_WIDTH,
    parameter FifoDepth  = `FIFO_DEPTH,
    parameter ParityType = `PARITY_TYPE,
    parameter ParityBit  = `PARITY_BIT,
    // do not change at instantiation
    parameter FifoWidth  = DataWidth+1
) (
    // global clock and reset
    input                  clk,
    input                  rst_n,
    // push interface
    input  [FifoWidth-1:0] data_i,
    input                  valid_i,
    output                 grant_o,
    // pop interface
    output [DataWidth-1:0] data_o,
    output                 valid_o,
    input                  grant_i
);

    wire [FifoWidth-1:0] pop_data;
    wire                 pop_valid;
    wire                 pop_grant;

    fifo #(
        .FifoWidth (FifoWidth),
        .FifoDepth (FifoDepth)
    ) u_fifo (
        .clk          (clk),
        .rst_n        (rst_n),
        .push_data_i  (data_i),
        .push_valid_i (valid_i),
        .push_grant_o (grant_o),
        .pop_data_o   (pop_data),
        .pop_valid_o  (pop_valid),
        .pop_grant_i  (pop_grant)
    );

    parity_checker #(
        .DataWidth  (DataWidth),
        .ParityType (ParityType),
        .ParityBit  (ParityBit)
    ) u_parity_checker (
        .pop_data_i  (pop_data),
        .pop_valid_i (pop_valid),
        .pop_grant_o (pop_grant),
        .data_o      (data_o),
        .valid_o     (valid_o),
        .grant_i     (grant_i)
    );

endmodule