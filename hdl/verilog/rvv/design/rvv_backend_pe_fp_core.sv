`ifndef HDL_VERILOG_RVV_DESIGN_RVV_SVH
`include "rvv_backend.svh"
`endif

module rvv_backend_pe_fp_core #(
  parameter DATA_WIDTH = `HWORD_WIDTH,
  parameter EXP_WIDTH  = 5,
  parameter MAN_WIDTH  = 10,
  parameter EXP_BIAS   = 15
) (
  input  logic [DATA_WIDTH-1:0] src0,
  input  logic [DATA_WIDTH-1:0] src1,
  output logic [DATA_WIDTH-1:0] res
);

  localparam SIG_WIDTH  = MAN_WIDTH + 1;
  localparam PROD_WIDTH = 2 * SIG_WIDTH;
  localparam EXP_MAX    = (1 << EXP_WIDTH) - 1;

  logic                     sign0;
  logic                     sign1;
  logic                     result_sign;
  logic [EXP_WIDTH-1:0]     exp0;
  logic [EXP_WIDTH-1:0]     exp1;
  logic [EXP_WIDTH-1:0]     pack_exp_bits;
  logic [MAN_WIDTH-1:0]     frac0;
  logic [MAN_WIDTH-1:0]     frac1;
  logic [SIG_WIDTH-1:0]     sig0;
  logic [SIG_WIDTH-1:0]     sig1;
  logic [SIG_WIDTH-1:0]     norm_sig;
  logic [PROD_WIDTH-1:0]    prod_sig;
  logic                     zero0;
  logic                     zero1;
  logic                     special0;
  logic                     special1;
  integer                   exp0_eff;
  integer                   exp1_eff;
  integer                   norm_exp;
  integer                   pack_exp;

  // Baseline scalar floating multiply. RVV2-002 will add the final lane
  // packing and mode-selection semantics on top of this stable interface.
  always_comb begin
    sign0       = src0[DATA_WIDTH-1];
    sign1       = src1[DATA_WIDTH-1];
    result_sign = sign0 ^ sign1;
    exp0        = src0[MAN_WIDTH +: EXP_WIDTH];
    exp1        = src1[MAN_WIDTH +: EXP_WIDTH];
    frac0       = src0[0 +: MAN_WIDTH];
    frac1       = src1[0 +: MAN_WIDTH];
    zero0       = (exp0 == '0) && (frac0 == '0);
    zero1       = (exp1 == '0) && (frac1 == '0);
    special0    = (exp0 == {EXP_WIDTH{1'b1}});
    special1    = (exp1 == {EXP_WIDTH{1'b1}});
    sig0        = '0;
    sig1        = '0;
    norm_sig    = '0;
    prod_sig    = '0;
    exp0_eff    = 0;
    exp1_eff    = 0;
    norm_exp    = 0;
    pack_exp    = 0;
    pack_exp_bits = '0;
    res         = '0;

    if (zero0 || zero1) begin
      res = '0;
    end else if (special0 || special1) begin
      res = {result_sign, {EXP_WIDTH{1'b1}}, {MAN_WIDTH{1'b0}}};
    end else begin
      if (exp0 == '0) begin
        sig0     = {1'b0, frac0};
        exp0_eff = 1 - EXP_BIAS;
      end else begin
        sig0     = {1'b1, frac0};
        exp0_eff = int'(exp0) - EXP_BIAS;
      end

      if (exp1 == '0) begin
        sig1     = {1'b0, frac1};
        exp1_eff = 1 - EXP_BIAS;
      end else begin
        sig1     = {1'b1, frac1};
        exp1_eff = int'(exp1) - EXP_BIAS;
      end

      prod_sig = sig0 * sig1;
      if (prod_sig == '0) begin
        res = '0;
      end else begin
        if (prod_sig[PROD_WIDTH-1]) begin
          norm_sig = prod_sig[PROD_WIDTH-1 -: SIG_WIDTH];
          norm_exp = exp0_eff + exp1_eff + 1;
        end else begin
          norm_sig = prod_sig[PROD_WIDTH-2 -: SIG_WIDTH];
          norm_exp = exp0_eff + exp1_eff;
        end

        pack_exp      = norm_exp + EXP_BIAS;
        pack_exp_bits = pack_exp[EXP_WIDTH-1:0];

        if (pack_exp <= 0) begin
          res = '0;
        end else if (pack_exp >= EXP_MAX) begin
          res = {result_sign, {EXP_WIDTH{1'b1}}, {MAN_WIDTH{1'b0}}};
        end else begin
          res = {result_sign, pack_exp_bits, norm_sig[MAN_WIDTH-1:0]};
        end
      end
    end
  end

endmodule
