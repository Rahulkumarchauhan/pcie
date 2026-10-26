//=============================================================================
// up_down_counter
//
// Parameterised up/down counter with asynchronous active-low reset,
// count enable, synchronous parallel load, optional saturation, and
// one-cycle terminal-count flags for cascading.
//
//   priority:  rst_n  >  load  >  en  >  (count up / down / hold)
//
//   up_down = 1 : count increments
//   up_down = 0 : count decrements
//   en      = 0 : count holds its value (clock still runs)
//
//   SATURATE = 0 : wraps  0 -> MAX -> 0 -> MAX (free running)
//   SATURATE = 1 : clamps at MAX / MIN and sticks there
//
//   max_tick : one-cycle pulse, asserted on the cycle *before* an
//              enabled up-count leaves MAX (i.e. would wrap/clamp).
//   min_tick : same idea for an enabled down-count leaving MIN.
//              Use these as carry/borrow into the next stage:
//              .en(next_stage) = en & max_tick
//
// Verilog-2001, synthesizable, no latches, no combinational feedback.
//=============================================================================

`default_nettype none

module up_down_counter #(
    parameter integer       WIDTH       = 8,
    parameter integer       SATURATE    = 0,
    parameter [WIDTH-1:0]   RESET_VALUE = {WIDTH{1'b0}}
) (
    input  wire                 clk,
    input  wire                 rst_n,
    input  wire                 en,
    input  wire                 up_down,
    input  wire                 load,
    input  wire [WIDTH-1:0]     load_value,
    output reg  [WIDTH-1:0]     count,
    output wire                 max_tick,
    output wire                 min_tick
);

    localparam [WIDTH-1:0] MAX_VAL = {WIDTH{1'b1}};
    localparam [WIDTH-1:0] MIN_VAL = {WIDTH{1'b0}};

    //------------------------------------------------------------------
    // Counter state
    //------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            count <= RESET_VALUE;
        end
        else if (load) begin
            count <= load_value;
        end
        else if (en) begin
            if (up_down) begin
                // up: wrap to 0, or hold at MAX when saturating
                count <= (count == MAX_VAL) ? (SATURATE ? count : MIN_VAL)
                                            : (count + 1'b1);
            end
            else begin
                // down: wrap to MAX, or hold at 0 when saturating
                count <= (count == MIN_VAL) ? (SATURATE ? count : MAX_VAL)
                                            : (count - 1'b1);
            end
        end
        // else: hold
    end

    //------------------------------------------------------------------
    // Terminal-count flags (combinational, one cycle wide)
    //------------------------------------------------------------------
    assign max_tick = en & ~load & rst_n &  up_down & (count == MAX_VAL);
    assign min_tick = en & ~load & rst_n & ~up_down & (count == MIN_VAL);

endmodule

`default_nettype wire
