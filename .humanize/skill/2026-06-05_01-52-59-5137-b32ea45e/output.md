CORE_RISKS:
- The biggest assumption is that this is “only first-stage decode.” Current draft wiring suggests wider risk: `VEML` is added under integer `OPIVV`, while the EML wrapper comments describe `OPFVV`. The template choice must be resolved before any patch.
- The EML unit is not safely gated. As drafted, `rvv_backend_alu_unit_eml.sv` treats every incoming ALU uop as EML (`is_eml_op = 1'b1`), so normal ALU ops can be captured and later produce bogus writeback.
- Bypassing the normal ALU p1 path risks skipping mask/tail/vstart/vl merge behavior. The wrapper emits raw `eml_result` directly toward ROB, so inactive lanes, tail policy, and old `vd` preservation may be wrong.
- `w_valid` appears set to `0` in the EML result path, which may mean the ROB never writes the vector result.
- EML is FP32-only, but the VADD-style decode template would likely accept SEW8/16/32. If SEW8/16 are legal by decode, the 32-bit lane EML datapath will silently compute nonsense.
- Multi-cycle result arbitration is not a wire-through detail. Giving EML highest priority can block or reorder standard ALU results unless the existing ROB/result-ready contract is proven compatible.
- The 8-cycle latency assumption is underspecified. The wrapper is single-uop busy/serialized, not a fully pipelined one-uop-per-cycle EML pipe.

MISSING_REQUIREMENTS:
- Exact instruction class: `OPIVV` custom integer vector op or `OPFVV` floating vector op.
- Exact legality rules: SEW must be 32? LMUL constraints? `ZVE32F_ON` required? masked form allowed?
- FP behavior: NaN, Inf, subnormal, signed zero, negative/zero `vs1` for `ln`, overflow/underflow, rounding mode, and exception flags.
- Mask/tail/vstart semantics: agnostic vs undisturbed handling and restart behavior after traps.
- Register overlap rules for `vd`, `vs1`, `vs2`, and `v0`.
- Throughput expectation: serialized 8-cycle op, pipelined 8-cycle latency, or shared ALU-stalling custom op.
- Assembler/test encoding support for generating VEML programs.
- Golden model tolerance for approximate `exp` and `ln`.

TECHNICAL_GAPS:
- First-stage decode likely needs more than three case edits if VEML is OPFVV: valid class, EEW/EMUL, legality, FRM/FP checks, and possibly decode macros must align.
- Second-stage decode may need more than “route to ALU”; VEML must appear in source-valid, uop-class, ROB-push, operand-read, and EEW propagation logic, not only execution-unit selection.
- ALU wrapper must gate on `alu_uop.uop_funct6 == VEML` and correct `uop_funct3`.
- Existing ALU subunits still receive every uop. Need prove no standard unit asserts a conflicting result for VEML.
- Direct EML writeback should either reuse the existing p1 mask/tail machinery or reimplement equivalent behavior.
- Build integration is not just `exports_files`: `include "EMLUnit.sv"` must work under Bazel/Verilator include paths without duplicate module definitions.
- UVM/RVVI types and reference models likely do not know VEML, so co-sim will fail or ignore the custom op unless extended.

ALTERNATIVE_DIRECTIONS:
- Minimal decode only, but first add a strict ALU gate and a unit-level EML smoke test. Fastest, but still high risk for mask/tail/writeback bugs.
- Integrate EML as a proper FP/ALU subunit feeding existing p1/result merge logic. More work, lower semantic risk.
- Add a dedicated EML execution unit/reservation station with explicit busy/ready arbitration. Best architectural fit for multi-cycle behavior, but larger change.
- Test-first path: decode test plus ALU wrapper test before end-to-end cocotb. Slower start, much better at catching silent misrouting.
- Prototype-only path: legalize only unmasked SEW32 LMUL1 `vstart=0` initially. Narrow but defensible if the goal is bring-up rather than full ISA support.

QUESTIONS_FOR_USER:
- Is VEML encoded as `OPIVV` or `OPFVV`?
- Must VEML be full RVV-compliant, including mask/tail/vstart and FP exception behavior, or is this a prototype instruction?
- Should only SEW32 be legal?
- What numerical tolerance and special-case behavior should the EML approximation satisfy?
- Is serialized one-uop-at-a-time EML throughput acceptable?
- Should UVM/MPACT support be required before merging, or is cocotb sufficient for the first patch?

CANDIDATE_CRITERIA:
- VEML decodes only for the intended `funct3/funct6` pair and rejects unsupported SEW/LMUL/masked forms as specified.
- No non-VEML ALU instruction can be captured by EML.
- VEML writes back correct FP32 lane results for normal inputs against a golden model within agreed tolerance.
- Mask, tail, `vl`, `vstart`, and multi-uop LMUL behavior are either correctly supported or explicitly illegal.
- Back-to-back VEML and mixed VEML/non-VEML ALU traffic preserve ROB ordering and do not drop results under `result_ready` stalls.
- Bazel/Verilator build passes with no duplicate `EMLUnit` definitions.
- Cocotb includes at least one end-to-end VEML program; UVM/RVVI model coverage is added before claiming architectural completeness.
