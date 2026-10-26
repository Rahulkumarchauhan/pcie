//=============================================================================
// counter_driver  -  drives counter_seq_item onto counter_if
//
// Rules this driver follows (and the original snippet broke):
//   1. It drives ONLY DUT inputs: en, up_down, load, load_value.
//      count / max_tick / min_tick are DUT outputs - never driven here.
//   2. It waits for reset to be released before driving, and parks the
//      interface in a known state first.
//   3. All pin writes go through the clocking block so there is no
//      posedge race between driver and DUT.
//   4. The argument type is counter_seq_item, not uvm_sequence_item,
//      so the item's own fields are visible without a $cast.
//
// The package must see the interface, so compile with:
//   `include "counter_if.sv"        (or reference a pre-compiled one)
// and the TB top must publish a MATCHING specialization:
//   uvm_config_db#(virtual counter_if #(COUNTER_WIDTH))::set(
//       null, "*", "vif", cif);
//
// If the set() and get() widths differ, get() returns 0 and the fatal
// below fires - that is the most common config_db mistake here.
//=============================================================================

`ifndef COUNTER_DRIVER_SVH
`define COUNTER_DRIVER_SVH

class counter_driver extends uvm_driver #(counter_seq_item);

  `uvm_component_utils(counter_driver)

  // Must match counter_seq_item::WIDTH and the DUT's WIDTH parameter.
  localparam int WIDTH = counter_seq_item::WIDTH;

  // Parameterised virtual interface: the width is part of the type.
  // (Use "./counter_if.sv" if your flow prefers a file include.)
  virtual counter_if #(WIDTH) vif;

  function new(string name = "counter_driver", uvm_component parent = null);
    super.new(name, parent);
  endfunction: new

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual counter_if #(WIDTH))::get(this, "", "vif", vif)) begin
      `uvm_fatal(get_name(), "Driver didn't get the virtual interface 'vif' from config_db")
    end
  endfunction: build_phase

  task run_phase(uvm_phase phase);
    super.run_phase(phase);

    // Never drive into reset.
    wait (vif.rst_n === 1'b1);
    @(vif.cb);
    idle();
    `uvm_info(get_name(), "Enter counter_driver run_phase", UVM_MEDIUM)

    forever begin
      seq_item_port.get_next_item(req);
      drive_item(req);
      seq_item_port.item_done();
    end
  endtask: run_phase

  //------------------------------------------------------------------
  // Park every DUT input in a safe, non-transacting value
  //------------------------------------------------------------------
  task idle();
    vif.cb.en         <= 1'b0;
    vif.cb.up_down    <= 1'b1;
    vif.cb.load       <= 1'b0;
    vif.cb.load_value <= {WIDTH{1'b0}};
  endtask: idle

  //------------------------------------------------------------------
  // Apply one item, hold it for exactly one DUT clock
  //------------------------------------------------------------------
  task drive_item(counter_seq_item tx);
    vif.cb.en         <= tx.en;
    vif.cb.up_down    <= tx.up_down;
    vif.cb.load       <= tx.load;
    vif.cb.load_value <= tx.load_value;

    @(vif.cb);      // one clock: the DUT samples the item on this edge
  endtask: drive_item

endclass: counter_driver

`endif
