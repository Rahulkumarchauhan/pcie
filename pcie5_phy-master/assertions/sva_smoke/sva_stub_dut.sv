// Smoke-test stub for the SVA checker.  It has the same interface as the real
// rtl/PCIE.v top module but only a small behavioural body, so that the bound
// assertions can be exercised without the full PHY and without a commercial
// simulator:
//    * legal stimulus  -> no assertion may fire
//    * injected bug    -> exactly the matching assertion must fire
// It is NOT a model of the design - the real regression is the UVM env in tb/.
`timescale 1ns/1ps

module PCIe #(
    parameter MAXPIPEWIDTH = 32, parameter DEVICETYPE = 0,
    parameter LANESNUMBER = 16,  parameter GEN1_PIPEWIDTH = 8,
    parameter GEN2_PIPEWIDTH = 8, parameter GEN3_PIPEWIDTH = 8,
    parameter GEN4_PIPEWIDTH = 8, parameter GEN5_PIPEWIDTH = 8,
    parameter MAX_GEN = 1
)(
  input CLK, input lpreset, output phy_reset, output [1:0] width,
  output [MAXPIPEWIDTH*LANESNUMBER-1:0] TxData,
  output [LANESNUMBER-1:0] TxDataValid, output [LANESNUMBER-1:0] TxElecIdle,
  output [LANESNUMBER-1:0] TxStartBlock,
  output [(MAXPIPEWIDTH/8)*LANESNUMBER-1:0] TxDataK,
  output [2*LANESNUMBER-1:0] TxSyncHeader,
  output [LANESNUMBER-1:0] TxDetectRx_Loopback,
  input  [MAXPIPEWIDTH*LANESNUMBER-1:0] RxData,
  input  [LANESNUMBER-1:0] RxDataValid_i,
  input  [(MAXPIPEWIDTH/8)*LANESNUMBER-1:0] RxDataK,
  input  [LANESNUMBER-1:0] RxStartBlock,
  input  [2*LANESNUMBER-1:0] RxSyncHeader,
  input  [3*LANESNUMBER-1:0] RxStatus,
  input  [15:0] RxElectricalIdle,
  output [4*LANESNUMBER-1:0] PowerDown, output [3:0] Rate,
  input  [LANESNUMBER-1:0] PhyStatus,
  output [4:0] PCLKRate, output PclkChangeAck, input PclkChangeOk,
  input  [18*LANESNUMBER-1:0] LocalTxPresetCoefficients,
  output [18*LANESNUMBER-1:0] TxDeemph,
  input  [6*LANESNUMBER-1:0] LocalFS, input [6*LANESNUMBER-1:0] LocalLF,
  output [4*LANESNUMBER-1:0] LocalPresetIndex,
  output [LANESNUMBER-1:0] GetLocalPresetCoeffcients,
  input  [LANESNUMBER-1:0] LocalTxCoefficientsValid,
  output [6*LANESNUMBER-1:0] LF, output [6*LANESNUMBER-1:0] FS,
  output [LANESNUMBER-1:0] RxEqEval, output [LANESNUMBER-1:0] InvalidRequest,
  input  [6*LANESNUMBER-1:0] LinkEvaluationFeedbackDirectionChange,
  output pl_trdy, input lp_irdy, input [511:0] lp_data, input [63:0] lp_valid,
  output [511:0] pl_data, output [63:0] pl_valid, input [3:0] lp_state_req,
  output [3:0] pl_state_sts, output [2:0] pl_speedmode, input lp_force_detect,
  input [63:0] lp_dlpstart, input [63:0] lp_dlpend,
  input [63:0] lp_tlpstart, input [63:0] lp_tlpend,
  output [63:0] pl_dlpstart, output [63:0] pl_dlpend,
  output [63:0] pl_tlpstart, output [63:0] pl_tlpend, output [63:0] pl_tlpedb,
  output pl_linkUp, output [7:0] M2P_MessageBus, input [7:0] P2M_MessageBus,
  output [15:0] RxStandby,
  // ---- stimulus / bug injection inputs (extra ports, not used by bind) ----
  input inj_tlp_end_only,     // A01: pl_tlpend without a start
        inj_gen_bad,          // A03: illegal GEN
        inj_sub_mismatch,     // A05: TX/RX substate not in lock step
        inj_link_stuck,       // A06: link stays up after a Reset request
        inj_powerdown_bad,    // A07: wrong PowerDown in Detect
        inj_sync_bad,         // A08: TxStartBlock without sync header
        inj_rxvalid_bad,      // A09: RxDataValid while RxStatus != 0
        inj_cfg_change,       // A10: config register changes with no strobe
        inj_linkup_in_reset,  // A04: link up while lpreset is low
        inj_dllp_end_only     // A02: pl_dlpend without a start
);
  // ---- internal signals observed by the bound checker -------------------
  wire [2:0] GEN;
  wire [4:0] SetTXState, RXsubstate;
  wire [7:0] rateIdInTx, linkNumberRxInput;
  wire       writerateid, WriteLinkNumFlagRx;
  wire [LANESNUMBER-1:0] RxDataValid;          // what the bind connects to


  // ---- model state -------------------------------------------------------
  logic [2:0] gen_r = 3'd1;
  logic       link_r = 1'b0;
  logic [4:0] st_r   = 5'd0;
  logic [7:0] rate_r = 8'h00, lnk_r = 8'h00;

  assign GEN            = inj_gen_bad ? 3'd7 : gen_r;
  assign SetTXState     = st_r;
  assign RXsubstate     = inj_sub_mismatch ? (st_r ^ 5'd1) : st_r;
  assign pl_speedmode   = (gen_r - 3'd1);
  assign pl_linkUp      = lpreset ? (inj_linkup_in_reset ? 1'b1 : link_r) : 1'b0;
  assign pl_state_sts   = pl_linkUp ? 4'd1 : 4'd0;
  assign pl_tlpstart    = tlp_start_r;
  assign pl_tlpend      = inj_tlp_end_only ? 64'h1 : {63'b0, tlp_end_r};
  assign pl_dlpstart    = 64'b0;
  assign pl_dlpend      = inj_dllp_end_only ? 64'h1 : 64'b0;
  assign pl_tlpedb      = 64'b0;
  assign pl_valid       = 64'b0;
  assign pl_data        = '0;
  assign pl_trdy        = 1'b0;
  assign pl_dlpstart    = 64'b0;
  assign RxDataValid    = inj_rxvalid_bad ? {LANESNUMBER{1'b1}} : RxDataValid_i;
  assign PowerDown      = {LANESNUMBER{(inj_powerdown_bad ? 4'd0 :
                          ((st_r == 5'd0) || (st_r == 5'd1)) ? 4'd2 : 4'd0)}};
  assign TxStartBlock   = inj_sync_bad ? {LANESNUMBER{1'b1}} : {LANESNUMBER{1'b0}};
  assign TxSyncHeader   = inj_sync_bad ? {2*LANESNUMBER{1'b00}} : {2*LANESNUMBER{2'b01}};
  assign rateIdInTx       = rate_r;
  assign linkNumberRxInput = lnk_r;
  assign writerateid       = 1'b0;
  assign WriteLinkNumFlagRx= 1'b0;

  assign phy_reset = lpreset;   assign width = 2'd0;     assign TxData = '0;
  assign TxDataValid = '0;      assign TxElecIdle = '0;  assign TxDataK = '0;
  assign TxSyncHeader = '0;     assign TxDetectRx_Loopback = '0;
  assign PCLKRate = 5'd0;       assign PclkChangeAck = 1'b0; assign Rate = 4'd0;
  assign TxDeemph = '0;         assign LocalPresetIndex = '0; assign LF = '0;
  assign FS = '0;               assign RxEqEval = '0;     assign InvalidRequest = '0;
  assign M2P_MessageBus = 8'h00; assign RxStandby = '0;
  assign GetLocalPresetCoeffcients = '0;

  // one clean TLP: start, then 6 cycles later the end
  logic tlp_start_r = 1'b0, tlp_end_r = 1'b0;
  logic [3:0] cnt = 4'd0;
  always_ff @(posedge CLK) begin
    if (!lpreset) begin
      gen_r <= 3'd1; link_r <= 1'b0; st_r <= 5'd0; cnt <= 4'd0;
      rate_r <= 8'h00; lnk_r <= 8'h00;
      tlp_start_r <= 1'b0; tlp_end_r <= 1'b0;
    end else begin
      // link follows the LPIF request
      if (inj_link_stuck)                 link_r <= link_r;               // ignores Reset
      else if (lp_state_req == 4'd0)      link_r <= 1'b0;
      else if (lp_state_req == 4'd1)     link_r <= 1'b1;
      if (lp_force_detect)               link_r <= 1'b0;

      st_r <= inj_powerdown_bad ? 5'd0 : (link_r ? 5'd10 : ((cnt[3]) ? 5'd0 : 5'd1));

      // a TLP every 16 cycles, only while the link is up
      cnt <= link_r ? (cnt + 4'd1) : 4'd0;
      tlp_start_r <= link_r && (cnt == 4'd5);
      tlp_end_r   <= link_r && (cnt == 4'd11);

      if (inj_gen_bad)  gen_r <= 3'd7;
      else if (gen_r == 3'd1) gen_r <= 3'd2;   // legal speed change to Gen2

      if (inj_cfg_change) begin
        rate_r <= rate_r + 8'h1;              // changes without a write strobe
        lnk_r  <= lnk_r  + 8'h1;
      end
    end
  end
endmodule
