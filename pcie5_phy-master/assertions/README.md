# SVA assertions for the PCIe 5.0 PHY

`pcie5_phy_assertions.sv` contains **10 SystemVerilog assertions** for the RTL in
`../rtl`. The checker is attached to the `PCIe` top module with a `bind`
statement, so **no RTL file and no testbench file has to be modified** – compiling
one extra file is enough.

| # | Name (label in the report) | What it checks | Block |
|---|----------------------------|----------------|-------|
| A01 | `a01_tlp_framing` | `pl_tlpend` may only be asserted after a `pl_tlpstart` was seen since the link came up (no un-framed TLP) | LPIF / RX data flow |
| A02 | `a02_dllp_framing` | same rule for DLLPs: `pl_dlpend` requires an open `pl_dlpstart` | LPIF / RX data flow |
| A03 | `a03_speedmode_vs_gen` | `pl_speedmode` must be the encoding of the running generation (`GEN-1`, 0…4) and `GEN` must be 1…5 – catches a broken LPIF/PHY speed handshake | LPIF ↔ PHY |
| A04 | `a04_reset_quiescent` | while `lpreset` is low the PHY must be down (`pl_linkUp = 0`) and back in Gen1 | reset |
| A05 | `a05_ltssm_lock_step` | TX and RX substate always move together and carry a legal encoding (0…20) | main LTSSM |
| A06 | `a06_lpif_reset_drops_link` | `lp_state_req = Reset` must bring `pl_linkUp` down within 4 cycles | LTSSM ↔ LPIF |
| A07 | `a07_powerdown_in_detect` | every lane drives `PowerDown = P1 (4'd2)` in Detect.Quiet / Detect.Active | PIPE control |
| A08 | `a08_startblock_needs_sync_header` | `TxStartBlock` may only be high together with a valid sync header (`01` data block / `10` OS block) | PIPE TX |
| A09 | `a09_rxvalid_needs_rxstatus0` | a lane may only assert `RxDataValid` while its `RxStatus` is `000` | PIPE RX |
| A10 | `a10_link_number_strobe` / `a10_rate_id_strobe` | the link number and the rate identifier may only change when the matching write strobe from the LTSSM is asserted | configuration registers |

A07, A08 and A09 are per-lane, so with `LANESNUMBER = 16` the file contains 10
assertion rules / 10 + 2·16 = 42 instantiated properties.

## How to run them

The flow is already wired into the testbench makefiles:

```bash
cd tb/sim
make build          # compiles rtl/*.v, the UVM env and the assertions
make run            # reset_vseq,link_up_vseq,enter_recovery_vseq,...
```

* compile line used (`tb/top/top.mk`): `vlog ../../assertions/pcie5_phy_assertions.sv`
* switch them off again: `make build SVA_ENABLE=0`
* or, without touching the makefiles, compile the file by hand after the RTL:
  `vlog +incdir+../.. ../assertions/pcie5_phy_assertions.sv`

Every failure prints a message that names the rule, e.g.

```
%Error: A06: pl_linkUp is still asserted 4 cycles after the LPIF requested Reset (lp_state_req=0)
```

Assertions are quiet while `lpreset` is low and during the first clock edge after
reset, so un-initialised registers never cause a false failure at time 0.

## How the rules were validated

`pcie5_phy_assertions.sv` was linted against the real `PCIe` declaration
(ports + internal nets taken from `rtl/PCIE.v`) and then executed:

* **legal stimulus** → 0 failures,
* **one injected violation at a time** → exactly the matching rule fired:

| injected bug | rule that fired |
|---|---|
| TLP end without a start | `a01_tlp_framing` |
| DLLP end without a start | `a02_dllp_framing` |
| `GEN` = 7 (illegal) | `a03_speedmode_vs_gen` |
| link up while `lpreset` low | `a04_reset_quiescent` |
| TX/RX substate out of lock-step | `a05_ltssm_lock_step` |
| link ignores the LPIF Reset request | `a06_lpif_reset_drops_link` |
| `PowerDown` != P1 in Detect | `a07_powerdown_in_detect` |
| `TxStartBlock` with sync header `00` | `a08_startblock_needs_sync_header` |
| `RxDataValid` with `RxStatus = 011` | `a09_rxvalid_needs_rxstatus0` |
| link number / rate id changed with no strobe | `a10_link_number_strobe`, `a10_rate_id_strobe` |

The same runs can be repeated locally (no commercial licence needed) with

```bash
cd sva_smoke && make          # needs verilator
```

`sva_smoke/` contains a **stub** of the `PCIe` interface with a tiny behavioural
body – it is a harness for the checker, *not* a model of the design. The real
regression remains the UVM environment in `tb/`.

## Notes / findings for the RTL

While writing the rules three things showed up that are worth a look
(none of them is caused by the assertions):

1. `rtl/PIPE_Data.v:24` – `always @(/*posedge pclk or negedge reset_n*/*)`:
   the sensitivity list is empty. Depending on the simulator this either does
   nothing after time 0 (the whole TX PIPE output path – `TxData`, `TxDataValid`,
   `TxDataK`, `TxSyncHeader`, `TxStartBlock` – stays frozen) or is silently
   treated as `always @*`. A08 is written so that it holds either way, but the
   block should be given a real sensitivity list.
2. `tb/top/hdl_top.sv` – the DUT instance connects `.RxDataK(PIPE.RxDataValid)`:
   the `RxDataK` input of the PHY is tied to the 16-bit `RxDataValid` bus, so
   the K-character input of the DUT is not what the PIPE driver intends.
3. `rtl/maintlssm.v` – in the `configurationIdle` case of the `reset_` LPIF
   state, `linkUp` is still set to 1 while `lpifStateStatus` reports `Reset`.
   A06 tolerates it (the link does go down two cycles later), but the two
   signals are momentarily inconsistent.

## Possible next assertions

* `pl_tlpedb` only directly after a `pl_tlpend` (end of a TLP that needs padding),
* `pl_valid` must be a contiguous run of ones (no holes in the beat),
* `PCLKRate == GEN + 1 - width` (the clock divider implied by the negotiated
  generation and the PIPE width),
* scrambling must be disabled for TS1/TS2 and enabled for TLPs
  (`disableScrambler` / `turnOffScrambler_flag`),
* EIEOS sequence: `K28.5 D10.2 …` symbol pattern on every lane at the same time.
