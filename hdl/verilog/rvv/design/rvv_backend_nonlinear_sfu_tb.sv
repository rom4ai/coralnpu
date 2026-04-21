`timescale 1ns / 1ps

`ifndef HDL_VERILOG_RVV_DESIGN_RVV_SVH
`include "rvv_backend.svh"
`endif

module rvv_backend_nonlinear_sfu_tb;

  logic clk;
  logic rst_n;
  logic in_valid;
  logic in_ready;
  logic flush_i;
  logic [`WORD_WIDTH-1:0] operand_i;
  logic [`REGFILE_INDEX_WIDTH-1:0] vs1_i;
  RVFRM rnd_mode_i;
  logic [3:0] tag_i;
  logic [`WORD_WIDTH-1:0] result_o;
  RVFEXP_t tbl_status_o;
  logic [3:0] tag_o;
  logic out_valid;
  logic out_ready;

  logic [`WORD_WIDTH-1:0] expected_result_q[$];
  logic [3:0] expected_tag_q[$];

  rvv_backend_nonlinear_sfu #(
    .TagType(logic [3:0])
  ) dut (
    .clk(clk),
    .rst_n(rst_n),
    .operand_i(operand_i),
    .vs1_i(vs1_i),
    .rnd_mode_i(rnd_mode_i),
    .tag_i(tag_i),
    .in_valid_i(in_valid),
    .in_ready_o(in_ready),
    .flush_i(flush_i),
    .result_o(result_o),
    .tbl_status_o(tbl_status_o),
    .tag_o(tag_o),
    .out_valid_o(out_valid),
    .out_ready_i(out_ready)
  );

  task automatic enqueue_case(
    input logic [`REGFILE_INDEX_WIDTH-1:0] opcode,
    input logic [`WORD_WIDTH-1:0] operand,
    input logic [`WORD_WIDTH-1:0] expected,
    input logic [3:0] tag
  );
    begin
      @(negedge clk);
      in_valid   <= 1'b1;
      vs1_i      <= opcode;
      operand_i  <= operand;
      tag_i      <= tag;
      wait (in_ready);
      expected_result_q.push_back(expected);
      expected_tag_q.push_back(tag);
      @(negedge clk);
      in_valid   <= 1'b0;
      operand_i  <= '0;
      vs1_i      <= '0;
      tag_i      <= '0;
    end
  endtask

  always #5 clk = ~clk;

  always @(posedge clk) begin
    if (rst_n && out_valid && out_ready) begin
      logic [`WORD_WIDTH-1:0] expected_result;
      logic [3:0] expected_tag;

      if (expected_result_q.size() == 0) begin
        $fatal(1, "Unexpected SFU output");
      end

      expected_result = expected_result_q.pop_front();
      expected_tag = expected_tag_q.pop_front();

      if (result_o !== expected_result) begin
        $fatal(1, "Result mismatch. got=%h expected=%h", result_o, expected_result);
      end

      if (tag_o !== expected_tag) begin
        $fatal(1, "Tag mismatch. got=%h expected=%h", tag_o, expected_tag);
      end

      if (tbl_status_o !== '0) begin
        $fatal(1, "Expected zero FP exception flags, got=%b", tbl_status_o);
      end
    end
  end

  initial begin
    clk        = 1'b0;
    rst_n      = 1'b0;
    in_valid   = 1'b0;
    flush_i    = 1'b0;
    operand_i  = '0;
    vs1_i      = '0;
    rnd_mode_i = FRNE;
    tag_i      = '0;
    out_ready  = 1'b1;

    repeat (3) @(posedge clk);
    rst_n = 1'b1;

    enqueue_case(VFSIGMOID, 32'h3e800000, 32'h3f000000, 4'h1); // +0.25 -> 0.5
    enqueue_case(VFSIGMOID, 32'h3f400000, 32'h3f1f597f, 4'h2); // +0.75 -> 0.622...
    enqueue_case(VFSIGMOID, 32'hbfa00000, 32'h3e89b2b1, 4'h3); // -1.25 -> 0.268...
    enqueue_case(VFSIGMOID, 32'h40600000, 32'h3f73dbe6, 4'h4); // +3.5  -> 0.952...
    enqueue_case(VFSIGMOID, 32'hc1000000, 32'h00000000, 4'h5); // -8.0  -> 0.0
    enqueue_case(VFTANH,    32'h3e800000, 32'h3e800000, 4'h6); // +0.25 -> identity
    enqueue_case(VFTANH,    32'hbf400000, 32'hbeec9a9f, 4'h7); // -0.75 -> -0.462...
    enqueue_case(VFTANH,    32'h3fa00000, 32'h3f42f7d6, 4'h8); // +1.25 -> 0.761...
    enqueue_case(VFTANH,    32'hbfe00000, 32'hbf67b7cc, 4'h9); // -1.75 -> -0.905...
    enqueue_case(VFTANH,    32'h40600000, 32'h3f7ebbe8, 4'ha); // +3.5  -> 0.995...
    enqueue_case(VFTANH,    32'hff800000, 32'hbf800000, 4'hb); // -inf  -> -1.0
    enqueue_case(VFSIGMOID, 32'h7fc00000, 32'h7fc00000, 4'hc); // NaN   -> canonical NaN

    wait (expected_result_q.size() == 0);
    repeat (5) @(posedge clk);
    $display("rvv_backend_nonlinear_sfu_tb: PASS");
    $finish;
  end

endmodule
