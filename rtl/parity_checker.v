`timescale 1ns/1ps
`include "defines.vh"

module parity_checker #(
    parameter DataWidth  = 32,
    parameter ParityType = 0,
    parameter ParityBit  = 0,
    // do not change at instantiation
    parameter FifoWidth  = DataWidth+1
) (
     // FIFO interface
    input  [FifoWidth-1:0] pop_data_i,
    input                  pop_valid_i,
    output                 pop_grant_o,
    // receiver interface
    output [DataWidth-1:0] data_o,
    output                 valid_o,
    input                  grant_i
);

    wire parity_err;
    
    // detect error in parity
    generate
        if (ParityType == `PARITY_TYPE_EVEN) begin
            assign parity_err = (^pop_data_i != 1'b0);
        end else begin
            assign parity_err = (^pop_data_i != 1'b1);
        end
    endgenerate

    // strip parity bit to recover original data
    generate
        if (ParityBit == `PARITY_BIT_LSB) begin
            assign data_o = pop_data_i[FifoWidth-1:1];
        end else begin
            assign data_o = pop_data_i[FifoWidth-2:0];
        end
    endgenerate

    // pop FIFO when (1) receiver is ready, or (2) data is corrupted
    assign pop_grant_o = (grant_i || parity_err);

    // forward to receiver only when valid and no parity error
    assign valid_o = (pop_valid_i && ~parity_err);

endmodule