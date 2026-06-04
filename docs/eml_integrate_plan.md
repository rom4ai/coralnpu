# Minimal VEML Decode Patch For EML Instruction Pipeline Integration

## Original Idea

integrate emlunit into decode face and create whole simulation tests for new add RVV eml instruction

## Primary Direction: Minimal Decode + ALU Wire-Through

### Rationale

Patch the decode path to recognize VEML funct6 and wire the already-instantiated EML ALU unit into the result mux — smallest surface, fastest to verify.

### Approach Summary

Patch the first-stage Verilog decode (`rvv_backend_decode_unit_ari.sv`) to recognize `VEML` funct6 and compute its EMUL, EEW, and validity checks, thereby allowing VEML instructions to flow through the already-wired EML ALU path. The EML ALU unit wrapper (`rvv_backend_alu_unit_eml.sv`) is already fully implemented and instantiated inside `rvv_backend_alu_unit.sv` with highest priority in the result mux. The second-stage decode (`rvv_backend_decode_unit_ari_de2.sv`) already routes VEML to the ALU execution unit. The only blocking gap is that the first-stage decode does not handle VEML, causing the `inst_encoding_correct` signal to be de-asserted and the instruction silently dropped. Specifically:

1. Add `VEML` to the EMUL computation `case` block under OPIVV (alongside VADD, VSUB, etc.) in `rvv_backend_decode_unit_ari.sv` — VEML is a standard SEW-width element operation with vs2 and vs1 sources, scaling with LMUL.
2. Add `VEML` to the EEW computation `case` block under `valid_opi` (alongside VADD, VSUB, etc.) — uses SEW=32 for FP32 operands.
3. Add `VEML` to the `check_special` logic under OPIVV — requires `check_vd_overlap_v0` (like VADD), standard register overlap check.
4. No changes needed in `rvv_backend_alu_unit.sv`, `rvv_backend_alu_unit_eml.sv`, `EMLUnit.sv`, `rvv_backend_decode_unit_ari_de2.sv`, or any dispatch logic — those are already complete.

Core mechanism: VEML uses funct6=`6'b000_001` (defined in `rvv_backend.svh:189`) with funct3=OPIVV (`3'b000`), operates on FP32 data, and computes `exp(vs2) - ln(vs1)` per vector element via the multi-cycle EML pipeline (latency=8). The existing ALU unit's result mux already treats EML as a bypass path with highest priority.

### Objective Evidence

- `/fact_data/shiruizhao/coralnpu/hdl/verilog/rvv/inc/rvv_backend.svh` — VEML funct6 defined at line 189 as `parameter VEML = 6'b000_001`, adjacent to VADD (`6'b000_000`). EXE_UNIT_e enum defines ALU as the primary exe unit.
- `/fact_data/shiruizhao/coralnpu/hdl/verilog/rvv/design/rvv_backend_alu_unit_eml.sv` — Complete EML ALU wrapper with per-lane EMLUnit instantiation, latency counter (EML_LATENCY=8), state machine, and result assembly. Already `include "EMLUnit.sv"`.
- `/fact_data/shiruizhao/coralnpu/hdl/verilog/rvv/design/EMLUnit.sv` — Complete EML datapath: FP32 multiplier, FP32 adder, ExpApprox (pipelined), LnApprox (pipelined + delay chain), and subtractor to compute `exp(x) - ln(y)`.
- `/fact_data/shiruizhao/coralnpu/hdl/verilog/rvv/design/rvv_backend_alu_unit.sv` — EML instantiated at lines 101-112 (u_alu_eml). Result mux with EML given highest priority (checked first, before standard units). EML signals (result_valid_eml, result_eml, pop_rs_eml) declared at lines 60-63.
- `/fact_data/shiruizhao/coralnpu/hdl/verilog/rvv/design/rvv_backend_decode_unit_ari_de2.sv` — VEML already placed at line 239 in ALU routing case (valid_opi block). Execution unit assignment: `uop_exe_unit = ALU`.
- `/fact_data/shiruizhao/coralnpu/hdl/verilog/rvv/design/rvv_backend_decode_unit_ari.sv` — **The gap**: VEML is absent from EMUL computation, EEW computation, and check_special. No case branch exists for `VEML` anywhere in this 3355-line file.
- `/fact_data/shiruizhao/coralnpu/hdl/verilog/rvv/design/BUILD` — Both `rvv_backend_alu_unit_eml.sv` and `EMLUnit.sv` are exported, confirming they are part of the build.
- Prior art for decode patching: `VADD` (funct6=`000_000`) serves as the exact template — it appears in every code path that VEML needs to be added to (EMUL, EEW, check_special, de2 routing), and VEML is the immediately adjacent funct6 encoding. The pattern is clear: copy VADD's handling to VEML's case branches in the three missing code paths.

