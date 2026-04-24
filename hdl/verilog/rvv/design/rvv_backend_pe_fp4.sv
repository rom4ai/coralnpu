`ifndef HDL_VERILOG_RVV_DESIGN_RVV_SVH
`include "rvv_backend.svh"
`endif

module rvv_backend_pe_fp4 (
  input  logic [`HWORD_WIDTH-1:0] src0,
  input  logic [`HWORD_WIDTH-1:0] src1,
  output logic [`HWORD_WIDTH-1:0] res
);

  logic [3:0] res_fp4;

  rvv_backend_pe_fp_core #(
    .DATA_WIDTH(4),
    .EXP_WIDTH (2),
    .MAN_WIDTH (1),
    .EXP_BIAS  (1)
  ) u_core (
    .src0 (src0[3:0]),
    .src1 (src1[3:0]),
    .res  (res_fp4)
  );

  assign res = {{(`HWORD_WIDTH-4){1'b0}}, res_fp4};

endmodule
