// EML ALU wrapper (rvv_backend_alu_unit_eml) unit testbench.
// Verifies: normal execution, trap-flush clearing, post-flush restart,
//           is_eml_op gate (funct6+funct3), funct3-collision regression.
// // Pattern follows Aligner_tb.sv / MultiFifo_tb.sv self-checking style.

`ifndef HDL_VERILOG_RVV_DESIGN_RVV_SVH
`include "rvv_backend.svh"
`endif
`ifndef ALU_DEFINE_SVH
`include "rvv_backend_alu.svh"
`endif

module EMLUnit_tb;
  reg         clk;
  reg         rst_n;
  reg         alu_uop_valid;
  ALU_RS_t    alu_uop;
  wire        pop_rs;
  wire        result_valid;
  PIPE_DATA_t result;
  reg         result_ready;
  reg         trap_flush_rvv;

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

  always #5 clk = ~clk;

  integer errors;
  integer wait_cycle;
  reg     seen;

  // Helper: send a VEML uop and check acceptance
  task send_veml_uop;
    begin
      alu_uop.uop_funct6 = VEML;
      alu_uop.uop_funct3 = OPIVV;
      alu_uop_valid = 1;
      @(posedge clk);
      alu_uop_valid = 0;
    end
  endtask

  // Helper: send a non-VEML uop with given funct6/funct3
  task send_uop(input [5:0] f6, input [2:0] f3);
    begin
      alu_uop.uop_funct6 = f6;
      alu_uop.uop_funct3 = f3;
      alu_uop_valid = 1;
      @(posedge clk);
      alu_uop_valid = 0;
    end
  endtask

  initial begin
    clk = 0;
    rst_n = 0;
    alu_uop_valid = 0;
    alu_uop = '0;
    result_ready = 1;
    trap_flush_rvv = 0;
    errors = 0;

    repeat (3) @(posedge clk);
    rst_n = 1;
    @(posedge clk);

    // --- Test 1: Normal VEML execution ---
    $display("Test 1: Normal VEML execution");
    send_veml_uop();
    if (!pop_rs) begin
      $error("Test 1 FAIL: pop_rs not asserted at acceptance");
      errors = errors + 1;
    end

    seen = 0;
    for (wait_cycle = 0; wait_cycle < 12; wait_cycle = wait_cycle + 1) begin
      @(posedge clk);
      if (result_valid && !seen) begin
        seen = 1;
        if (result.w_valid !== 1'b1) begin
          $error("Test 1 FAIL: w_valid should be 1, got %0b", result.w_valid);
          errors = errors + 1;
        end
        $display("Test 1 PASS: result_valid at wait_cycle %0d, w_valid=%0b",
                 wait_cycle, result.w_valid);
      end
    end
    if (!seen) begin
      $error("Test 1 FAIL: result_valid never asserted");
      errors = errors + 1;
    end

    // --- Test 2: Trap-flush mid-execution ---
    $display("Test 2: Trap-flush mid-execution");
    send_veml_uop();
    if (!pop_rs) begin
      $error("Test 2 FAIL: pop_rs not asserted at acceptance");
      errors = errors + 1;
    end

    // Wait 3 cycles into EML pipeline, then flush
    repeat (3) @(posedge clk);
    trap_flush_rvv = 1;
    @(posedge clk);
    trap_flush_rvv = 0;

    // Verify no stale result for 2*LATENCY cycles after flush
    seen = 0;
    for (wait_cycle = 0; wait_cycle < 20; wait_cycle = wait_cycle + 1) begin
      @(posedge clk);
      if (result_valid) begin
        seen = 1;
        $error("Test 2 FAIL: stale result_valid at wait_cycle %0d after flush",
               wait_cycle);
        errors = errors + 1;
      end
    end
    if (!seen)
      $display("Test 2 PASS: no stale result after trap-flush");

    // --- Test 3: Post-flush new VEML ---
    $display("Test 3: New VEML after flush");
    send_veml_uop();
    if (!pop_rs) begin
      $error("Test 3 FAIL: pop_rs not asserted after flush");
      errors = errors + 1;
    end

    seen = 0;
    for (wait_cycle = 0; wait_cycle < 12; wait_cycle = wait_cycle + 1) begin
      @(posedge clk);
      if (result_valid && !seen) begin
        seen = 1;
        $display("Test 3 PASS: result_valid after post-flush VEML");
      end
    end
    if (!seen) begin
      $error("Test 3 FAIL: no result_valid after post-flush VEML");
      errors = errors + 1;
    end

    // --- Test 4: is_eml_op gate rejects VADD ---
    $display("Test 4: is_eml_op gate rejects VADD");
    send_uop(VADD, OPIVV);
    if (pop_rs) begin
      $error("Test 4 FAIL: pop_rs asserted for non-VEML uop (VADD)");
      errors = errors + 1;
    end else
      $display("Test 4 PASS: VADD rejected");

    // --- Test 5: funct3-collision gate rejects VREDAND ---
    // VREDAND uses same funct6=000_001 as VEML but funct3=OPMVV
    $display("Test 5: funct3 gate rejects VREDAND (funct6=1, OPMVV)");
    send_uop(VREDAND, OPMVV);
    if (pop_rs) begin
      $error("Test 5 FAIL: pop_rs asserted for VREDAND (funct6 collision)");
      errors = errors + 1;
    end else
      $display("Test 5 PASS: VREDAND rejected by funct3 gate");

    // --- Summary ---
    if (errors == 0)
      $display("ALL TESTS PASSED");
    else
      $display("%0d TEST(S) FAILED", errors);

    $finish;
  end

endmodule
