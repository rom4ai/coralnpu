`ifndef HDL_VERILOG_RVV_DESIGN_RVV_SVH
`include "rvv_backend.svh"
`endif

module rvv_backend_pe_mxint4 (
  input  logic [`HWORD_WIDTH-1:0] src0,
  input  logic                    src0_is_signed,
  input  logic [`HWORD_WIDTH-1:0] src1,
  input  logic                    src1_is_signed,
  output logic [`HWORD_WIDTH-1:0] res
);

  logic [7:0] res_mxint4;

  rvv_backend_pe_int_core #(
    .DATA_WIDTH(4)
  ) u_core (
    .src0           (src0[3:0]),
    .src0_is_signed (src0_is_signed),
    .src1           (src1[3:0]),
    .src1_is_signed (src1_is_signed),
    .res            (res_mxint4)
  );

  assign res = {{(`HWORD_WIDTH-8){1'b0}}, res_mxint4};

endmodule
