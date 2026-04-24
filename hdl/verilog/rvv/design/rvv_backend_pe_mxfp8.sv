`ifndef HDL_VERILOG_RVV_DESIGN_RVV_SVH
`include "rvv_backend.svh"
`endif

module rvv_backend_pe_mxfp8 (
  input  logic [`HWORD_WIDTH-1:0] src0,
  input  logic [`HWORD_WIDTH-1:0] src1,
  output logic [`HWORD_WIDTH-1:0] res
);

  logic [7:0] res_mxfp8;

  rvv_backend_pe_fp_core #(
    .DATA_WIDTH(8),
    .EXP_WIDTH (4),
    .MAN_WIDTH (3),
    .EXP_BIAS  (7)
  ) u_core (
    .src0 (src0[7:0]),
    .src1 (src1[7:0]),
    .res  (res_mxfp8)
  );

  assign res = {{(`HWORD_WIDTH-8){1'b0}}, res_mxfp8};

endmodule
