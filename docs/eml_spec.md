# VEML Instruction Decode and ALU Pipeline Integration for Coral NPU RVV Backend

## Goal Description

Integrate the VEML instruction (funct6=`6'b000_001`, funct3=OPIVV) into the Coral NPU RVV backend's decode-to-execute path and create end-to-end simulation tests. The EMLUnit datapath (FP32 `exp(vs2) - ln(vs1)` per element, 8-cycle pipeline) and its ALU wrapper are already fully implemented and instantiated in `rvv_backend_alu_unit.sv`. The decode gap is precisely characterized: VEML is missing from first-stage decode case statements (`rvv_backend_decode_unit_ari.sv`), causing `inst_encoding_correct` to de-assert and silently drop the instruction. Additionally, the EML ALU wrapper has three safety/handshake defects that must be fixed for the instruction to produce correct results: un-gated opcode acceptance, zeroed writeback valid, and missing RS pop handshake.

## Acceptance Criteria

Following TDD philosophy, each criterion includes positive and negative tests for deterministic verification.

- AC-1: VEML instruction (funct6=`000_001`, funct3=OPIVV, SEW=32, unmasked, vstart=0, LMUL=1) decodes successfully and dispatches to the ALU execution unit.
  - Positive Tests (expected to PASS):
    - A VEML instruction with legal encoding (SEW32, LMUL1, vm=1, vstart=0) produces `inst_encoding_correct=1` in `rvv_backend_decode_unit_ari.sv` and `uop_exe_unit=ALU` in the de2 decode.
    - The instruction flows through dispatch to the ALU reservation station and is consumed by `rvv_backend_alu_unit_eml`.
  - Negative Tests (expected to FAIL):
    - A VEML instruction with SEW=8 is rejected (`inst_encoding_correct=0`).
    - A VEML instruction with SEW=16 is rejected.
    - A VEML instruction with funct3=OPIVX is rejected (not in supported ISA subset).
    - A VEML instruction with vm=0 (masked) is rejected if mask support is deferred.
    - A VEML instruction with LMUL=2 (multi-uop) produces correct lane behavior for each uop if enabled, or is rejected if multi-LMUL is deferred.

