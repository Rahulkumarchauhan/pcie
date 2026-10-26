//=============================================================================
// counter_seq_item  -  sequence item for up_down_counter (rtl/UpDownCounter.v)
//
// Stimulus fields are the DUT inputs only:
//   en, up_down, load, load_value
// The observed fields (count, max_tick, min_tick) are filled by the monitor
// when it re-uses this item; they are NOT randomized here.
//
// NOTE (bugs in the original snippet):
//   - uvm_sequence_item is NOT a parameterized class, so
//     "extends uvm_sequence_item #(parameter int WIDTH=8)" does not compile.
//     A class that inherits a parameterized base needs
//     "class X #(int W=8) extends uvm_sequence_item;" plus
//     `uvm_object_param_utils(X #(W)) - not needed here, use a localparam.
//   - "super.new(sequence_item)" passes a *type* where a string is required;
//     must be "super.new(name)".
//=============================================================================

`ifndef COUNTER_WIDTH
  `define COUNTER_WIDTH 8
`endif

/******************************** Class Header ********************************************/
class counter_seq_item extends uvm_sequence_item;

  // UVM Factory Registration Macro
  `uvm_object_utils(counter_seq_item)

  // Width must match counter_if / up_down_counter #(.WIDTH(...))
  localparam int          WIDTH   = `COUNTER_WIDTH;
  localparam logic [WIDTH-1:0] MAX_VAL = {WIDTH{1'b1}};

  //  Group: Variables - stimulus (driven into the DUT)
  rand logic             en;
  rand logic             up_down;
  rand logic             load;
  rand logic [WIDTH-1:0] load_value;

  //  Group: Variables - observed (sampled by the monitor, never driven)
  logic [WIDTH-1:0]      count;
  logic                  max_tick;
  logic                  min_tick;

  //  Group: Constraints
  // Keep the DUT mostly counting; load and disable are rare corner cases.
  constraint c_load_dist {
    load dist { 1'b0 := 90, 1'b1 := 10 };
  }

  constraint c_en_dist {
    en dist { 1'b1 := 95, 1'b0 := 5 };
  }

  // Bias loads towards the wrap / clamp corners so max_tick & min_tick
  // actually get hit. Guarded for WIDTH == 1.
  constraint c_load_value_dist {
    if (MAX_VAL > 1) {
      load_value dist { {WIDTH{1'b0}} := 25,
                        MAX_VAL         := 25,
                        [1 : MAX_VAL-1] := 50 };
    }
  }

  // Different seeds -> different mix; keeps the "hold" case reproducible.
  constraint c_dir_soft {
    soft up_down == 1'b1;
  }

  extern function new(string name = "counter_seq_item");
  extern function void do_copy(uvm_object rhs);
  extern function bit do_compare(uvm_object rhs, uvm_comparer comparer);
  extern function string convert2string();
  extern function void do_print(uvm_printer printer);

endclass: counter_seq_item
/*******************************************************************************************/

/********************************* Class Implementation ************************************/

function counter_seq_item::new(string name = "counter_seq_item");
  super.new(name);
endfunction: new

function void counter_seq_item::do_copy(uvm_object rhs);
  counter_seq_item rhs_;

  if (!$cast(rhs_, rhs)) begin
    `uvm_fatal("do_copy", "cast of rhs object to counter_seq_item failed")
  end

  super.do_copy(rhs);
  this.en         = rhs_.en;
  this.up_down    = rhs_.up_down;
  this.load       = rhs_.load;
  this.load_value = rhs_.load_value;
  this.count      = rhs_.count;
  this.max_tick   = rhs_.max_tick;
  this.min_tick   = rhs_.min_tick;
endfunction: do_copy

// Only the driven fields take part in a comparison: what the driver sends
// is what the scoreboard cares about.
function bit counter_seq_item::do_compare(uvm_object rhs, uvm_comparer comparer);
  counter_seq_item rhs_;

  if (!$cast(rhs_, rhs)) begin
    `uvm_error("do_compare", "cast of rhs object failed")
    return 0;
  end

  return ((super.do_compare(rhs, comparer)) &&
          (this.en         == rhs_.en)         &&
          (this.up_down    == rhs_.up_down)    &&
          (this.load       == rhs_.load)       &&
          (this.load_value == rhs_.load_value));
endfunction: do_compare

function string counter_seq_item::convert2string();
  return $sformatf("COUNTER Seq Item: en=%0b up_down=%0b load=%0b load_value=0x%0h | count=0x%0h max_tick=%0b min_tick=%0b",
                   this.en, this.up_down, this.load, this.load_value,
                   this.count, this.max_tick, this.min_tick);
endfunction: convert2string

function void counter_seq_item::do_print(uvm_printer printer);
  printer.m_string = this.convert2string();
endfunction: do_print

/*******************************************************************************************/
