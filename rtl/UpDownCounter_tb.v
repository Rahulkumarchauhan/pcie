//=============================================================================
// up_down_counter_tb  -  self-checking testbench for up_down_counter
//
// Two DUTs share identical stimulus:
//   dut_wrap : SATURATE = 0  (free running, wraps at MAX/MIN)
//   dut_sat  : SATURATE = 1  (clamps at MAX/MIN)
//
// Covers: async reset, hold (en=0), count up, count down, load priority,
//         wrap at MAX, wrap at MIN, clamp at both ends,
//         max_tick / min_tick behaviour.
//
// Run (Icarus Verilog):
//   iverilog -g2005 -o counter.vvp rtl/UpDownCounter.v rtl/UpDownCounter_tb.v
//   vvp counter.vvp
// Run (Questa/ModelSim):
//   vlog rtl/UpDownCounter.v rtl/UpDownCounter_tb.v
//   vsim -c up_down_counter_tb -do "run -all; quit -f"
//=============================================================================

`timescale 1ns/1ps
`default_nettype none

module up_down_counter_tb;

    localparam integer     WIDTH = 4;    // small width so wrap is quick to hit
    localparam integer     CYCLE = 10;   // clock period in ns
    localparam [WIDTH-1:0] MAX   = {WIDTH{1'b1}};
    localparam [WIDTH-1:0] MIN   = {WIDTH{1'b0}};

    //------------------------------------------------------------------
    // Stimulus
    //------------------------------------------------------------------
    reg              clk        = 1'b0;
    reg              rst_n      = 1'b1;
    reg              en         = 1'b0;
    reg              up_down    = 1'b1;
    reg              load       = 1'b0;
    reg  [WIDTH-1:0] load_value = MIN;

    //------------------------------------------------------------------
    // DUT outputs
    //------------------------------------------------------------------
    wire [WIDTH-1:0] count_wrap;
    wire [WIDTH-1:0] count_sat;
    wire             max_tick_wrap, min_tick_wrap;
    wire             max_tick_sat,  min_tick_sat;

    //------------------------------------------------------------------
    // Bookkeeping
    //------------------------------------------------------------------
    integer checks = 0;
    integer errors = 0;

    //------------------------------------------------------------------
    // DUTs
    //------------------------------------------------------------------
    up_down_counter #(
        .WIDTH       (WIDTH),
        .SATURATE    (0),
        .RESET_VALUE (MIN)
    ) dut_wrap (
        .clk        (clk),
        .rst_n      (rst_n),
        .en         (en),
        .up_down    (up_down),
        .load       (load),
        .load_value (load_value),
        .count      (count_wrap),
        .max_tick   (max_tick_wrap),
        .min_tick   (min_tick_wrap)
    );

    up_down_counter #(
        .WIDTH       (WIDTH),
        .SATURATE    (1),
        .RESET_VALUE (MIN)
    ) dut_sat (
        .clk        (clk),
        .rst_n      (rst_n),
        .en         (en),
        .up_down    (up_down),
        .load       (load),
        .load_value (load_value),
        .count      (count_sat),
        .max_tick   (max_tick_sat),
        .min_tick   (min_tick_sat)
    );

    always #(CYCLE/2) clk = ~clk;

    //------------------------------------------------------------------
    // Advance n clock cycles, returning just after the last posedge so
    // that non-blocking updates have settled.
    //------------------------------------------------------------------
    task tick;
        input [31:0] n;
        integer      k;
        begin
            for (k = 0; k < n; k = k + 1) begin
                @(posedge clk);
                #1;
            end
        end
    endtask

    //------------------------------------------------------------------
    // Compare both counters against expected values
    //------------------------------------------------------------------
    task check;
        input [WIDTH-1:0] exp_wrap;
        input [WIDTH-1:0] exp_sat;
        input [8*24-1:0]  name;
        begin
            checks = checks + 1;
            if (count_wrap !== exp_wrap) begin
                errors = errors + 1;
                $display("[%0t] FAIL %0s : wrap count = %0d, expected %0d",
                         $time, name, count_wrap, exp_wrap);
            end
            if (count_sat !== exp_sat) begin
                errors = errors + 1;
                $display("[%0t] FAIL %0s : sat  count = %0d, expected %0d",
                         $time, name, count_sat, exp_sat);
            end
        end
    endtask

    //------------------------------------------------------------------
    // Compare terminal-count flags. The two DUTs live in different
    // states, so each expectation is given separately.
    //------------------------------------------------------------------
    task check_flags;
        input exp_max_wrap;
        input exp_max_sat;
        input exp_min_wrap;
        input exp_min_sat;
        input [8*28-1:0] name;
        begin
            checks = checks + 1;
            if (max_tick_wrap !== exp_max_wrap || max_tick_sat !== exp_max_sat) begin
                errors = errors + 1;
                $display("[%0t] FAIL %0s : max_tick = %b/%b, expected %b/%b",
                         $time, name, max_tick_wrap, max_tick_sat,
                         exp_max_wrap, exp_max_sat);
            end
            if (min_tick_wrap !== exp_min_wrap || min_tick_sat !== exp_min_sat) begin
                errors = errors + 1;
                $display("[%0t] FAIL %0s : min_tick = %b/%b, expected %b/%b",
                         $time, name, min_tick_wrap, min_tick_sat,
                         exp_min_wrap, exp_min_sat);
            end
        end
    endtask

    //------------------------------------------------------------------
    // Stimulus
    //------------------------------------------------------------------
    initial begin
        // force a clean negedge on rst_n regardless of simulator start-up
        rst_n = 1'b1; #1;
        rst_n = 1'b0; #1;
        check(MIN, MIN, "async reset");

        rst_n = 1'b1; #1;

        // ---- hold while disabled -------------------------------------
        en = 1'b0; up_down = 1'b1;
        tick(2);
        check(MIN, MIN, "hold when en=0");

        // ---- synchronous load ----------------------------------------
        load = 1'b1; load_value = 4'h7;
        tick(1);
        load = 1'b0;
        check(4'h7, 4'h7, "load 7");

        // ---- count up ------------------------------------------------
        en = 1'b1; up_down = 1'b1;
        tick(3);
        check(4'hA, 4'hA, "up 7 -> A");               // 8, 9, A
        check_flags(1'b0, 1'b0, 1'b0, 1'b0, "flags quiet mid-range");

        // ---- wrap / clamp at MAX -------------------------------------
        tick(6);
        check(MIN, MAX, "wrap 0 / clamp MAX");        // A..F,0   vs  A..F,F

        // ---- count down ----------------------------------------------
        up_down = 1'b0;
        tick(2);
        check(4'hE, 4'hD, "down wrap/sat");           // F,E      vs  E,D

        // ---- load wins over counting ---------------------------------
        load = 1'b1; load_value = 4'h1;
        tick(1);
        load = 1'b0;
        check(4'h1, 4'h1, "load 1 while enabled");

        // ---- wrap / clamp at MIN -------------------------------------
        tick(1);
        check(MIN, MIN, "down 1 -> 0");
        check_flags(1'b0, 1'b0, 1'b1, 1'b1, "min_tick at MIN");

        tick(1);
        check(MAX, MIN, "wrap to MAX / clamp MIN");
        check_flags(1'b0, 1'b0, 1'b0, 1'b1, "sat stuck at MIN");

        // ---- enable gates the flags ----------------------------------
        en = 1'b0; up_down = 1'b1;
        tick(2);
        check(MAX, MIN, "hold F / hold 0");
        check_flags(1'b0, 1'b0, 1'b0, 1'b0, "no ticks while en=0");

        en = 1'b1;
        #1;   // let the combinational tick flags settle before sampling
        check_flags(1'b1, 1'b0, 1'b0, 1'b0, "max_tick, wrap DUT only");

        tick(1);
        check(MIN, 4'h1, "wrap F -> 0 / up 0 -> 1");
        check_flags(1'b0, 1'b0, 1'b0, 1'b0, "flags cleared after step");

        // ---- max_tick on the saturating DUT --------------------------
        load = 1'b1; load_value = MAX;
        tick(1);
        load = 1'b0;
        check(MAX, MAX, "load F");
        check_flags(1'b1, 1'b1, 1'b0, 1'b0, "max_tick at MAX (both)");

        tick(1);
        check(MIN, MAX, "wrap to 0 / clamp MAX");
        check_flags(1'b0, 1'b1, 1'b0, 1'b0, "sat holds at MAX");

        // ---- back to normal counting ---------------------------------
        load = 1'b1; load_value = MIN;
        tick(1);
        load = 1'b0;
        check(MIN, MIN, "reload 0");

        tick(5);
        check(4'h5, 4'h5, "up 0 -> 5");
        check_flags(1'b0, 1'b0, 1'b0, 1'b0, "flags quiet at 5");

        //--------------------------------------------------------------
        $display("--------------------------------------------------");
        if (errors == 0)
            $display("PASS : %0d checks, 0 errors", checks);
        else
            $display("FAIL : %0d checks, %0d errors", checks, errors);
        $display("--------------------------------------------------");
        $finish;
    end

    //------------------------------------------------------------------
    // Optional VCD dump:  iverilog -DVCD ...
    //------------------------------------------------------------------
`ifdef VCD
    initial begin
        $dumpfile("up_down_counter.vcd");
        $dumpvars(0, up_down_counter_tb);
    end
`endif

    //------------------------------------------------------------------
    // Watchdog
    //------------------------------------------------------------------
    initial begin
        #(CYCLE * 1000);
        $display("FAIL : timeout");
        $finish;
    end

endmodule

`default_nettype wire