- AC-2: The EML ALU wrapper only accepts uops whose `uop_funct6 == VEML` and `uop_funct3 == OPIVV`.
  - Positive Tests (expected to PASS):
    - A VEML uop arriving when the EML wrapper is idle is accepted (`busy` transitions to 1, pop_rs asserted).
    - A VADD uop arriving when the EML wrapper is idle is NOT captured (the EML wrapper's `is_eml_op` gate prevents acceptance).
  - Negative Tests (expected to FAIL):
    - Any non-VEML ALU uop (VADD, VSUB, VMUL, etc.) should never cause the EML wrapper's `busy` flag to assert.

- AC-3: VEML results are correctly written back to the vector register file with `w_valid=1` for all active lanes.
  - Positive Tests (expected to PASS):
    - After EML execution completes, the ROB entry shows `w_valid=1` and `w_data` contains the per-lane FP32 results.
    - The vector destination register (`vd`) is updated with the EML result values.
  - Negative Tests (expected to FAIL):
    - VEML result does NOT appear with `w_valid=0` (which would suppress the writeback).
    - Non-VEML ALU results are not corrupted by EML operations executing concurrently.

- AC-4: The ALU reservation station correctly pops EML uops at acceptance time and does not deadlock.
  - Positive Tests (expected to PASS):
    - When the EML wrapper accepts a uop (`is_eml_op && alu_uop_valid && !busy`), `pop_rs` is asserted at the ALU unit output in the same cycle.
    - The RS entry for the consumed EML uop is freed and can accept a new uop.
  - Negative Tests (expected to FAIL):
    - EML uop does NOT remain stuck in the RS for 8 cycles waiting for `result_valid_eml` to assert.
    - Back-to-back EML uops (when the first is still busy) do not cause RS overflow or deadlock.

- AC-5: EML results include mask/tail/vstart merge for lane-level correctness, or unsupported configurations are rejected by decode.
  - Positive Tests (expected to PASS):
    - For unmasked, vstart=0, full-vl operations: all active lanes receive computed EML results.
    - For the restricted initial bring-up: decode rejects masked, non-zero vstart, and partial-vl configurations with a clear `inst_encoding_correct=0`.
  - Negative Tests (expected to FAIL):
    - EML results do NOT show stale `vd` data in lanes that should be written.
    - A masked VEML instruction (vm=0) with deferred mask support does NOT silently produce incorrect lane results.

- AC-6: An end-to-end cocotb test exercises the VEML instruction from ELF load through result comparison.
  - Positive Tests (expected to PASS):
    - A compiled ELF containing a VEML instruction (encoded via `.insn` assembly) loads into the simulator, executes, and produces FP32 results within tolerance of a NumPy `exp(x) - ln(y)` golden reference.
    - The test is registered in `RVV_ARITHMETIC_TESTCASES` and runnable via `bazel test //tests/cocotb:rvv_arithmetic_cocotb_test`.
  - Negative Tests (expected to FAIL):
    - An ELF with an illegally-encoded VEML instruction (wrong SEW) is rejected by the hardware and the test detects the rejection (e.g., trap, hang, or incorrect result).

- AC-7: The Bazel build passes with EMLUnit included, and no duplicate module definitions occur.
  - Positive Tests (expected to PASS):
    - `bazel build //hdl/verilog/rvv/design:rvv_backend_alu_unit_eml` succeeds.
    - The Verilator-based cocotb simulation compiles without duplicate `EMLUnit` or `FP32Multiplier` definition errors.

## Path Boundaries

### Upper Bound (Maximum Acceptable Scope)

The implementation includes: VEML decode for OPIVV with SEW=32, LMUL=1/2/4/8, unmasked, vstart=0, supported; EML ALU wrapper gated on `funct6==VEML && funct3==OPIVV`; `w_valid=1` for all active lanes with mask/tail/vstart merge applied in the EML result path; `pop_rs` correctly asserted at uop acceptance time; an end-to-end cocotb test using `.insn`-encoded VEML with a NumPy golden reference and tolerance derived from the hardware approximation; stress tests covering back-to-back EML dispatch, mixed EML+standard ALU traffic, and trap-flush mid-EML execution; and the Chisel `RvvAluOp` enum updated with VEML to enable the S1 front-end path.

### Lower Bound (Minimum Acceptable Scope)

The implementation includes: VEML decode for OPIVV with SEW=32, LMUL=1 only, unmasked, vstart=0; EML ALU wrapper gated on funct6+funct3; `w_valid=1` asserted for results (merge skipped for LMUL=1 unmasked vstart=0 which is identity); `pop_rs` correctly routed at acceptance time; one cocotb test with a single `.insn`-encoded VEML instruction verifying FP32 results against NumPy within a documented tolerance; decode rejects all unsupported configurations (masked, non-SEW32, non-zero vstart, LMUL>1) with `inst_encoding_correct=0`. Chisel S1 decode changes are deferred; the test path that bypasses the Chisel front-end is valid because the Verilog backend decode is independent of Chisel for the compressed-instruction format.

### Allowed Choices

- Can use: Raw `.insn` RISC-V assembly to encode VEML in test ELFs (no compiler intrinsic needed).
- Can use: Direct `bazel build //hdl/chisel/src/coralnpu:rvv_core_mini_verification_axi_cc_library_emit_verilog` for Verilog re-emission if Chisel changes are needed.
- Can use: `coralnpu_v2_binary` Bazel rule (not `template_rule`) for the EML test ELF since no intrinsic-based template exists.
- Can use: The existing `filelist.f` at the project root as the Verilog source manifest.
- Cannot use: `__riscv_veml_*` compiler intrinsics (do not exist). All EML instructions must be emitted via inline assembly `.insn` directive or standalone `.S` files.
- Cannot use: The existing `rvv_arithmetic_template.cc` directly for EML (it assumes `__riscv_v{op}_vv_{suffix}` intrinsics).
- Encoding choice is fixed: funct6=`6'b000_001`, funct3=OPIVV. This follows the precedent in `rvv_backend.svh` line 189 and the de2 decode routing at `rvv_backend_decode_unit_ari_de2.sv`.

## Feasibility Hints and Suggestions

> **Note**: This section is for reference and understanding only. These are conceptual suggestions, not prescriptive requirements.

### Conceptual Approach

**Milestone 1: Decode Integration (5 insertions in 2 files)**

In `rvv_backend_decode_unit_ari.sv`, add `VEML` to 4 case blocks under OPIVV only:
1. EMUL computation block — add `VEML,` after `VADD,` in the OPIVV case (shares the `csr_lmul`-based EMUL computation for EMUL1/2/4/8)
2. EEW computation block — add `VEML,` after `VADD,` in the `valid_opi` EEW case (SEW=32 mapping; add a SEW guard to reject SEW8/16 for VEML specifically)
3. check_special block — add `VEML,` after `VADD,` with `check_vd_overlap_v0`
4. SEW legality guard — add a new check: `assign check_sew_eml = (inst_funct6 == VEML) ? (csr_sew == SEW32) : 1'b1;` and AND it into `check_common`

In `rvv_backend_decode_unit_ari_de2.sv`, add `VEML` to:
5. uop_class block — add `VEML,` after `VADD,` in the OPIVV group setting `uop_class[i] = XVV`

**Milestone 2: ALU Safety Hardening (4 fixes in 2 files)**

In `rvv_backend_alu_unit_eml.sv`:
- Fix-1: Replace `wire is_eml_op = 1'b1;` with `wire is_eml_op = (alu_uop.uop_funct6 == VEML) && (alu_uop.uop_funct3 == OPIVV);`
- Fix-2: Replace `assign result.w_valid = 1'b0;` with `assign result.w_valid = 1'b1;`
- Fix-3 (minimum viable): For LMUL=1 unmasked vstart=0, the mask/tail/vstart merge is mathematically identity (all lanes active, no tail, no vstart offset). Assert these conditions or add the merge logic. The simplest approach: add an assertion that `alu_uop.vm == 1'b1 && alu_uop.vstart == '0` at the wrapper input for initial bring-up.

In `rvv_backend_alu_unit.sv`:
- Fix-4 (pop_rs routing): In the non-EML result path of the top-level mux, add a case for EML acceptance: when `alu_uop_valid && is_eml_op_exported && !result_valid_eml`, assert `pop_rs = pop_rs_eml`. This requires exporting `is_eml_op` from the EML wrapper as an output port or recomputing the gate at the top level.

**Milestone 3: Cocotb End-to-End Test**

Write a C++ test file (`rvv_eml_test.cc`) that:
- Uses inline assembly with the `.insn r 0x57, 0x1, %[vd], %[vs1], %[vs2]` directive to encode VEML
- Loads FP32 test vectors via `__riscv_vle32_v_f32m1`, executes VEML, stores via `__riscv_vse32_v_f32m1`
- Tests a small set of hand-picked FP32 pairs with known expected values
- Add to `tests/cocotb/rvv/arithmetics/BUILD` as a `coralnpu_v2_binary` target
- Add Python test function in `rvv_arithmetic_cocotb_test.py` with NumPy golden `np.exp(x) - np.log(np.maximum(y, 1e-10))`
- Register in `RVV_ARITHMETIC_TESTCASES` in `tests/cocotb/BUILD`

**Milestone 4: Stress and Regression**

- Back-to-back EML test: two VEML instructions back-to-back, verify second waits for first to complete
- Mixed traffic test: interleave VEML with VADD/VFADD, verify no cross-contamination
- Trap-flush test: assert trap_flush_rvv mid-EML execution, verify clean reset and no stale state

### Relevant References

- `hdl/verilog/rvv/inc/rvv_backend.svh` — VEML funct6 definition (line 189), UOP_CLASS_e enum, PIPE_DATA_t struct, ALU_RS_t struct, EXE_UNIT_e enum
- `hdl/verilog/rvv/design/rvv_backend_decode_unit_ari.sv` — First-stage decode: EMUL computation (OPIVV ~line 137), EEW computation (valid_opi ~line 1750), check_special (~line 2560), `inst_encoding_correct` computation (~line 3040)
- `hdl/verilog/rvv/design/rvv_backend_decode_unit_ari_de2.sv` — Second-stage decode: uop_exe_unit routing (line 239), uop_class (line 489)
- `hdl/verilog/rvv/design/rvv_backend_alu_unit_eml.sv` — EML ALU wrapper: `is_eml_op` (line 91), state machine, latency counter, `w_valid` (line 169)
- `hdl/verilog/rvv/design/rvv_backend_alu_unit.sv` — ALU top-level: EML instantiation (lines 101-112), result mux (lines 218-286), pop_rs routing
- `hdl/verilog/rvv/design/rvv_backend_alu_unit_execution_p1.sv` — P1 pipeline stage: mask/tail/vstart merge (lines 645-662), w_valid logic (line 1630)
- `hdl/verilog/rvv/design/EMLUnit.sv` — EML datapath: FP32Multiplier, FP32Adder, ExpApprox, LnApprox
- `tests/cocotb/rvv/arithmetics/BUILD` — Existing cocotb test BUILD patterns
- `tests/cocotb/rvv_arithmetic_cocotb_test.py` — Python cocotb test runner with NumPy reference comparison
- `tests/cocotb/BUILD` — `RVV_ARITHMETIC_TESTCASES` list (line 298)
- `hdl/chisel/src/coralnpu/rvv/RvvAlu.scala` — Chisel RvvAluOp enum (no VEML entry currently; needs update for S1 front-end path)
- `hdl/chisel/src/coralnpu/rvv/RvvDecode.scala` — Chisel S1 decode (no VEML entry; needed for Chisel-generated compressed-instruction path)

## Dependencies and Sequence

### Milestones

1. Milestone 1: Decode Integration
   - Phase A: Add VEML to EMUL, EEW, check_special, and SEW-legality-guard blocks in `rvv_backend_decode_unit_ari.sv` (4 insertions, OPIVV-only)
   - Phase B: Add VEML to uop_class block in `rvv_backend_decode_unit_ari_de2.sv` (1 insertion)
   - Phase C: Verify via RTL simulation that `inst_encoding_correct` asserts for legal VEML encodings and de-asserts for illegal ones (wrong SEW, wrong funct3)

2. Milestone 2: ALU Safety Hardening
   - Phase A: Gate `is_eml_op` on funct6+funct3 in `rvv_backend_alu_unit_eml.sv`
   - Phase B: Set `w_valid=1` for EML results
   - Phase C: Route `pop_rs_eml` at EML acceptance time in `rvv_backend_alu_unit.sv` top-level mux
   - Phase D: Add mask/tail/vstart assertion or merge logic for initial bring-up

3. Milestone 3: End-to-End Cocotb Test
   - Phase A: Write C++ test with inline `.insn`-encoded VEML instruction
   - Phase B: Add BUILD target and register in `RVV_ARITHMETIC_TESTCASES`
   - Phase C: Add Python cocotb test function with NumPy golden comparison
   - Phase D: Run `bazel test` and verify pass

4. Milestone 4: Stress and Regression Validation
   - Phase A: Back-to-back EML dispatch test
   - Phase B: Mixed VEML + standard ALU traffic test
   - Phase C: Trap-flush mid-EML execution test

Milestone 1 must complete before Milestone 2 (decode must be correct before ALU fixes can be validated). Milestone 2 must complete before Milestone 3 (ALU fixes are needed for cocotb test to pass). Milestone 4 depends on Milestone 3 (stress tests build on the cocotb infrastructure).

## Task Breakdown

Each task must include exactly one routing tag:
- `coding`: implemented by Claude
- `analyze`: executed via Codex (`/humanize:ask-codex`)

| Task ID | Description | Target AC | Tag (`coding`/`analyze`) | Depends On |
|---------|-------------|-----------|----------------------------|------------|
| task1 | Add VEML to EMUL block under OPIVV in decode_unit_ari.sv | AC-1 | coding | - |
| task2 | Add VEML to EEW block under valid_opi in decode_unit_ari.sv with SEW32 guard | AC-1 | coding | task1 |
| task3 | Add VEML to check_special block under OPIVV in decode_unit_ari.sv | AC-1 | coding | task1 |
| task4 | Add VEML to uop_class block under valid_opi in decode_unit_ari_de2.sv | AC-1 | coding | task1 |
| task5 | Gate is_eml_op on funct6+funct3 in rvv_backend_alu_unit_eml.sv | AC-2 | coding | task4 |
| task6 | Fix w_valid to 1 and route pop_rs_eml at acceptance time | AC-3, AC-4 | coding | task5 |
| task7 | Add mask/tail/vstart guard or merge logic in EML result path | AC-5 | coding | task5 |
| task8 | Analyze Chisel S1 decode gap and determine if Chisel changes block cocotb test path | AC-1 | analyze | task1 |
| task9 | Write cocotb EML test ELF (C++ with inline .insn assembly) | AC-6 | coding | task6 |
| task10 | Add Python cocotb test function with NumPy golden model | AC-6 | coding | task9 |
| task11 | Register EML test in BUILD and RVV_ARITHMETIC_TESTCASES | AC-6, AC-7 | coding | task10 |
| task12 | Write back-to-back EML dispatch stress test | AC-4 | coding | task11 |
| task13 | Write mixed EML + standard ALU traffic test | AC-3 | coding | task11 |
| task14 | Analyze EML golden tolerance from hardware LUT approximations | AC-6 | analyze | task10 |

## Claude-Codex Deliberation

### Agreements
- The decode is the real blocker: VEML is defined in `rvv_backend.svh` and routed in de2, but the first-stage arithmetic decode does not recognize it. This is a surgical fix, not architectural redesign.
- The EML ALU wrapper has three defects that must be fixed: `is_eml_op = 1'b1` (no gating), `w_valid = 1'b0` (suppressed writeback), and `pop_rs_eml` dropped at acceptance time (potential RS deadlock).
- Raw `.insn` assembly is the correct first test mechanism since no `__riscv_veml_*` compiler intrinsic exists.
- Back-to-back, mixed ALU, and flush stress tests are necessary validation steps.
- The `uop_class` gap in de2 is a real blocker independent of the first-stage decode — without it, source operand classification defaults to `XXX`.
- VEML must be scoped to OPIVV only for initial bring-up; OPIVX/OPIVI variants should not be legalized unless explicitly part of the ISA specification.

### Resolved Disagreements
- OPIVV-only vs OPIVI/OPIVX inclusion: Claude initially proposed 8 insertions across all OPI variants matching VADD's pattern. Codex argued for OPIVV-only since the EML wrapper always consumes `vs1_data` (vector source). Resolution: scope to OPIVV-only. The 3 OPIVX/OPIVI insertions are dropped from the plan. Rationale: the EML wrapper's per-lane instantiation requires both operands to be vector registers; scalar/immediate forms would need a different datapath.
- `w_valid = 1` completeness: Codex correctly noted that `w_valid=1` alone is insufficient without mask/tail/vstart merge. Resolution: for the initial LMUL=1/unmasked/vstart=0 bring-up scope, the merge is mathematically identity. An assertion guards this contract. Full merge logic is deferred to upper bound scope.
- `pop_rs` fix placement: Claude identified the risk but omitted it from initial fixes list. Codex required it as a convergence blocker. Resolution: Fix-4 added explicitly — export `is_eml_op` from the wrapper or recompute the gate at the top-level mux to assert `pop_rs = pop_rs_eml` at EML acceptance time.
- Mask/tail/vstart handling: Claude proposed documenting the limitation. Codex required enforcement in decode. Resolution: decode actively rejects unsupported configurations (SEW≠32, masked, vstart≠0, LMUL>1) with `inst_encoding_correct=0`, and the EML wrapper asserts supported conditions at its input.

### Convergence Status
- Final Status: `converged`

One convergence round was sufficient. All REQUIRED_CHANGES from the second Codex review were incorporated into the plan. The remaining items in UNRESOLVED are genuine user-facing design decisions that require explicit human input.

## Pending User Decisions

- DEC-1: ISA encoding scope — Should VEML support only OPIVV (vector-vector), or also OPIVX (vector-scalar) and OPIVI (vector-immediate) variants?
  - Claude Position: OPIVV-only for initial bring-up. The EML wrapper's per-lane EMLUnit instantiation expects `vs1_data` (vector register). Scalar/immediate forms would require a different datapath or a splat mechanism.
  - Codex Position: OPIVV-only. Legalizing scalar/immediate forms without the corresponding datapath support would create incorrect behavior.
  - Tradeoff Summary: OPIVV-only is simpler, safer, and matches the existing wrapper implementation. OPIVX/OPIVI variants could be added later if the ISA specification requires them.
  - Decision Status: `PENDING`

- DEC-2: RVV compliance scope — Should VEML support full RVV semantics (mask, tail agnostic/undisturbed, vstart≠0, multi-LMUL), or should the initial implementation be restricted to unmasked SEW32 LMUL1 vstart=0?
  - Claude Position: Restricted initial scope (unmasked, SEW32, LMUL1, vstart=0) enforced by decode rejection of unsupported configurations. This is the lower bound. Full RVV semantics can be added incrementally.
  - Codex Position: Agrees with restricted initial scope, but emphasizes that unsupported configurations must be rejected in decode, not silently produce wrong results.
  - Tradeoff Summary: Restricted scope enables rapid functional bring-up and avoids the complexity of mask/tail/vstart merge logic in the EML bypass path. Full compliance requires either integrating EML into the standard p1 merge path (upper bound) or replicating the merge logic in the EML wrapper.
  - Decision Status: `PENDING`

- DEC-3: Golden model tolerance — What numerical error tolerance is acceptable for the EML hardware approximation vs a double-precision NumPy reference?
  - Claude Position: Tolerance should be derived from the EMLUnit LUT-based approximation characteristics (ExpApprox uses lookup tables, LnApprox uses linear interpolation). Empirical measurement from RTL simulation should establish the ULP bound, likely 1-2 ULP for LUT-based methods. Document the measured tolerance in the test.
  - Codex Position: Agrees that tolerance cannot be assumed from exact float32 math. Must be empirically measured from the hardware implementation.
  - Tradeoff Summary: Setting tolerance too tight causes false test failures; too loose masks real bugs. Empirical measurement from the actual hardware pipeline is the gold standard. The test should log the maximum observed error and use it as the acceptance threshold with a small margin.
  - Decision Status: `PENDING`

## Implementation Notes

### Code Style Requirements
- Implementation code and comments must NOT contain plan-specific terminology such as "AC-", "Milestone", "Step", "Phase", or similar workflow markers
- These terms are for plan documentation only, not for the resulting codebase
- Use descriptive, domain-appropriate naming in code instead--- Original Design Draft Start ---

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

--- Original Design Draft End ---
