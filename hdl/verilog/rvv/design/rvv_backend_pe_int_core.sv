`ifndef HDL_VERILOG_RVV_DESIGN_RVV_SVH
`include "rvv_backend.svh"
`endif

module rvv_backend_pe_int_core #(
  parameter DATA_WIDTH = `BYTE_WIDTH
) (
  input  logic [DATA_WIDTH-1:0]   src0,
  input  logic                    src0_is_signed,
  input  logic [DATA_WIDTH-1:0]   src1,
  input  logic                    src1_is_signed,
  output logic [2*DATA_WIDTH-1:0] res
);

  logic                     src0_sgn;
  logic                     src1_sgn;
  logic [2*DATA_WIDTH-1:0]  src0_ext;
  logic [2*DATA_WIDTH-1:0]  src1_ext;

  assign src0_sgn = src0_is_signed & src0[DATA_WIDTH-1];
  assign src1_sgn = src1_is_signed & src1[DATA_WIDTH-1];
  assign src0_ext = {{DATA_WIDTH{src0_sgn}}, src0};
  assign src1_ext = {{DATA_WIDTH{src1_sgn}}, src1};
  assign res      = src0_ext * src1_ext;

endmodule
