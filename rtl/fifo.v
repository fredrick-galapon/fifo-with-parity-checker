`timescale 1ns/1ps

module fifo #(
    parameter FifoWidth = 32,
    parameter FifoDepth = 4
) (
    // global clock and reset
    input                      clk,
    input                      rst_n,
    // push interface
    input      [FifoWidth-1:0] push_data_i,
    input                      push_valid_i,
    output reg                 push_grant_o,
    // pop interface
    output     [FifoWidth-1:0] pop_data_o,
    output reg                 pop_valid_o,
    input                      pop_grant_i
);

    localparam AddrWidth = $clog2(FifoDepth);   // range of [0,FifoDepth-1]
    localparam CtrWidth  = $clog2(FifoDepth+1); // range of [0,FifoDepth]

    reg [FifoWidth-1:0] mem [0:FifoDepth-1];    // memory

    reg [AddrWidth-1:0] tail;       // track where to write data
    reg [AddrWidth-1:0] head;       // track where to read data
    reg [CtrWidth-1:0]  ctr;        // count the number of data in FIFO
    reg                 ctr_inc;    // counter increment signal
    reg                 ctr_dec;    // counter decrement signal

    localparam AddrZero = {AddrWidth{1'b0}};
    localparam AddrOne  = (AddrWidth == 1)? 1'b1 : {{AddrWidth-1{1'b0}}, 1'b1};
    localparam CtrZero  = {CtrWidth{1'b0}};
    localparam CtrOne   = (CtrWidth == 1)?  1'b1 : {{CtrWidth-1{1'b0}}, 1'b1};

    wire fifo_wr = (push_valid_i && push_grant_o);    // write data
    wire fifo_rd = (pop_grant_i && pop_valid_o);      // read data

    // write to memory
    integer idx;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (idx = 0; idx < FifoDepth; idx = idx + 1) begin
                mem[idx] <= {FifoWidth{1'b0}};
            end
        end else begin
            if (fifo_wr) begin
                mem[tail] <= push_data_i;
            end // else latch
        end
    end

    // read from memory
    assign pop_data_o = mem[head];

    // move (or increment) tail pointer when writing
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tail <= AddrZero;
        end else begin
            if (fifo_wr) begin
                if (tail == FifoDepth-1) begin  // wrap around
                    tail <= AddrZero;
                end else begin
                    tail <= tail + AddrOne;
                end
            end // else latch
        end
    end

    // move (or increment) head pointer when reading
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            head <= AddrZero;
        end else begin
            if (fifo_rd) begin
                if (head == FifoDepth-1) begin  // wrap around
                    head <= AddrZero;
                end else begin
                    head <= head + AddrOne;
                end
            end // else latch
        end
    end

    // update counter
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ctr <= CtrZero;
        end else begin
            case ({ctr_inc, ctr_dec})
                2'b10: begin    // increment
                    ctr <= ctr + CtrOne;
                end
                2'b01: begin    // decrement
                    ctr <= ctr - CtrOne;
                end
                // default: latch
            endcase
        end
    end

    // set counter increment/decrement control signals
    always @(*) begin
        case ({fifo_wr, fifo_rd})
            2'b10: begin    // increment when writing
                ctr_inc = 1'b1;
                ctr_dec = 1'b0;
            end
            2'b01: begin    // decrement when reading
                ctr_inc = 1'b0;
                ctr_dec = 1'b1;
            end
            default: begin  // no R/W or both
                ctr_inc = 1'b0;
                ctr_dec = 1'b0;
            end
        endcase
    end

    // determine FIFO state
    wire full         = (ctr == FifoDepth);
    wire empty        = (ctr == CtrZero);
    wire almost_full  = (ctr == FifoDepth-1);
    wire almost_empty = (ctr == CtrOne);

    // set push_grant to 0 if full
    // assign push_grant_o = (ctr == FifoDepth)? 1'b0 : 1'b1;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            push_grant_o <= 1'b1;
        end else begin
            if ((almost_full && ctr_inc) || (full && !ctr_dec)) begin
                push_grant_o <= 1'b0;
            end else begin
                push_grant_o <= 1'b1;
            end
        end
    end

    // set pop_valid to 0 if empty
    // assign pop_valid_o = (ctr == CtrZero)? 1'b0 : 1'b1;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pop_valid_o <= 1'b0;
        end else begin
            if ((almost_empty && ctr_dec) || (empty && !ctr_inc)) begin
                pop_valid_o <= 1'b0;
            end else begin
                pop_valid_o <= 1'b1;
            end
        end
    end

endmodule