### Known Risks

- The EML unit uses a fixed 8-cycle pipeline (EML_LATENCY=8), but the first-stage decode assumes EML is a single-cycle ALU op. If the decode splits the vector instruction into multiple uops, the ALU reservation station could dispatch back-to-back EML uops before the first completes — potential for resource contention since the EML ALU wrapper can only process one uop at a time (non-pipelined, `busy` flag serializes).
- EML uses OPIVV funct3 per de2 routing, but the EML wrapper's own comment says "uses OPFVV funct3 with a custom funct6 encoding". This inconsistency suggests the encoding choice may still be in flux. The de2 code already routes via OPIVV, so the patch should follow that precedent.
- The EML ALU unit bypasses the standard pipeline (p0 → p1) and inserts directly into the result mux. This means the empty/full tracking of the ALU reservation station must account for a uop being consumed but producing no output for 8 cycles. The `pop_rs_eml` signal handles this, but the RS depth sizing (`ALU_RS_DEPTH=4` or `8` depending on DISPATCH mode) was not designed with multi-cycle ALU ops in mind.
- No Chisel representation or Chisel-level tests exist for VEML — integration testing must be done entirely at the Verilog/system-verilog level.
- The EMLUnit (Chisel-generated FIRRTL output) has its own internal pipeline stage registers; its behavior under reset/trap_flush conditions needs verification since the ALU wrapper applies `~rst_n` to an active-high reset unit.

## Alternative Directions Considered

### Alt-1: Full Decode + EXE Pipeline Integration

- Gist: Complete all pipeline concerns beyond the minimal decode patch: multi-cycle latency awareness in hazard detection (RAW data hazards between uops), result forwarding for EML partial results, dispatch credit-based back-pressure to avoid ALU RS blocking by 8-cycle EML operations, and comprehensive flush handling. The EML ALU wrapper already handles `trap_flush_rvv` (resets FSM on flush), but the dispatch_ctrl and retire modules lack multi-cycle awareness — back-to-back EML instructions could starve single-cycle ALU ops sharing the same reservation station.
- Objective Evidence:
  - `/fact_data/shiruizhao/coralnpu/hdl/verilog/rvv/design/rvv_backend_dispatch_ctrl.sv` lines 107-170 — ALU/CMP uops route to alu RS; no EML-specific RS or credit tracking exists
  - `/fact_data/shiruizhao/coralnpu/hdl/verilog/rvv/design/rvv_backend_dispatch_structure_hazard.sv` — VRF read port structure hazard check; no EML-specific handling
  - `/fact_data/shiruizhao/coralnpu/hdl/verilog/rvv/design/rvv_backend_dispatch_bypass.sv` — No forwarding path for EML multi-cycle partial results
  - `/fact_data/shiruizhao/coralnpu/hdl/verilog/rvv/sve/rvv_backend_tb/src/rvv_behavior_model.sv` (3234 lines) — No VEML instruction handling in the reference behavioral model
- Why not primary: This direction addresses legitimate pipeline risks but represents an order of magnitude more work (~200+ LOC across 5+ files) for issues that can be validated incrementally after the minimal decode patch is verified working; the ALU RS blocking concern can be measured empirically first.

### Alt-2: Cocotb Test-First Incremental Integration

