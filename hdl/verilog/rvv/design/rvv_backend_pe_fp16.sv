`ifndef HDL_VERILOG_RVV_DESIGN_RVV_SVH
`include "rvv_backend.svh"
`endif

module rvv_backend_pe_fp16 (
  input  logic [`HWORD_WIDTH-1:0] src0,
  input  logic [`HWORD_WIDTH-1:0] src1,
  output logic [`HWORD_WIDTH-1:0] res
);

  logic [`HWORD_WIDTH-1:0] res_fp16;

  rvv_backend_pe_fp_core #(
    .DATA_WIDTH(`HWORD_WIDTH),
    .EXP_WIDTH (5),
    .MAN_WIDTH (10),
    .EXP_BIAS  (15)
  ) u_core (
    .src0 (src0),
    .src1 (src1),
    .res  (res_fp16)
  );

  assign res = res_fp16;

endmodule
