//=============================================================================
// counter_corner_seq  -  directed sequence that hits max_tick / min_tick
//
// Random stimulus almost never lands on 0 or MAX, which is where the
// interesting DUT behaviour lives (terminal counts, wrap vs clamp).
//
// Sequence:
//   load MAX, count up, count up   -> max_tick, then wrap (SATURATE=0)
//                                     or hold at MAX (SATURATE=1)
//   load 0,   count down, down     -> min_tick, then wrap or hold at 0
//   hold with en=0
//   load mid-range and count both ways
//=============================================================================

`ifndef COUNTER_CORNER_SEQ_SVH
`define COUNTER_CORNER_SEQ_SVH

class counter_corner_seq extends counter_base_seq;

  `uvm_object_utils(counter_corner_seq)

  extern function new(string name = "counter_corner_seq");
  extern virtual task body();

endclass: counter_corner_seq

function counter_corner_seq::new(string name = "counter_corner_seq");
  super.new(name);
endfunction: new

task counter_corner_seq::body();
  `uvm_info(get_name(), "Started counter_corner_seq", UVM_MEDIUM)

  // ---- top end: load MAX, then two up-counts -------------------------
  send(1'b1, 1'b1, 1'b1, MAX_VAL);   // load MAX
  send(1'b1, 1'b1, 1'b0, MAX_VAL);   // max_tick asserted here
  send(1'b1, 1'b1, 1'b0, MAX_VAL);   // wrap to 0 / clamp at MAX

  // ---- bottom end: load 0, then two down-counts ----------------------
  send(1'b1, 1'b0, 1'b1, MIN_VAL);   // load 0
  send(1'b1, 1'b0, 1'b0, MIN_VAL);   // min_tick asserted here
  send(1'b1, 1'b0, 1'b0, MIN_VAL);   // wrap to MAX / clamp at 0

  // ---- hold: en low, clock keeps running ----------------------------
  send(1'b0, 1'b1, 1'b0, MIN_VAL);
  send(1'b0, 1'b0, 1'b0, MIN_VAL);
  send(1'b1, 1'b1, 1'b0, MIN_VAL);   // resume counting

  // ---- load wins over counting --------------------------------------
  send(1'b1, 1'b1, 1'b1, MAX_VAL >> 1);

  // ---- mid-range up / down ------------------------------------------
  repeat (4) send(1'b1, 1'b1, 1'b0, MIN_VAL);
  repeat (4) send(1'b1, 1'b0, 1'b0, MIN_VAL);

  `uvm_info(get_name(), "Finished counter_corner_seq", UVM_MEDIUM)
endtask: body

`endif
