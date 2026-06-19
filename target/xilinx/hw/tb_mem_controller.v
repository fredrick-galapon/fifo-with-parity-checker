`timescale 1ns/1ps
`define CLK_PERIOD 20

module tb_mem_controller ();
    localparam AddrWidth = 32;

    reg                  clk;
    reg                  rst_n;
    reg                  start_i;
    wire                 ren_push_o;
    wire                 wen_pop_o;
    wire                 done_o;
    reg  [AddrWidth-1:0] addr_end_i;
    wire [AddrWidth-1:0] addr_push_o;
    wire [AddrWidth-1:0] addr_pop_o;
    
    mem_controller UUT (
        .clk         (clk),
        .rst_n       (rst_n),
        .start_i     (start_i),
        .ren_push_o  (ren_push_o),
        .wen_pop_o   (wen_pop_o),
        .done_o      (done_o),
        .addr_end_i  (addr_end_i),
        .addr_push_o (addr_push_o),
        .addr_pop_o  (addr_pop_o)
    );

    always begin
        #(`CLK_PERIOD/2) clk = ~clk;
    end

    task enable_mem;
        begin
            @(negedge clk);
            start_i = 1'b1;
            #(`CLK_PERIOD*10)
            start_i = 1'b0;
            while (!done_o) begin
                #(`CLK_PERIOD);
            end
        end
    endtask

    initial begin
        $dumpfile("tb_mem_controller.vcd");
        $dumpvars(0, tb_mem_controller);

        clk        = 1'b0;
        rst_n      = 1'b0;
        start_i    = 1'b0;
        addr_end_i = 32'd0;
        #(`CLK_PERIOD*5)
        rst_n      = 1'b1;
        #(`CLK_PERIOD*10)

        addr_end_i = 32'd2048;
        enable_mem();
        #(`CLK_PERIOD*10);
        
        addr_end_i = 32'd128;
        enable_mem();
        #(`CLK_PERIOD*10);

        $finish;
    end

endmodule