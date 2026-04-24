`ifndef HDL_VERILOG_RVV_DESIGN_RVV_SVH
`include "rvv_backend.svh"
`endif

module rvv_backend_pe_bf16 (
  input  logic [`HWORD_WIDTH-1:0] src0,
  input  logic [`HWORD_WIDTH-1:0] src1,
  output logic [`HWORD_WIDTH-1:0] res
);

  logic [`HWORD_WIDTH-1:0] res_bf16;

  rvv_backend_pe_fp_core #(
    .DATA_WIDTH(`HWORD_WIDTH),
    .EXP_WIDTH (8),
    .MAN_WIDTH (7),
    .EXP_BIAS  (127)
  ) u_core (
    .src0 (src0),
    .src1 (src1),
    .res  (res_bf16)
  );

  assign res = res_bf16;

endmodule
