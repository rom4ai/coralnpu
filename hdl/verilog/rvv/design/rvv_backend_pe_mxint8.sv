`ifndef HDL_VERILOG_RVV_DESIGN_RVV_SVH
`include "rvv_backend.svh"
`endif

module rvv_backend_pe_mxint8 (
  input  logic [`HWORD_WIDTH-1:0] src0,
  input  logic                    src0_is_signed,
  input  logic [`HWORD_WIDTH-1:0] src1,
  input  logic                    src1_is_signed,
  output logic [`HWORD_WIDTH-1:0] res
);

  logic [`HWORD_WIDTH-1:0] res_mxint8;

  rvv_backend_mul_unit_mul8 u_core (
    .res            (res_mxint8),
    .src0           (src0[`BYTE_WIDTH-1:0]),
    .src0_is_signed (src0_is_signed),
    .src1           (src1[`BYTE_WIDTH-1:0]),
    .src1_is_signed (src1_is_signed)
  );

  assign res = res_mxint8;

endmodule
