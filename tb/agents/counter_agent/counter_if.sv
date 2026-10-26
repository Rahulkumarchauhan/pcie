//=============================================================================
// counter_if  -  interface for up_down_counter (rtl/UpDownCounter.v)
//
// Matches the DUT port list exactly:
//   DUT inputs   : clk, rst_n, en, up_down, load, load_value
//   DUT outputs  : count, max_tick, min_tick
//
// NOTE (this is the bug in the original snippet):
//   clk / rst_n belong in the PORT list "( ... )", not in the
//   parameter list "#( ... )". The parameter port list may only hold
//   parameters (IEEE 1800-2017 / 1800-2023, parameter_port_declaration),
//   so "#(input clk, input rst_n)" is a syntax error.
//   WIDTH must be declared as a parameter, otherwise it is undeclared.
//
// Sweep in the TB top:
//   logic clk, rst_n;
//   counter_if #(.WIDTH(4)) cif (clk, rst_n);
//
//   up_down_counter #(.WIDTH(4)) dut (
//       .clk        (cif.clk),
//       .rst_n      (cif.rst_n),
//       .en         (cif.en),
//       .up_down    (cif.up_down),
//       .load       (cif.load),
//       .load_value (cif.load_value),
//       .count      (cif.count),
//       .max_tick   (cif.max_tick),
//       .min_tick   (cif.min_tick)
//   );
//
// Two DUTs (e.g. SATURATE=0 and SATURATE=1) need one interface
// instance each - a single instance cannot carry two drivers on
// count / max_tick / min_tick.
//=============================================================================

interface counter_if #(
    parameter int WIDTH = 8
) (
    input logic clk,
    input logic rst_n
);

    logic             en;
    logic             up_down;
    logic             load;
    logic [WIDTH-1:0] load_value;
    logic [WIDTH-1:0] count;
    logic             max_tick;
    logic             min_tick;

    //------------------------------------------------------------------
    // Modports - optional, but they catch direction mistakes at compile
    // time and are what a virtual interface should be declared against.
    //------------------------------------------------------------------
    modport dut (
        input  clk,
        input  rst_n,
        input  en,
        input  up_down,
        input  load,
        input  load_value,
        output count,
        output max_tick,
        output min_tick
    );

    modport tb (
        input  clk,
        input  rst_n,
        input  count,
        input  max_tick,
        input  min_tick,
        output en,
        output up_down,
        output load,
        output load_value
    );

    //------------------------------------------------------------------
    // Clocking block - removes the posedge race between the TB driving
    // inputs and the DUT sampling them. Use "cif.cb.<signal>" in the TB.
    //------------------------------------------------------------------
    clocking cb @(posedge clk);
        default input #1step output #0;
        input  count;
        input  max_tick;
        input  min_tick;
        output en;
        output up_down;
        output load;
        output load_value;
    endclocking : cb

endinterface : counter_if
