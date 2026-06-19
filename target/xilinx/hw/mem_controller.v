`timescale 1ns/1ps

module mem_controller #(
    parameter AddrWidth = 32
) (
    // global clock and reset
    input                      clk,
    input                      rst_n,
    // control signals
    input                      start_i,
    output                     ren_push_o,
    output reg                 wen_pop_o,
    output reg                 done_o,
    // addresses
    input      [AddrWidth-1:0] addr_end_i,
    output reg [AddrWidth-1:0] addr_push_o,
    output reg [AddrWidth-1:0] addr_pop_o
);

    // detect rising edge of start_i signal
    reg  start_q, start_q2, start_q3;
    wire start_pulse;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            start_q  <= 1'b0;
            start_q2 <= 1'b0;
            start_q3 <= 1'b0;
        end else begin
            start_q  <= start_i;
            start_q2 <= start_q;
            start_q3 <= start_q2;
        end
    end

    assign start_pulse = ((start_q2 == 1'b1) && (start_q3 == 1'b0)); // rising edge

    
    // state machine
    reg [1:0] state_q, state_d;

    localparam StIdle    = 2'b00;
    localparam StCompute = 2'b01;
    localparam StDone    = 2'b10;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_q <= StIdle;
        end else begin
            state_q <= state_d;
        end
    end
    
    always @(*) begin
        case (state_q)
            // wait for start_pulse to be asserted
            StIdle: begin
                if (start_pulse) begin
                    state_d <= StCompute;
                end else begin
                    state_d <= state_q;
                end
            end

            // wait until output address is equal to target address
            StCompute: begin
                if (addr_push_o == addr_end_i) begin
                    state_d <= StDone;
                end else begin
                    state_d <= state_q;
                end
            end

            // go back to idle state
            StDone: begin
                state_d <= StIdle;
            end
        endcase
    end


    // generate output addresses
    localparam AddrZero = {AddrWidth{1'b0}};
    localparam AddrFour = {{AddrWidth-3{1'b0}}, 3'd4};

    wire addr_inc = (state_q == StCompute);
    wire addr_clr = (state_q == StDone);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            addr_push_o <= AddrZero;
        end else begin
            case ({addr_inc, addr_clr})
                2'b10: begin
                    addr_push_o <= addr_push_o + AddrFour;
                end
                2'b01: begin
                    addr_push_o <= AddrZero;
                end
            endcase
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            addr_pop_o <= AddrZero;
        end else begin  // delayed version of addr_push_o
            addr_pop_o <= addr_push_o;
        end
    end


    // control signals
    assign ren_push_o = (state_q == StCompute);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wen_pop_o <= 1'b0;
        end else begin  // delayed version of wen_pop_o
            wen_pop_o <= ren_push_o;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            done_o <= 1'b0;
        end else begin
            if (state_q == StDone) begin    // delayed version
                done_o <= 1'b1;
            end else begin
                done_o <= 1'b0;
            end
        end
    end

endmodule