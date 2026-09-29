//======================================================================
// File    : pcie5_phy_assertions.sv
// Project : pcie5_phy  (PCIe Gen1..Gen5 PHY - Verification team)
// Purpose : 10 bind-able SystemVerilog assertions (SVA) for the RTL
// Target  : any IEEE-1800 simulator (Questa / VCS / Xcelium / Verilator)
//
// Usage   : the file is already part of the flow (see tb/top/top.mk):
//              make build            -> assertions on
//              make build SVA_ENABLE=0 -> assertions off
//            The "bind" at the end of the file hooks the checker onto the
//            PCIe top module automatically - the RTL itself is untouched.
//
// Covers  : A01/A02 LPIF packet framing      A06 LTSSM <-> LPIF handshake
//           A03 LPIF speed mode vs. generation A07 PIPE PowerDown
//           A04 reset behaviour               A08 PIPE block start
//           A05 LTSSM substate lock-step      A09 PIPE RX status
//                                            A10 configuration registers
//======================================================================

`ifndef PCIE5_PHY_ASSERTIONS_SV
`define PCIE5_PHY_ASSERTIONS_SV

`default_nettype none

module pcie5_phy_assertions #(
  parameter int LANESNUMBER = 16            // keep in sync with the DUT
)(
  //-------------------------------------------------------------- clock/reset
  input wire                      CLK,
  input wire                      lpreset,        // active low (PIPE lpreset)
  //------------------------------------------------------ LPIF (to controller)
  input wire                      pl_linkUp,
  input wire [3:0]                lp_state_req,   // 0=Reset 1=Active 11=Retrain
  input wire [2:0]                pl_speedmode,   // PHY speed mode toward LPIF
  input wire [63:0]               pl_tlpstart,
  input wire [63:0]               pl_tlpend,
  input wire [63:0]               pl_dlpstart,
  input wire [63:0]               pl_dlpend,
  //------------------------------------------------------------------- LTSSM
  input wire [2:0]                GEN,            // negotiated generation
  input wire [4:0]                SetTXState,     // TX substate  (L0, Recovery..)
  input wire [4:0]                RXsubstate,     // RX substate  (L0, Recovery..)
  //------------------------------------------------------------------- PIPE
  input wire [4*LANESNUMBER-1:0]  PowerDown,
  input wire [LANESNUMBER-1:0]    TxStartBlock,
  input wire [2*LANESNUMBER-1:0]  TxSyncHeader,
  input wire [LANESNUMBER-1:0]    RxDataValid,
  input wire [3*LANESNUMBER-1:0]  RxStatus,
  //------------------------------------------------- configuration registers
  input wire [7:0]                linkNumberRxInput,
  input wire                      WriteLinkNumFlagRx,
  input wire [7:0]                rateIdInTx,
  input wire                      writerateid
);

  //---------------------------------------------------------------- localparams
  //   LTSSM substates : 0=Detect.Quiet  1=Detect.Active  ... 20=Recovery.wait
  //   (the values are written inline in the properties on purpose - some
  //    tools refuse named constants inside an "inside {}" range)
  localparam [4:0] SubstateMax  = 5'd20;   // recoverywait, last encoded state

  //---------------------------------------------------------------- housekeeping
  // "init_done" keeps every assertion quiet until the DUT has seen a real
  // clock edge after reset, so that uninitialised regs never cause a false
  // failure at time 0.
  logic init_done = 1'b0;
  always_ff @(posedge CLK) init_done <= 1'b1;

  // packet framing monitors: a TLP/DLLP is "open" between its start and its end
  logic tlp_frame_open  = 1'b0;
  logic dllp_frame_open = 1'b0;

  always_ff @(posedge CLK) begin
    if (!lpreset || !pl_linkUp) begin            // link down -> nothing in flight
      tlp_frame_open  <= 1'b0;
      dllp_frame_open <= 1'b0;
    end else begin
      tlp_frame_open  <= (tlp_frame_open  || (|pl_tlpstart))  && !(|pl_tlpend);
      dllp_frame_open <= (dllp_frame_open || (|pl_dlpstart)) && !(|pl_dlpend);
    end
  end

  //======================================================================
  // A01 : LPIF (RX) - a TLP end is only legal after a TLP start
  //       PCIe Base Spec. 2.7.1 - every TLP is delimited by start/end
  //======================================================================
  a01_tlp_framing : assert property (@(posedge CLK)
      disable iff (!lpreset || !init_done || !pl_linkUp)
      (|pl_tlpend) |-> (tlp_frame_open || (|pl_tlpstart)))
    else $error({"A01: TLP end (pl_tlpend) without a preceding TLP start ",
                 "- the LPIF RX path delivered an un-framed packet"});

  //======================================================================
  // A02 : LPIF (RX) - a DLLP end is only legal after a DLLP start
  //       PCIe Base Spec. 2.7.1 / 2.7.2 - DLLPs carry their own framing
  //======================================================================
  a02_dllp_framing : assert property (@(posedge CLK)
      disable iff (!lpreset || !init_done || !pl_linkUp)
      (|pl_dlpend) |-> (dllp_frame_open || (|pl_dlpstart)))
    else $error({"A02: DLLP end (pl_dlpend) without a preceding DLLP start ",
                 "- the LPIF RX path delivered an un-framed packet"});

  //======================================================================
  // A03 : LPIF - pl_speedmode must be the encoding of the running generation
  //       LPIF defines speed mode 0..4 for Gen1..Gen5 (PCIe LPIF spec.)
  //       The PHY derives it from GEN inside LPIF_RX_Control_DataFlow,
  //       so a mismatch means the two sides of the PHY disagree.
  //======================================================================
  a03_speedmode_vs_gen : assert property (@(posedge CLK)
      disable iff (!lpreset || !init_done)
      !$isunknown({GEN, pl_speedmode})
      |-> ((GEN inside {[3'd1:3'd5]}) && (pl_speedmode == (GEN - 3'd1))))
    else $error({"A03: pl_speedmode=0b%0b does not match the negotiated ",
                 "generation GEN=0d%0d (expected GEN-1, 0..4)"}, pl_speedmode, GEN);

  //======================================================================
  // A04 : reset behaviour - while lpreset is asserted the PHY must be idle
  //       and must fall back to Gen1 (mainLTSSM resets GEN to 3'd1).
  //======================================================================
  a04_reset_quiescent : assert property (@(posedge CLK)
      disable iff (!init_done)
      (!lpreset) |-> (!pl_linkUp && (GEN == 3'd1)))
    else $error({"A04: during reset the PHY must be down and in Gen1 ",
                 "(pl_linkUp=%0b, GEN=%0d)"}, pl_linkUp, GEN);

  //======================================================================
  // A05 : LTSSM - TX and RX substate always move in lock-step
  //       (mainLTSSM assigns {substateTx,substateRx} as a pair) and both must
  //       carry a legal substate encoding (Detect..Recovery.wait = 0..20).
  //======================================================================
  a05_ltssm_lock_step : assert property (@(posedge CLK)
      disable iff (!lpreset || !init_done)
      !$isunknown({SetTXState, RXsubstate})
      |-> ((SetTXState == RXsubstate) && (SetTXState <= SubstateMax)))
    else $error({"A05: TX substate=%0d / RX substate=%0d - they must be equal ",
                 "and within 0..%0d"}, SetTXState, RXsubstate, SubstateMax);

  //======================================================================
  // A06 : LPIF <-> LTSSM handshake - a Reset request must drop the link
  //       PCIe LPIF spec.: pl_state_req = Reset de-asserts pl_linkUp and
  //       sends the PHY back to Detect.
  //======================================================================
  a06_lpif_reset_drops_link : assert property (@(posedge CLK)
      disable iff (!lpreset || !init_done)
      (lp_state_req == 4'd0) |-> ##[1:4] !pl_linkUp)
    else $error({"A06: pl_linkUp is still asserted 4 cycles after the LPIF ",
                 "requested Reset (lp_state_req=0)"});

  genvar lane;
  generate
    for (lane = 0; lane < LANESNUMBER; lane++) begin : g_lane

      //======================================================================
      // A07 : PIPE control - every lane must be in PowerDown P1 (4'd2) while
      //       the LTSSM sits in Detect.Quiet / Detect.Active
      //       (PIPE spec. 3.3.2 - Detect must be entered with the PHY in P1)
      //======================================================================
      a07_powerdown_in_detect : assert property (@(posedge CLK)
          disable iff (!lpreset || !init_done)
          (SetTXState inside {5'd0, 5'd1})     // Detect.Quiet / Detect.Active
          |-> (PowerDown[4*lane +: 4] == 4'd2))
        else $error({"A07: lane %0d - PowerDown must be P1 (4'd2) in Detect, ",
                     "got 4'h%0h (LTSSM substate=%0d)"},
                    lane, PowerDown[4*lane +: 4], SetTXState);

      //======================================================================
      // A08 : PIPE TX - TxStartBlock may only be asserted together with a
      //       valid sync header (01 = data block, 10 = ordered set block).
      //       PCIe Base Spec. 2.6.1 / PIPE 3.4.1 - the first symbol of a
      //       block carries the sync header, TxStartBlock marks exactly that.
      //======================================================================
      a08_startblock_needs_sync_header : assert property (@(posedge CLK)
          disable iff (!lpreset || !init_done)
          TxStartBlock[lane] |-> (TxSyncHeader[2*lane +: 2] inside {2'b01, 2'b10}))
        else $error({"A08: lane %0d - TxStartBlock asserted while TxSyncHeader ",
                     "is 2'b%0b (only 01 or 10 may start a block)"},
                    lane, TxSyncHeader[2*lane +: 2]);

      //======================================================================
      // A09 : PIPE RX - RxDataValid is only legal while the lane reports
      //       RxStatus = 000 (normal operation).  Any other RxStatus means
      //       the receiver is detecting/idle and must not deliver data.
      //       (PIPE spec. 3.3.3 / 3.4.1)
      //======================================================================
      a09_rxvalid_needs_rxstatus0 : assert property (@(posedge CLK)
          disable iff (!init_done)
          RxDataValid[lane] |-> (RxStatus[3*lane +: 3] == 3'b000))
        else $error({"A09: lane %0d - RxDataValid is high while RxStatus is ",
                     "3'b%0b, it may only be 3'b000"},
                    lane, RxStatus[3*lane +: 3]);
    end
  endgenerate

  //======================================================================
  // A10 : configuration registers are written by a strobe only
  //       (mainLTSSM latches linkNumber / rateId only when the matching
  //       write flag from the LTSSM is asserted) - one rule, two checks:
  //       the link number and the rate identifier.
  //======================================================================
  a10_link_number_strobe : assert property (@(posedge CLK)
      disable iff (!lpreset || !init_done)
      (!WriteLinkNumFlagRx) |-> $stable(linkNumberRxInput))
    else $error({"A10: link number changed from %0h without WriteLinkNumFlagRx ",
                 "being asserted"}, $past(linkNumberRxInput));

  a10_rate_id_strobe : assert property (@(posedge CLK)
      disable iff (!lpreset || !init_done)
      (!writerateid) |-> $stable(rateIdInTx))
    else $error({"A10: rate identifier changed from %0h without writerateid ",
                 "being asserted"}, $past(rateIdInTx));

endmodule : pcie5_phy_assertions

//----------------------------------------------------------------------
// Bind the checker to the PHY top module.  Compiling this file is enough,
// no RTL edit and no TB edit is required.
//----------------------------------------------------------------------
bind PCIe pcie5_phy_assertions #(
    .LANESNUMBER(LANESNUMBER)
) u_pcie5_phy_assertions (
    .CLK               (CLK),
    .lpreset           (lpreset),
    .pl_linkUp         (pl_linkUp),
    .lp_state_req      (lp_state_req),
    .pl_speedmode      (pl_speedmode),
    .pl_tlpstart       (pl_tlpstart),
    .pl_tlpend         (pl_tlpend),
    .pl_dlpstart     (pl_dlpstart),
    .pl_dlpend       (pl_dlpend),
    .GEN               (GEN),
    .SetTXState        (SetTXState),
    .RXsubstate        (RXsubstate),
    .PowerDown         (PowerDown),
    .TxStartBlock      (TxStartBlock),
    .TxSyncHeader      (TxSyncHeader),
    .RxDataValid       (RxDataValid),
    .RxStatus          (RxStatus),
    .linkNumberRxInput (linkNumberRxInput),
    .WriteLinkNumFlagRx(WriteLinkNumFlagRx),
    .rateIdInTx        (rateIdInTx),
    .writerateid       (writerateid)
);

`default_nettype wire

`endif // PCIE5_PHY_ASSERTIONS_SV
