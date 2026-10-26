//=============================================================================
// counter_base_seq  -  base sequence for the counter agent
//
// REQ type must match the sequencer and the driver:
//   uvm_sequencer #(counter_seq_item)  <->  counter_sequence #(counter_seq_item)
//   counter_driver : uvm_driver #(counter_seq_item)
//
// A type mismatch between any of those three is a compile/elaboration error
// ("incompatible REQ type"), so never mix counter_seq_item and a raw
// uvm_sequence_item here.
//=============================================================================

`ifndef COUNTER_BASE_SEQ_SVH
`define COUNTER_BASE_SEQ_SVH

class counter_base_seq extends uvm_sequence #(counter_seq_item);

  `uvm_object_utils(counter_base_seq)

  // Pulled from the item so the width is defined in exactly one place.
  localparam int               WIDTH   = counter_seq_item::WIDTH;
  localparam logic [WIDTH-1:0] MAX_VAL = counter_seq_item::MAX_VAL;
  localparam logic [WIDTH-1:0] MIN_VAL = {WIDTH{1'b0}};

  extern function new(string name = "counter_base_seq");
  extern virtual task body();

  // Build, start, drive and finish one item in a single call.
  // Uses start_item/finish_item (not the deprecated `uvm_do macro).
  extern task send(input bit en,
                   input bit up_down,
                   input bit load,
                   input logic [WIDTH-1:0] load_value);

endclass: counter_base_seq

function counter_base_seq::new(string name = "counter_base_seq");
  super.new(name);
endfunction: new

// Stimulus lives in the derived sequences.
task counter_base_seq::body();
endtask: body

task counter_base_seq::send(input bit en,
                            input bit up_down,
                            input bit load,
                            input logic [WIDTH-1:0] load_value);
  counter_seq_item req = counter_seq_item::type_id::create("req");

  start_item(req);
  req.en         = en;
  req.up_down    = up_down;
  req.load       = load;
  req.load_value = load_value;
  finish_item(req);
endtask: send

`endif
