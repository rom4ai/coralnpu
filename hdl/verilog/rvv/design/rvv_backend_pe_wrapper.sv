`ifndef HDL_VERILOG_RVV_DESIGN_RVV_SVH
`include "rvv_backend.svh"
`endif

module rvv_backend_pe_wrapper (
  input  RVVPEMode_e              pe_mode,
  input  logic [`HWORD_WIDTH-1:0] src0,
  input  logic                    src0_is_signed,
  input  logic [`HWORD_WIDTH-1:0] src1,
  input  logic                    src1_is_signed,
  output logic [`HWORD_WIDTH-1:0] res
);

  logic [`HWORD_WIDTH-1:0] mxint4_res;
  logic [`HWORD_WIDTH-1:0] mxint6_res;
  logic [`HWORD_WIDTH-1:0] mxint8_res;
  logic [`HWORD_WIDTH-1:0] mxfp4_res;
  logic [`HWORD_WIDTH-1:0] mxfp6_res;
  logic [`HWORD_WIDTH-1:0] mxfp8_res;
  logic [`HWORD_WIDTH-1:0] fp4_res;
  logic [`HWORD_WIDTH-1:0] fp8_res;
  logic [`HWORD_WIDTH-1:0] fp16_res;
  logic [`HWORD_WIDTH-1:0] bf16_res;

  rvv_backend_pe_mxint4 u_mxint4 (
    .src0           (src0),
    .src0_is_signed (src0_is_signed),
    .src1           (src1),
    .src1_is_signed (src1_is_signed),
    .res            (mxint4_res)
  );

  rvv_backend_pe_mxint6 u_mxint6 (
    .src0           (src0),
    .src0_is_signed (src0_is_signed),
    .src1           (src1),
    .src1_is_signed (src1_is_signed),
    .res            (mxint6_res)
  );

  rvv_backend_pe_mxint8 u_mxint8 (
    .src0           (src0),
    .src0_is_signed (src0_is_signed),
    .src1           (src1),
    .src1_is_signed (src1_is_signed),
    .res            (mxint8_res)
  );

  rvv_backend_pe_mxfp4 u_mxfp4 (
    .src0 (src0),
    .src1 (src1),
    .res  (mxfp4_res)
  );

  rvv_backend_pe_mxfp6 u_mxfp6 (
    .src0 (src0),
    .src1 (src1),
    .res  (mxfp6_res)
  );

  rvv_backend_pe_mxfp8 u_mxfp8 (
    .src0 (src0),
    .src1 (src1),
    .res  (mxfp8_res)
  );

  rvv_backend_pe_fp4 u_fp4 (
    .src0 (src0),
    .src1 (src1),
    .res  (fp4_res)
  );

  rvv_backend_pe_fp8 u_fp8 (
    .src0 (src0),
    .src1 (src1),
    .res  (fp8_res)
  );

  rvv_backend_pe_fp16 u_fp16 (
    .src0 (src0),
    .src1 (src1),
    .res  (fp16_res)
  );

  rvv_backend_pe_bf16 u_bf16 (
    .src0 (src0),
    .src1 (src1),
    .res  (bf16_res)
  );

  always_comb begin
    case (pe_mode)
      RVV_PE_MODE_MXINT4: res = mxint4_res;
      RVV_PE_MODE_MXINT6: res = mxint6_res;
      RVV_PE_MODE_MXINT8: res = mxint8_res;
      RVV_PE_MODE_MXFP4:  res = mxfp4_res;
      RVV_PE_MODE_MXFP6:  res = mxfp6_res;
      RVV_PE_MODE_MXFP8:  res = mxfp8_res;
      RVV_PE_MODE_FP4:    res = fp4_res;
      RVV_PE_MODE_FP8:    res = fp8_res;
      RVV_PE_MODE_FP16:   res = fp16_res;
      RVV_PE_MODE_BF16:   res = bf16_res;
      default:            res = '0;
    endcase
  end

endmodule
