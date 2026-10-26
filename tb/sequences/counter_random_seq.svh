//=============================================================================
// counter_random_seq  -  N fully random items
//
// Equivalent to the original "task body(); `uvm_do(req); endtask" but with
//   - an explicitly created / checked item,
//   - a controllable, randomizable length,
//   - repo-style start_item / finish_item instead of the `uvm_do macro.
//
// Start it from a test with:
//   counter_random_seq seq = counter_random_seq::type_id::create("seq");
//   if (!seq.randomize() with { num_items == 100; }) `uvm_fatal(...)
//   seq.start(env.counter_agent_h.counter_sequencer_h);
//=============================================================================

`ifndef COUNTER_RANDOM_SEQ_SVH
`define COUNTER_RANDOM_SEQ_SVH

class counter_random_seq extends counter_base_seq;

  `uvm_object_utils(counter_random_seq)

  rand int unsigned num_items;

  constraint num_items_c {
    num_items inside {[1:100]};
  }

  extern function new(string name = "counter_random_seq");
  extern virtual task body();

endclass: counter_random_seq

function counter_random_seq::new(string name = "counter_random_seq");
  super.new(name);
endfunction: new

task counter_random_seq::body();
  counter_seq_item req;

  if (!this.randomize()) begin
    `uvm_fatal(get_name(), "Couldn't randomize num_items")
  end

  `uvm_info(get_name(),
            $sformatf("Driving %0d random counter items", num_items), UVM_MEDIUM)

  repeat (num_items) begin
    req = counter_seq_item::type_id::create("req");
    start_item(req);
    if (!req.randomize()) begin
      `uvm_fatal(get_name(), "Couldn't randomize counter_seq_item")
    end
    finish_item(req);
  end
endtask: body

`endif
