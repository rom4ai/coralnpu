`ifndef HDL_VERILOG_RVV_DESIGN_RVV_SVH
`include "rvv_backend.svh"
`endif

module tb_rvv_backend_pe_wrapper;

  logic [15:0] src0;
  logic        src0_is_signed;
  logic [15:0] src1;
  logic        src1_is_signed;
  logic [15:0] res;
  RVVPEMode_e  pe_mode;

  integer      vector_fd;
  integer      vector_count;
  integer      status;
  integer      mode_int;
  integer      src0_signed_int;
  integer      src1_signed_int;
  logic [15:0] expected;
  string       vector_file;
  string       vector_line;

  rvv_backend_pe_wrapper dut (
    .pe_mode        (pe_mode),
    .src0           (src0),
    .src0_is_signed (src0_is_signed),
    .src1           (src1),
    .src1_is_signed (src1_is_signed),
    .res            (res)
  );

  initial begin
    src0 = '0;
    src1 = '0;
    src0_is_signed = 1'b0;
    src1_is_signed = 1'b0;
    pe_mode = RVV_PE_MODE_MXINT8;
    vector_count = 0;

    if (!$value$plusargs("VECTOR_FILE=%s", vector_file)) begin
      $fatal(1, "Missing +VECTOR_FILE=<path> plusarg");
    end

    vector_fd = $fopen(vector_file, "r");
    if (vector_fd == 0) begin
      $fatal(1, "Failed to open vector file %s", vector_file);
    end

    while (!$feof(vector_fd)) begin
      vector_line = "";
      status = $fgets(vector_line, vector_fd);
      if (status == 0) begin
        continue;
      end

      if ((vector_line.len() == 0) || (vector_line.substr(0, 0) == "#")) begin
        continue;
      end

      status = $sscanf(vector_line, "%d %h %d %h %d %h",
                       mode_int, src0, src0_signed_int, src1, src1_signed_int, expected);
      if (status != 6) begin
        $fatal(1, "Malformed vector line: %s", vector_line);
      end

      pe_mode = RVVPEMode_e'(mode_int);
      src0_is_signed = src0_signed_int[0];
      src1_is_signed = src1_signed_int[0];
      #1;

      if (res !== expected) begin
        $display("FAIL idx=%0d mode=%0d src0=0x%04h src0_signed=%0d src1=0x%04h src1_signed=%0d got=0x%04h exp=0x%04h",
                 vector_count, mode_int, src0, src0_is_signed, src1, src1_is_signed, res, expected);
        $fatal(1);
      end

      vector_count += 1;
    end

    $fclose(vector_fd);

    if (vector_count == 0) begin
      $fatal(1, "No vectors were loaded from %s", vector_file);
    end

    $display("PASS tb_rvv_backend_pe_wrapper vectors=%0d", vector_count);
    $finish;
  end

endmodule
