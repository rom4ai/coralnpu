// EML Unit wrapper for RVV ALU pipeline.
// Instantiates EMLUnit per 32-bit word lane for element-wise math ops.
// EMLUnit has ~8-cycle internal pipeline, handled via latency counter.

`ifndef HDL_VERILOG_RVV_DESIGN_RVV_SVH
`include "rvv_backend.svh"
`endif
`ifndef ALU_DEFINE_SVH
`include "rvv_backend_alu.svh"
`endif

// EMLUnit datapath modules (FP32Multiplier, FP32Adder, ExpApprox, LnApprox, EMLUnit)
`ifndef EMLUNIT_SV
`include "EMLUnit.sv"
`endif

module rvv_backend_alu_unit_eml
(
  clk,
  rst_n,

  alu_uop_valid,
  alu_uop,
  pop_rs,

  result_valid,
  result,
  result_ready,

  trap_flush_rvv
);

// --- interface signals ---
  // global signal
  input   logic           clk;
  input   logic           rst_n;

  // ALU RS handshake signals
  input   logic           alu_uop_valid;
  input   ALU_RS_t        alu_uop;
  output  logic           pop_rs;

  // EML result to ROB
  output  logic           result_valid;
  output  PIPE_DATA_t     result;
  input   logic           result_ready;

  // trap-flush
  input   logic           trap_flush_rvv;

// --- internal signals ---
  // ALU_RS_t struct signals
  FUNCT6_u                                uop_funct6;
  logic   [`FUNCT3_WIDTH-1:0]             uop_funct3;
  logic   [`VLEN-1:0]                     v0_data;
  logic   [`VLEN-1:0]                     vs1_data;
  logic   [`VLEN-1:0]                     vs2_data;
  EEW_e                                   vs2_eew;

  // EML pipeline control
  // EMLUnit pipeline depth: ExpApprox(~8 stages) + LnApprox(~4 stages + 4 delay regs)
  // Measured worst-case: output valid 8 cycles after input
  localparam EML_LATENCY = 8;

  logic                                   busy;
  logic   [$clog2(EML_LATENCY+1)-1:0]     cycle_cnt;

  // captured uop state for final result assembly
  ALU_RS_t                                captured_uop;
  logic                                   captured_valid;

  // per-lane EML instances
  logic   [`VLENW-1:0][31:0]              eml_x;
  logic   [`VLENW-1:0][31:0]              eml_y;
  wire    [`VLENW-1:0][31:0]              eml_result;

  // for-loop
  genvar                                  i;

// --- code start ---
  // split ALU_RS_t struct
  assign  uop_funct6     = alu_uop.uop_funct6;
  assign  uop_funct3     = alu_uop.uop_funct3;
  assign  v0_data        = alu_uop.v0_data;
  assign  vs1_data       = alu_uop.vs1_data;
  assign  vs2_data       = alu_uop.vs2_data;
  assign  vs2_eew        = alu_uop.vs2_eew;

// --- opcode detection ---
  // EML operations: funct6=VEML (000_001), funct3=OPIVV (000)
  // Gate on encoding to prevent non-VEML uops from being captured
  wire is_eml_op = (alu_uop.uop_funct6 == VEML) && (alu_uop.uop_funct3 == OPIVV);

// --- state machine ---
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      busy          <= 1'b0;
      cycle_cnt     <= '0;
      captured_uop  <= '0;
      captured_valid <= 1'b0;
    end else if (trap_flush_rvv) begin
      busy          <= 1'b0;
      cycle_cnt     <= '0;
      captured_uop  <= '0;
      captured_valid <= 1'b0;
    end else begin
      if (!busy) begin
        // IDLE: accept new uop if it's an EML op
        if (alu_uop_valid && is_eml_op) begin
          busy          <= 1'b1;
          cycle_cnt     <= '0;
          captured_uop  <= alu_uop;
          captured_valid <= 1'b1;
        end else begin
          captured_valid <= 1'b0;
        end
      end else begin
        // BUSY: count pipeline cycles
        if (cycle_cnt < EML_LATENCY) begin
          cycle_cnt <= cycle_cnt + 1'b1;
        end
        // When result is sent to ROB, go back to IDLE
        if (cycle_cnt == EML_LATENCY && result_ready) begin
          busy          <= 1'b0;
          captured_valid <= 1'b0;
        end
      end
    end
  end

  // mask/tail/vstart guard: initial bring-up requires unmasked, vstart=0
  // Decode check_eml_legal already enforces these; assertions are for VCS only
  `ifndef VERILATOR
  `ifdef RVV_ASSERT__SVH
    `rvv_expect(~(alu_uop_valid && is_eml_op && !busy) || (alu_uop.vm == 1'b1))
    `rvv_expect(~(alu_uop_valid && is_eml_op && !busy) || (alu_uop.vstart == '0))
  `endif
  `endif

  // pop_rs: accept new uop when not busy
  assign pop_rs = !busy && alu_uop_valid && is_eml_op;

  // result_valid: asserted when pipeline completes and we have captured data
  assign result_valid = busy && (cycle_cnt == EML_LATENCY) && captured_valid;

// --- per-lane EMLUnit instantiation ---
  generate
    for (i = 0; i < `VLENW; i = i + 1) begin : EML_LANE
      // Map input operands: io_x = vs2 element, io_y = vs1 element
      // Use captured uop data during BUSY, live data during IDLE
      assign eml_x[i] = busy ? captured_uop.vs2_data[(i+1)*32-1:i*32] : vs2_data[(i+1)*32-1:i*32];
      assign eml_y[i] = busy ? captured_uop.vs1_data[(i+1)*32-1:i*32] : vs1_data[(i+1)*32-1:i*32];

      EMLUnit u_eml (
        .clock      (clk),
        .reset      (~rst_n),  // EMLUnit uses active-high reset
        .io_x       (eml_x[i]),
        .io_y       (eml_y[i]),
        .io_result  (eml_result[i])
      );
    end
  endgenerate

// --- submit result ---
  `ifdef TB_SUPPORT
    assign result.uop_pc          = captured_uop.uop_pc;
  `endif
    assign result.rob_entry       = captured_uop.rob_entry;
    assign result.opcode          = ADDSUB_VADD;
    assign result.uop_funct6      = captured_uop.uop_funct6;
    assign result.uop_funct3      = captured_uop.uop_funct3;
    assign result.is_addsub       = 1'b1;
    assign result.is_cmp          = captured_uop.is_cmp;
    assign result.vstart          = captured_uop.vstart;
    assign result.vl              = captured_uop.vl;
    assign result.vm              = captured_uop.vm;
    assign result.vxrm            = captured_uop.vxrm;
    assign result.vs2_eew         = captured_uop.vs2_eew;
    assign result.w_valid         = captured_uop.vm;  // unmasked: vm=1 per check_eml_legal
    assign result.src2_sgn        = '0;
    assign result.src1_sgn        = '0;
    assign result.last_uop_valid  = captured_uop.last_uop_valid;
    assign result.uop_index       = captured_uop.uop_index;
    assign result.w_data          = eml_result;
    assign result.vsat_cout.cout  = '0;
    assign result.v0_src2.v0      = captured_uop.v0_data;
    assign result.vd_src1.vd      = captured_uop.vd_data;

endmodule
