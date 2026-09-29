# pcie5_phy
PCIE 5.0 Graduation project (Verification Team)

To run the Environment: 
- navigate to tb/sim
- run  `make build` to build the environment
- run `make run` to run the code

## Assertions
The environment also builds 10 bind-able SystemVerilog assertions for the PHY
(`assertions/pcie5_phy_assertions.sv`, compiled by `tb/top/top.mk`).  They need
no change in the RTL or in the testbench - the file binds itself to the `PCIe`
module.  Turn them off with `make build SVA_ENABLE=0`.
Details, coverage and the RTL findings they uncovered: `assertions/README.md`.
