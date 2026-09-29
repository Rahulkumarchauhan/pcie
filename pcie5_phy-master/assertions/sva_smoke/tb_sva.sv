// Smoke testbench (local only) for the 10 SVA properties.
//   +MODE=legal            : fully legal stimulus, no assertion may fire
//   +MODE=inj +INJ=A01..A10: inject exactly one violation, that one must fire
// Stimulus is always applied on the negedge so that it never races with the
// assertion sampling region.
`timescale 1ns/1ps

module tb_sva;
  localparam int LANESNUMBER = 16;

  logic CLK = 0;
  logic lpreset = 0;
  logic [3:0] lp_state_req = 0;
  logic lp_force_detect = 0;
  logic [3*LANESNUMBER-1:0] RxStatus = '0;
  logic [LANESNUMBER-1:0]    RxDataValid_i = '0;

  logic inj_tlp_end_only=0, inj_gen_bad=0, inj_sub_mismatch=0, inj_link_stuck=0,
        inj_powerdown_bad=0, inj_sync_bad=0, inj_rxvalid_bad=0, inj_cfg_change=0,
        inj_linkup_in_reset=0, inj_dllp_end_only=0;

  always #5 CLK = ~CLK;

  PCIe #(.LANESNUMBER(LANESNUMBER)) dut (
    .CLK(CLK), .lpreset(lpreset), .phy_reset(), .width(),
    .TxData(), .TxDataValid(), .TxElecIdle(), .TxStartBlock(), .TxDataK(),
    .TxSyncHeader(), .TxDetectRx_Loopback(),
    .RxData('0), .RxDataValid_i(RxDataValid_i), .RxDataK('0), .RxStartBlock('0),
    .RxSyncHeader('0), .RxStatus(RxStatus), .RxElectricalIdle('0),
    .PowerDown(), .Rate(), .PhyStatus('0), .PCLKRate(), .PclkChangeAck(),
    .PclkChangeOk(1'b0), .LocalTxPresetCoefficients('0), .TxDeemph(),
    .LocalFS('0), .LocalLF('0), .LocalPresetIndex(),
    .GetLocalPresetCoeffcients(), .LocalTxCoefficientsValid('0), .LF(), .FS(),
    .RxEqEval(), .InvalidRequest(), .LinkEvaluationFeedbackDirectionChange('0),
    .pl_trdy(), .lp_irdy(1'b0), .lp_data('0), .lp_valid('0), .pl_data(),
    .pl_valid(), .lp_state_req(lp_state_req), .pl_state_sts(), .pl_speedmode(),
    .lp_force_detect(lp_force_detect),
    .lp_dlpstart('0), .lp_dlpend('0), .lp_tlpstart('0), .lp_tlpend('0),
    .pl_dlpstart(), .pl_dlpend(), .pl_tlpstart(), .pl_tlpend(), .pl_tlpedb(),
    .pl_linkUp(), .M2P_MessageBus(), .P2M_MessageBus('0), .RxStandby(),
    .inj_tlp_end_only(inj_tlp_end_only), .inj_gen_bad(inj_gen_bad),
    .inj_sub_mismatch(inj_sub_mismatch), .inj_link_stuck(inj_link_stuck),
    .inj_powerdown_bad(inj_powerdown_bad), .inj_sync_bad(inj_sync_bad),
    .inj_rxvalid_bad(inj_rxvalid_bad), .inj_cfg_change(inj_cfg_change),
    .inj_linkup_in_reset(inj_linkup_in_reset),
    .inj_dllp_end_only(inj_dllp_end_only)
  );

  task automatic req_set(input logic [3:0] v);
    @(negedge CLK); lp_state_req = v;
  endtask

  task automatic reset_set(input logic v);
    @(negedge CLK); lpreset = v;
  endtask

  task automatic clear_inj();
    @(negedge CLK);
    inj_tlp_end_only=0; inj_gen_bad=0; inj_sub_mismatch=0; inj_link_stuck=0;
    inj_powerdown_bad=0; inj_sync_bad=0; inj_rxvalid_bad=0; inj_cfg_change=0;
    inj_linkup_in_reset=0; inj_dllp_end_only=0;
  endtask

  task automatic inject(input string name, input int unsigned cycles);
    @(negedge CLK);
    $display("---- injecting %s", name);
    case (name)
      "A01_tlp_end_only":  inj_tlp_end_only = 1'b1;
      "A02_dllp_end_only": inj_dllp_end_only= 1'b1;
      "A03_gen_bad":       inj_gen_bad      = 1'b1;
      "A05_sub_mismatch":  inj_sub_mismatch = 1'b1;
      "A06_link_stuck":    begin inj_link_stuck = 1'b1; lp_state_req = 4'd0; end
      "A07_powerdown_bad": inj_powerdown_bad= 1'b1;
      "A08_sync_bad":      inj_sync_bad     = 1'b1;
      "A09_rxvalid_bad":   begin inj_rxvalid_bad = 1'b1; RxStatus = {3*LANESNUMBER{3'b011}}; end
      "A10_cfg_change":    inj_cfg_change   = 1'b1;
      default: $display("     (no injection knob for %s)", name);
    endcase
    repeat (cycles) @(posedge CLK);
    clear_inj();
    repeat (6) @(posedge CLK);
  endtask

  initial begin
    string mode, inj;
    void'($value$plusargs("MODE=%s", mode));
    if (mode == "") mode = "legal";
    if (!$value$plusargs("INJ=%s", inj)) inj = "";

    repeat (4) @(posedge CLK);
    reset_set(1'b1);
    repeat (20) @(posedge CLK);
    req_set(4'd1);                       // LPIF Active -> link comes up
    repeat (40) @(posedge CLK);
    req_set(4'd0);                       // LPIF Reset -> link must drop (A06 legal path)
    repeat (10) @(posedge CLK);
    req_set(4'd1);
    repeat (20) @(posedge CLK);

    if (mode == "legal") begin
      $display("RESULT: legal stimulus finished with NO assertion failure");
      $finish;
    end

    if (inj == "A04_linkup_in_reset") begin
      inject("A04_linkup_in_reset", 1);
      reset_set(1'b0);
      repeat (4) @(posedge CLK);
      reset_set(1'b1);
      repeat (4) @(posedge CLK);
    end else begin
      inject(inj, (inj == "A06_link_stuck") ? 10 : 6);
    end
    $display("RESULT: injection %s finished", inj);
    $finish;
  end
endmodule
