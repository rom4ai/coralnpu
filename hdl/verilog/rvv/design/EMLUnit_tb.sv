// EMLUnit trap-flush unit testbench.
// Verifies the EML ALU wrapper correctly clears state on trap_flush_rvv
// mid-execution: busy=0, captured_valid=0, result_valid stays 0.
//
// Pattern follows Aligner_tb.sv self-checking unit testbench style.

`ifndef HDL_VERILOG_RVV_DESIGN_RVV_SVH
`include "rvv_backend.svh"
`endif
`ifndef ALU_DEFINE_SVH
`include "rvv_backend_alu.svh"
`endif

module EMLUnit_tb;
  reg         clk;
  reg         rst_n;

  // ALU interface signals
  reg                    alu_uop_valid;
  ALU_RS_t               alu_uop;
  wire                   pop_rs;

  wire                   result_valid;
  PIPE_DATA_t            result;
  reg                    result_ready;

  reg                    trap_flush_rvv;

  // DUT
  rvv_backend_alu_unit_eml u_dut (
    .clk              (clk),
    .rst_n            (rst_n),
    .alu_uop_valid    (alu_uop_valid),
    .alu_uop          (alu_uop),
    .pop_rs           (pop_rs),
    .result_valid     (result_valid),
    .result           (result),
    .result_ready     (result_ready),
    .trap_flush_rvv   (trap_flush_rvv)
  );

  // Clock: 10ns period
  always #5 clk = ~clk;

  integer errors;
  integer cycle;

  initial begin
    clk = 0;
    rst_n = 0;
    alu_uop_valid = 0;
    alu_uop = '0;
    result_ready = 1;
    trap_flush_rvv = 0;
    errors = 0;

    // Reset
    repeat (3) @(posedge clk);
    rst_n = 1;
    @(posedge clk);

    // --- Test 1: Normal VEML execution ---
    $display("Test 1: Normal VEML execution");
    alu_uop.uop_funct6 = VEML;
    alu_uop.uop_funct3 = OPIVV;
    alu_uop_valid = 1;
    @(posedge clk);
    // Check acceptance
    if (!pop_rs) begin
      $error("Test 1 FAIL: pop_rs not asserted at acceptance");
      errors = errors + 1;
    end
    alu_uop_valid = 0;

    // Wait for EML pipeline to complete (EML_LATENCY=8 cycles)
    for (cycle = 0; cycle < 10; cycle = cycle + 1) begin
      @(posedge clk);
      if (result_valid) begin
        $display("Test 1 PASS: result_valid at cycle %0d", cycle);
        $display("Test 1 w_valid=%0b", result.w_valid);
        if (result.w_valid !== 1'b1) begin
          $error("Test 1 FAIL: w_valid should be 1, got %0b", result.w_valid);
          errors = errors + 1;
        end
        cycle = 100;  // break out
      end
    end
    if (cycle != 100) begin
      $error("Test 1 FAIL: result_valid never asserted");
      errors = errors + 1;
    end

    // --- Test 2: Trap-flush mid-execution ---
    $display("Test 2: Trap-flush mid-execution");
    alu_uop.uop_funct6 = VEML;
    alu_uop.uop_funct3 = OPIVV;
    alu_uop_valid = 1;
    @(posedge clk);
    if (!pop_rs) begin
      $error("Test 2 FAIL: pop_rs not asserted at acceptance");
      errors = errors + 1;
    end
    alu_uop_valid = 0;

    // Wait 3 cycles, then assert trap_flush_rvv
    repeat (3) @(posedge clk);
    trap_flush_rvv = 1;
    @(posedge clk);
    trap_flush_rvv = 0;

    // Verify flush cleared state: result_valid should stay 0
    for (cycle = 0; cycle < 15; cycle = cycle + 1) begin
      @(posedge clk);
      if (result_valid) begin
        $error("Test 2 FAIL: result_valid asserted at cycle %0d after flush", cycle);
        errors = errors + 1;
      end
    end
    $display("Test 2 PASS: no stale result after trap-flush");

    // --- Test 3: Post-flush new VEML ---
    $display("Test 3: New VEML after flush");
    alu_uop.uop_funct6 = VEML;
    alu_uop.uop_funct3 = OPIVV;
    alu_uop_valid = 1;
    @(posedge clk);
    if (!pop_rs) begin
      $error("Test 3 FAIL: pop_rs not asserted after flush");
      errors = errors + 1;
    end
    alu_uop_valid = 0;

    for (cycle = 0; cycle < 10; cycle = cycle + 1) begin
      @(posedge clk);
      if (result_valid) begin
        $display("Test 3 PASS: result_valid at cycle %0d after flush", cycle);
        cycle = 100;
      end
    end
    if (cycle != 100) begin
      $error("Test 3 FAIL: no result_valid after post-flush VEML");
      errors = errors + 1;
    end

    // --- Test 4: is_eml_op gate rejects non-VEML uop ---
    $display("Test 4: is_eml_op gate rejects VADD");
    alu_uop.uop_funct6 = VADD;
    alu_uop.uop_funct3 = OPIVV;
    alu_uop_valid = 1;
    @(posedge clk);
    if (pop_rs) begin
      $error("Test 4 FAIL: pop_rs asserted for non-VEML uop (VADD)");
      errors = errors + 1;
    end else begin
      $display("Test 4 PASS: VADD correctly rejected by EML wrapper");
    end
    alu_uop_valid = 0;

    // --- Test 5: is_eml_op gate rejects VREDAND (same funct6, different funct3) ---
    $display("Test 5: is_eml_op gate rejects VREDAND (funct6=1, OPMVV)");
    alu_uop.uop_funct6 = VREDAND;  // 6'b000_001 same as VEML
    alu_uop.uop_funct3 = OPMVV;     // different funct3
    alu_uop_valid = 1;
    @(posedge clk);
    if (pop_rs) begin
      $error("Test 5 FAIL: pop_rs asserted for VREDAND (same funct6, different funct3)");
      errors = errors + 1;
    end else begin
      $display("Test 5 PASS: VREDAND correctly rejected by funct3 gate");
    end
    alu_uop_valid = 0;

    // --- Summary ---
    if (errors == 0)
      $display("ALL TESTS PASSED");
    else
      $display("%0d TEST(S) FAILED", errors);

    $finish;
  end

endmodule
