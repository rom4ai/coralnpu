`ifndef HDL_VERILOG_RVV_DESIGN_RVV_SVH
`include "rvv_backend.svh"
`endif

module rvv_backend_pe_mxfp6 (
  input  logic [`HWORD_WIDTH-1:0] src0,
  input  logic [`HWORD_WIDTH-1:0] src1,
  output logic [`HWORD_WIDTH-1:0] res
);

  logic [5:0] res_mxfp6;

  rvv_backend_pe_fp_core #(
    .DATA_WIDTH(6),
    .EXP_WIDTH (3),
    .MAN_WIDTH (2),
    .EXP_BIAS  (3)
  ) u_core (
    .src0 (src0[5:0]),
    .src1 (src1[5:0]),
    .res  (res_mxfp6)
  );

  assign res = {{(`HWORD_WIDTH-6){1'b0}}, res_mxfp6};

endmodule