- Gist: Follow the established cocotb `rvv_arithmetic_test` template pattern with `template_rule` macro, write EML tests first. Create a C++ test template with float32 vector operands calling the VEML intrinsic, add test entries to `tests/cocotb/rvv/arithmetics/BUILD` following the exact template_rule pattern, implement a Python cocotb testcase with numpy-based golden reference (`exp(x) - y`), and iterate on hardware decode fixes until tests pass. Also requires adding VEML to the `SAME_TYPE_BINARY_OPS` in `coralnpu_test_utils/rvv_cpp_util_header_generator.py` and to the `rvv_arith_tests` filegroup.
- Objective Evidence:
  - `/fact_data/shiruizhao/coralnpu/tests/cocotb/rvv/arithmetics/rvv_arithmetic_template.cc` (62 lines) — Existing C++ template with placeholder substitution for math_op, sew, dtype
  - `/fact_data/shiruizhao/coralnpu/tests/cocotb/rvv/arithmetics/BUILD` (1440 lines) — Exact template_rule + coralnpu_v2_binary pattern for mass test generation
  - `/fact_data/shiruizhao/coralnpu/coralnpu_test_utils/rvv_cpp_util_header_generator.py` lines 223-266 — `SAME_TYPE_BINARY_OPS` list lacks VEML
  - `/fact_data/shiruizhao/coralnpu/tests/cocotb/rvv_arithmetic_cocotb_test.py` (800+ lines) — Python cocotb testcases with numpy reference models
  - The Chisel decode gap: `hdl/chisel/src/coralnpu/rvv/RvvDecode.scala` and `RvvAlu.scala` have zero VEML support — the Chisel S1 pipeline would reject VEML as illegal instruction
- Why not primary: The Chisel-side decode gap blocks cocotb test execution since the S1 pipeline drives the compressed-instruction front-end; without Chisel changes, VEML never reaches the Verilog decode unit. The cocotb approach is downstream-dependent on the Chisel or Verilog decode being fixed first.

### Alt-3: UVM Co-Simulation Full-Stack Verification

- Gist: Leverage the fully operational UVM testbench with MPACT-Sim golden model DPI-C integration and Spike three-way co-simulation checker. Key steps: add EML instruction semantics (`exp(x) - ln(y)`) to the external `coralnpu_mpact` C++ golden model so that `mpact_step()` correctly computes vector register results; extend coverage group `Cvgrp_Custom.sv` to add EML-specific crossings; add VEML to random instruction stream generator `rvv_zve32x_inst_sequences.sv`; write ELF programs exercising EML instructions; and run through the existing `coralnpu_regression_test` framework.
- Objective Evidence:
  - `/fact_data/shiruizhao/coralnpu/tests/uvm/common/cosim/coralnpu_cosim_checker_pkg.sv` (540 lines) — Full MPACT DPI-C golden comparison with VPR writeback detection
  - `/fact_data/shiruizhao/coralnpu/tests/uvm/common/cosim/spike_cosim_checker.sv` (175 lines) — Three-way checker (RTL vs MPACT vs Spike)
  - `/fact_data/shiruizhao/coralnpu/tests/uvm/Makefile` (194 lines) — Automated build/run flow with `make rtl` + `make run_3way`
  - `/fact_data/shiruizhao/coralnpu/tests/uvm/common/rvvi_agent/Cvgrp_Custom.sv` (28 lines) — Existing custom instruction coverage with only MPAUSE; trivial to extend
  - Spike does not recognize the custom VEML opcode — requires either custom Spike patches or must skip Spike for EML instructions, reducing the 3-way safety net to 2-way
- Why not primary: Requires modifying the external MPACT-Sim repository (coordinated versioning) and the EML floating-point hardware uses LUT-based approximations that won't bit-match standard math library results — needs tolerance-based comparison rather than exact match, adding verification complexity.

## Synthesis Notes

The three alternative directions each contribute valuable elements that could fold into the primary decode-integration path. From Alt-2 (Cocotb TDD), the test-template pattern in `tests/cocotb/rvv/arithmetics/` provides a proven workflow for creating end-to-end EML instruction tests once the decode gap is closed — the cocotb test should be the second step after the decode patch, not the first. From Alt-3 (UVM), the `Cvgrp_Custom.sv` extension is trivial (28 lines) and should be done immediately for coverage tracking; the MPACT golden model comparison provides the strongest signal for multi-cycle correctness. The Alt-1 (Full Pipeline) concerns about ALU RS contention and multi-cycle hazard detection are real but should be measured empirically after the minimal patch — they may not manifest at current dispatch widths. The recommended execution sequence is: (1) Minimal decode patch for functional VEML flow, (2) Cocotb end-to-end test for basic correctness, (3) VEML behavioral model addition + UVM co-sim for golden comparison, (4) Pipeline stress testing to quantify ALU RS contention and determine if Alt-1 mitigations are needed.
