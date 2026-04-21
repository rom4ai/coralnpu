`ifndef HDL_VERILOG_RVV_DESIGN_RVV_SVH
`include "rvv_backend.svh"
`endif

module rvv_backend_nonlinear_sfu(
  clk,
  rst_n,
  // Input signals
  operand_i,
  vs1_i,
  rnd_mode_i,
  tag_i,
  // Input Handshake
  in_valid_i,
  in_ready_o,
  flush_i,
  // Output signals
  result_o,
  tbl_status_o,
  tag_o,
  // Output handshake
  out_valid_o,
  out_ready_i
);
  parameter type TagType = logic;

  typedef enum logic [1:0] {
    SFU_SIGMOID = 2'b00,
    SFU_TANH    = 2'b01,
    SFU_ILLEGAL = 2'b10
  } sfu_op_e;

  localparam logic [`WORD_WIDTH-1:0] CANO_NAN = 32'h7fc0_0000;
  localparam logic [`WORD_WIDTH-1:0] FP_ZERO  = 32'h0000_0000;
  localparam logic [`WORD_WIDTH-1:0] FP_ONE   = 32'h3f80_0000;
  localparam logic [`WORD_WIDTH-1:0] FP_NEG_ONE = 32'hbf80_0000;

  localparam logic [30:0] FP_MAG_0P5 = 31'h3f00_0000;
  localparam logic [30:0] FP_MAG_1P0 = 31'h3f80_0000;
  localparam logic [30:0] FP_MAG_1P5 = 31'h3fc0_0000;
  localparam logic [30:0] FP_MAG_2P0 = 31'h4000_0000;
  localparam logic [30:0] FP_MAG_3P0 = 31'h4040_0000;
  localparam logic [30:0] FP_MAG_4P0 = 31'h4080_0000;

  localparam logic [`WORD_WIDTH-1:0] SIGMOID_0P047 = 32'h3d42_41a2;
  localparam logic [`WORD_WIDTH-1:0] SIGMOID_0P119 = 32'h3df4_20a9;
  localparam logic [`WORD_WIDTH-1:0] SIGMOID_0P182 = 32'h3e3a_cdc1;
  localparam logic [`WORD_WIDTH-1:0] SIGMOID_0P269 = 32'h3e89_b2b1;
  localparam logic [`WORD_WIDTH-1:0] SIGMOID_0P378 = 32'h3ec1_4d03;
  localparam logic [`WORD_WIDTH-1:0] SIGMOID_0P500 = 32'h3f00_0000;
  localparam logic [`WORD_WIDTH-1:0] SIGMOID_0P622 = 32'h3f1f_597f;
  localparam logic [`WORD_WIDTH-1:0] SIGMOID_0P731 = 32'h3f3b_26a8;
  localparam logic [`WORD_WIDTH-1:0] SIGMOID_0P818 = 32'h3f51_4c90;
  localparam logic [`WORD_WIDTH-1:0] SIGMOID_0P881 = 32'h3f61_7beb;
  localparam logic [`WORD_WIDTH-1:0] SIGMOID_0P953 = 32'h3f73_dbe6;

  localparam logic [`WORD_WIDTH-1:0] TANH_0P462 = 32'h3eec_9a9f;
  localparam logic [`WORD_WIDTH-1:0] TANH_0P762 = 32'h3f42_f7d6;
  localparam logic [`WORD_WIDTH-1:0] TANH_0P905 = 32'h3f67_b7cc;
  localparam logic [`WORD_WIDTH-1:0] TANH_0P964 = 32'h3f76_ca83;
  localparam logic [`WORD_WIDTH-1:0] TANH_0P995 = 32'h3f7e_bbe8;

  input logic                     clk;
  input logic                     rst_n;
  input logic [`WORD_WIDTH-1:0]   operand_i;
  input logic [`REGFILE_INDEX_WIDTH-1:0] vs1_i;
  input RVFRM                     rnd_mode_i;
  input TagType                   tag_i;
  input logic                     in_valid_i;
  output logic                    in_ready_o;
  input logic                     flush_i;
  output logic [`WORD_WIDTH-1:0]  result_o;
  output RVFEXP_t                 tbl_status_o;
  output TagType                  tag_o;
  output logic                    out_valid_o;
  input logic                     out_ready_i;

  logic                stall_pip;
  logic                invld;
  sfu_op_e             dec_op;

  logic                pip1_vld;
  logic                pip2_vld;
  logic                pip3_vld;
  logic                pip4_vld;
  sfu_op_e             pip1_op;
  sfu_op_e             pip2_op;
  sfu_op_e             pip3_op;
  logic [`WORD_WIDTH-1:0] pip1_operand;
  logic [`WORD_WIDTH-1:0] pip2_operand;
  logic [`WORD_WIDTH-1:0] pip3_operand;
  logic [`WORD_WIDTH-1:0] pip4_result;
  RVFEXP_t             pip4_status;
  TagType              pip1_tag;
  TagType              pip2_tag;
  TagType              pip3_tag;
  TagType              pip4_tag;

  logic _unused_rnd_mode;
  assign _unused_rnd_mode = ^rnd_mode_i;

  function automatic sfu_op_e decode_op(
    input logic [`REGFILE_INDEX_WIDTH-1:0] opcode
  );
    begin
      unique case (opcode)
        VFSIGMOID: decode_op = SFU_SIGMOID;
        VFTANH:    decode_op = SFU_TANH;
        default:   decode_op = SFU_ILLEGAL;
      endcase
    end
  endfunction

  function automatic logic fp_is_nan(input logic [`WORD_WIDTH-1:0] operand);
    begin
      fp_is_nan = (operand[30:23] == 8'hff) && (operand[22:0] != '0);
    end
  endfunction

  function automatic logic fp_is_inf(input logic [`WORD_WIDTH-1:0] operand);
    begin
      fp_is_inf = (operand[30:23] == 8'hff) && (operand[22:0] == '0);
    end
  endfunction

  function automatic logic [`WORD_WIDTH-1:0] with_sign(
    input logic sign,
    input logic [`WORD_WIDTH-1:0] magnitude_word
  );
    begin
      with_sign = {sign, magnitude_word[30:0]};
    end
  endfunction

  function automatic logic [`WORD_WIDTH-1:0] approx_sigmoid(
    input logic sign,
    input logic [30:0] magnitude
  );
    begin
      if (sign) begin
        if (magnitude >= FP_MAG_4P0)       approx_sigmoid = FP_ZERO;
        else if (magnitude >= FP_MAG_3P0)  approx_sigmoid = SIGMOID_0P047;
        else if (magnitude >= FP_MAG_2P0)  approx_sigmoid = SIGMOID_0P119;
        else if (magnitude >= FP_MAG_1P5)  approx_sigmoid = SIGMOID_0P182;
        else if (magnitude >= FP_MAG_1P0)  approx_sigmoid = SIGMOID_0P269;
        else if (magnitude >= FP_MAG_0P5)  approx_sigmoid = SIGMOID_0P378;
        else                               approx_sigmoid = SIGMOID_0P500;
      end else begin
        if (magnitude >= FP_MAG_4P0)       approx_sigmoid = FP_ONE;
        else if (magnitude >= FP_MAG_3P0)  approx_sigmoid = SIGMOID_0P953;
        else if (magnitude >= FP_MAG_2P0)  approx_sigmoid = SIGMOID_0P881;
        else if (magnitude >= FP_MAG_1P5)  approx_sigmoid = SIGMOID_0P818;
        else if (magnitude >= FP_MAG_1P0)  approx_sigmoid = SIGMOID_0P731;
        else if (magnitude >= FP_MAG_0P5)  approx_sigmoid = SIGMOID_0P622;
        else                               approx_sigmoid = SIGMOID_0P500;
      end
    end
  endfunction

  function automatic logic [`WORD_WIDTH-1:0] approx_tanh(
    input logic sign,
    input logic [30:0] magnitude,
    input logic [`WORD_WIDTH-1:0] operand
  );
    begin
      if (magnitude < FP_MAG_0P5)          approx_tanh = operand;
      else if (magnitude < FP_MAG_1P0)     approx_tanh = with_sign(sign, TANH_0P462);
      else if (magnitude < FP_MAG_1P5)     approx_tanh = with_sign(sign, TANH_0P762);
      else if (magnitude < FP_MAG_2P0)     approx_tanh = with_sign(sign, TANH_0P905);
      else if (magnitude < FP_MAG_3P0)     approx_tanh = with_sign(sign, TANH_0P964);
      else if (magnitude < FP_MAG_4P0)     approx_tanh = with_sign(sign, TANH_0P995);
      else if (sign)                       approx_tanh = FP_NEG_ONE;
      else                                 approx_tanh = FP_ONE;
    end
  endfunction

  function automatic logic [`WORD_WIDTH-1:0] compute_result(
    input logic [`WORD_WIDTH-1:0] operand,
    input sfu_op_e                op
  );
    logic sign;
    logic [30:0] magnitude;
    begin
      sign = operand[31];
      magnitude = operand[30:0];

      if (fp_is_nan(operand)) begin
        compute_result = CANO_NAN;
      end else begin
        unique case (op)
          SFU_SIGMOID: begin
            if (fp_is_inf(operand)) compute_result = sign ? FP_ZERO : FP_ONE;
            else                    compute_result = approx_sigmoid(sign, magnitude);
          end
          SFU_TANH: begin
            if (fp_is_inf(operand)) compute_result = sign ? FP_NEG_ONE : FP_ONE;
            else                    compute_result = approx_tanh(sign, magnitude, operand);
          end
          default: compute_result = CANO_NAN;
        endcase
      end
    end
  endfunction

  assign dec_op = decode_op(vs1_i);
  assign stall_pip = out_valid_o & !out_ready_i;
  assign invld = in_valid_i & in_ready_o & !flush_i;
  assign in_ready_o = ~stall_pip;
  assign out_valid_o = pip4_vld;
  assign result_o = pip4_result;
  assign tbl_status_o = pip4_status;
  assign tag_o = pip4_tag;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      pip1_vld    <= 1'b0;
      pip2_vld    <= 1'b0;
      pip3_vld    <= 1'b0;
      pip4_vld    <= 1'b0;
      pip1_op     <= SFU_ILLEGAL;
      pip2_op     <= SFU_ILLEGAL;
      pip3_op     <= SFU_ILLEGAL;
      pip1_operand<= '0;
      pip2_operand<= '0;
      pip3_operand<= '0;
      pip4_result <= '0;
      pip4_status <= '0;
      pip1_tag    <= '0;
      pip2_tag    <= '0;
      pip3_tag    <= '0;
      pip4_tag    <= '0;
    end else if (flush_i) begin
      pip1_vld    <= 1'b0;
      pip2_vld    <= 1'b0;
      pip3_vld    <= 1'b0;
      pip4_vld    <= 1'b0;
    end else if (!stall_pip) begin
      pip4_vld     <= pip3_vld;
      pip4_result  <= compute_result(pip3_operand, pip3_op);
      pip4_status  <= '0;
      pip4_tag     <= pip3_tag;

      pip3_vld     <= pip2_vld;
      pip3_op      <= pip2_op;
      pip3_operand <= pip2_operand;
      pip3_tag     <= pip2_tag;

      pip2_vld     <= pip1_vld;
      pip2_op      <= pip1_op;
      pip2_operand <= pip1_operand;
      pip2_tag     <= pip1_tag;

      pip1_vld     <= invld;
      pip1_op      <= dec_op;
      pip1_operand <= operand_i;
      pip1_tag     <= tag_i;
    end
  end

endmodule
