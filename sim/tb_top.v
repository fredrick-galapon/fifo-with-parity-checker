`timescale 1ns/1ps
`include "defines.vh"
`include "config.vh"
`define CLK_PERIOD      20
`define MEM_DEPTH       2048
`define SEED            12345

module tb_top ();
    localparam DataWidth  = `DATA_WIDTH;
    localparam FifoDepth  = `FIFO_DEPTH;
    localparam ParityType = `PARITY_TYPE;
    localparam ParityBit  = `PARITY_BIT;
    localparam FifoWidth  = DataWidth+1;

    reg                  clk;
    reg                  rst_n;
    reg  [FifoWidth-1:0] data_i;
    reg                  valid_i;
    wire                 grant_o;
    wire [DataWidth-1:0] data_o;
    wire                 valid_o;
    reg                  grant_i;


    /////////////////////
    // Unit Under Test //
    /////////////////////
    wire VDD;
	wire VSS;

    assign VDD = 1'b1;
    assign VSS = 1'b0;

    top UUT  (
    `ifdef USE_POWER_PINS
        .VPWR    (VDD),
        .VGND    (VSS),
    `endif
        .clk     (clk),
        .rst_n   (rst_n),
        .data_i  (data_i),
        .valid_i (valid_i),
        .grant_o (grant_o),
        .data_o  (data_o),
        .valid_o (valid_o),
        .grant_i (grant_i)
    );


    /////////////////////
    // Clock Generator //
    /////////////////////
    always begin
        #(`CLK_PERIOD/2) clk = ~clk;
    end


    ////////////////
    // Scoreboard //
    ////////////////
    reg [DataWidth-1:0] sb_mem       [0:FifoDepth-1];
    reg                 sb_mem_valid [0:FifoDepth-1];

    // counters
    integer sb_num_push       = 0;  // number of data transmitted (good and bad)
    integer sb_num_parity_err = 0;  // number of bad data transmitted
    integer sb_num_pass       = 0;  // number of good data correctly received
    integer sb_num_fail       = 0;  // number of good data incorrectly received
    integer sb_num_drop_pass  = 0;  // number of bad data correctly dropped
    integer sb_num_drop_fail  = 0;  // number of bad data incorrectly dropped
    integer sb_num_grant_err  = 0;  // number of incorrect grants
    integer sb_num_valid_err  = 0;  // number of incorrect valids

    // pointers and flags
    integer sb_tail           = 0;  // for writing
    integer sb_head           = 0;  // for reading
    integer sb_count          = 0;  // number of data stored in scoreboard
    reg     sb_error_flag     = 0;  // set to 1 when errors are injected into data

    // state
    wire sb_expect_grant = (sb_count < FifoDepth);  // with available slot
    wire sb_expect_valid = (sb_count > 0);          // with available data
    
    always @(posedge clk) begin
        // check grant and valid
        if (grant_o != sb_expect_grant) begin
            sb_num_grant_err = sb_num_grant_err + 1;
        end
        if (valid_o != (sb_expect_valid && sb_mem_valid[sb_head % FifoDepth])) begin
            sb_num_valid_err = sb_num_valid_err + 1;
        end

        // push transaction: store everything (both good and bad)
        if (valid_i && sb_expect_grant) begin
            if (ParityBit == `PARITY_BIT_MSB)
                sb_mem[sb_tail % FifoDepth] = data_i[FifoWidth-2:0];
            else begin
                sb_mem[sb_tail % FifoDepth] = data_i[FifoWidth-1:1];
            end
            sb_mem_valid[sb_tail % FifoDepth] = ~sb_error_flag; // 1 = good, 0 = bad
            sb_tail = sb_tail + 1;

            sb_num_push = sb_num_push + 1;
            if (sb_error_flag) begin
                sb_num_parity_err = sb_num_parity_err + 1;
            end
        end

        // pop transaction: bad word at head
        if (sb_expect_valid && !sb_mem_valid[sb_head % FifoDepth]) begin
            if (valid_o) begin
                sb_num_drop_fail = sb_num_drop_fail + 1;
            end else begin
                sb_num_drop_pass = sb_num_drop_pass + 1;
            end
            sb_head = sb_head + 1;
        end
        // pop transaction: good word at head
        else begin
            if (grant_i && sb_expect_valid && sb_mem_valid[sb_head % FifoDepth]) begin
                if (valid_o && (data_o == sb_mem[sb_head % FifoDepth])) begin
                    sb_num_pass = sb_num_pass + 1;
                end else begin
                    sb_num_fail = sb_num_fail + 1;
                end
                sb_head = sb_head + 1;
            end
        end

        sb_count = sb_tail - sb_head;
    end

    task reset_sb;
        begin
            // counters
            sb_num_push       = 0;
            sb_num_parity_err = 0;
            sb_num_pass       = 0;
            sb_num_fail       = 0;
            sb_num_drop_pass  = 0;
            sb_num_drop_fail  = 0;
            sb_num_grant_err  = 0;
            sb_num_valid_err  = 0;
            // pointers
            sb_tail           = 0;
            sb_head           = 0;
            sb_count          = 0;
        end
    endtask

    task display_sb;
        integer i;

        begin
            $display("Number of data transmitted (good and bad) = %5d", sb_num_push);
            $display("Number of good data transmitted           = %5d", sb_num_push-sb_num_parity_err);
            $display("Number of good data correctly received    = %5d", sb_num_pass);
            $display("Number of good data incorrectly received  = %5d", sb_num_fail);
            $display("Number of bad data transmitted            = %5d", sb_num_parity_err);
            $display("Number of bad data correctly dropped      = %5d", sb_num_drop_pass);
            $display("Number of bad data incorrectly dropped    = %5d", sb_num_drop_fail);
            $display("Number of incorrect grants                = %5d", sb_num_grant_err);
            $display("Number of incorrect valids                = %5d", sb_num_valid_err);
            $display("--------------------------------------------------");

            if ((sb_num_fail == 0) && (sb_num_drop_fail == 0) && 
                (sb_num_pass == (sb_num_push - sb_num_parity_err)) && 
                (sb_num_drop_pass == sb_num_parity_err) &&
                (sb_num_grant_err == 0) && (sb_num_valid_err == 0)) begin
                $display("PASS");
            end else begin
                $display("FAIL");
            end
            $display("");
        end
    endtask


    ///////////////////////////////////
    // Memory for Traffic Generation //
    ///////////////////////////////////
    reg [FifoWidth-1:0] mem [0:`MEM_DEPTH-1];

    integer fault_rate;
    integer j = 0;

    initial begin
        if ((ParityType == `PARITY_TYPE_ODD) && (ParityBit == `PARITY_BIT_LSB)) begin
            $readmemh("sim/data_odd_lsb.txt", mem);
        end else if ((ParityType == `PARITY_TYPE_ODD) && (ParityBit == `PARITY_BIT_MSB)) begin
            $readmemh("sim/data_odd_msb.txt", mem);
        end else if ((ParityType == `PARITY_TYPE_EVEN) && (ParityBit == `PARITY_BIT_LSB)) begin
            $readmemh("sim/data_even_lsb.txt", mem);
        end else begin
            $readmemh("sim/data_even_msb.txt", mem);
        end
    end

    always @(negedge clk) begin
        data_i = mem[j % `MEM_DEPTH];   // assume data has correct parity

        sb_error_flag = 0;
        if (($urandom % 100) < fault_rate) begin
            data_i = data_i ^ (1 << ($urandom % FifoWidth));
            sb_error_flag = 1;
        end
        j = j + 1;
    end


    ///////////////////////
    // Traffic Generator //
    ///////////////////////
    integer seed = `SEED;

    task fill_fifo;
        begin
            @(negedge clk);
            while (sb_expect_grant) begin   // while FIFO is not full
                valid_i = 1'b1;
                #(`CLK_PERIOD);
            end
            valid_i = 1'b0;
        end
    endtask

    task empty_fifo;
        begin
            @(negedge clk);
            while (sb_expect_valid) begin   // while FIFO is not empty
                grant_i = 1'b1;
                #(`CLK_PERIOD);
            end
            grant_i = 1'b0;
        end
    endtask

    task traffic_always_grant;
        integer i;

        begin
            @(negedge clk);
            for (i = 0; i < $urandom; i = i + 1) begin
                valid_i = $urandom;
                grant_i = 1'b1;
                #(`CLK_PERIOD);
            end
            valid_i = 1'b0;
            grant_i = 1'b0;
        end
    endtask

    task traffic_random_grant;
        integer i;

        begin
            @(negedge clk);
            for (i = 0; i < $urandom; i = i + 1) begin
                valid_i = $urandom;
                grant_i = $urandom;
                #(`CLK_PERIOD);
            end
            valid_i = 1'b0;
            grant_i = 1'b0;
        end
    endtask
    
    
    /////////////////////////
    // SDF Back-annotation //
    /////////////////////////
    `ifdef ENABLE_SDF
        initial begin
		    $sdf_annotate("final/top__nom_tt_025C_1v80.sdf", UUT);
        end
    `endif


    ///////////////
    // Main Test //
    ///////////////
    initial begin
    `ifdef USE_POWER_PINS
        $dumpfile("build/tb_top_pls.vcd");
    `else
        $dumpfile("build/tb_top.vcd");
    `endif
        $dumpvars(0, tb_top);

        clk     = 1'b0;
        rst_n   = 1'b0;
        data_i  = 0;
        valid_i = 1'b0;
        grant_i = 1'b0;
        #(`CLK_PERIOD*10)
        rst_n   = 1'b1;
        #(`CLK_PERIOD*2)

        $urandom(seed);

        // no fault
        fault_rate = 0;

        // FIFO fill & empty
        $display("");
        $display("--------------------------------------------------");
        $display("FIFO fill and empty");
        $display("--------------------------------------------------");
        reset_sb();
        fill_fifo();
        empty_fifo();
        display_sb();

        // random traffic at maximum bandwidth
        $display("");
        $display("--------------------------------------------------");
        $display("Random traffic, maximum bandwidth");
        $display("--------------------------------------------------");
        reset_sb();
        traffic_always_grant();
        empty_fifo();
        display_sb();

        // random traffic with random grant
        $display("");
        $display("--------------------------------------------------");
        $display("Random traffic, random grant");
        $display("--------------------------------------------------");
        reset_sb();
        traffic_random_grant();
        empty_fifo();
        display_sb();

        // fault injection
        fault_rate = 40;
        $display("");
        $display("--------------------------------------------------");
        $display("Random traffic, fault injection");
        $display("--------------------------------------------------");
        reset_sb();
        traffic_random_grant();
        empty_fifo();
        display_sb();

        $finish;
    end

endmodule