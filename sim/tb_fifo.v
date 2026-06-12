`timescale 1ns/1ps
`define CLK_PERIOD 10

module tb_fifo ();
    localparam FifoWidth = 32;
    localparam FifoDepth = 4;

    reg                  clk;
    reg                  rst_n;
    reg  [FifoWidth-1:0] push_data_i;
    reg                  push_valid_i;
    wire                 push_grant_o;
    wire [FifoWidth-1:0] pop_data_o;
    wire                 pop_valid_o;
    reg                  pop_grant_i;

    fifo UUT (
        .clk          (clk),
        .rst_n        (rst_n),
        .push_data_i  (push_data_i),
        .push_valid_i (push_valid_i),
        .push_grant_o (push_grant_o),
        .pop_data_o   (pop_data_o),
        .pop_valid_o  (pop_valid_o),
        .pop_grant_i  (pop_grant_i)
    );

    always begin
        #(`CLK_PERIOD/2) clk = ~clk;
    end

    initial begin
        $dumpfile("build/tb_fifo.vcd");
        $dumpvars(0, tb_fifo);

        clk          = 1'b0;
        rst_n        = 1'b0;
        push_data_i  = 32'd0;
        push_valid_i = 1'b0;
        pop_grant_i  = 1'b0;
        #(`CLK_PERIOD*10)
        rst_n        = 1'b1;
        #(`CLK_PERIOD*2)

        // timing waveform is similar to the one shown in specs
        push_data_i  = 32'hABAD_1DEA;   // data A
        push_valid_i = 1'b1;
        #(`CLK_PERIOD)

        push_data_i = 32'hBA5E_BA11;    // data B
        #(`CLK_PERIOD)

        push_data_i = 32'h00C0_FFEE;    // data C
        #(`CLK_PERIOD)

        push_data_i = 32'hDEAD_BEEF;    // data D
        #(`CLK_PERIOD)

        push_data_i = 32'hE0FA_CADE;    // data E
        pop_grant_i = 1'b1;
        #(2*`CLK_PERIOD)

        push_data_i  = 32'h00FA_B055;   // other data
        push_valid_i = 1'b0;
        pop_grant_i  = 1'b0;
        #(`CLK_PERIOD)

        pop_grant_i = 1'b1;
        #(5*`CLK_PERIOD)
    
        $finish;
    end


endmodule