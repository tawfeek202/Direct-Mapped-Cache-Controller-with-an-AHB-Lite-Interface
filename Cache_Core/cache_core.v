module cache_core (
    input clk,
    input rst_n,

    // Request path — from CPU-Side Slave FSM
    input [21:0] core_addr_tag,
    input [ 5:0] core_addr_index,
    input [ 1:0] core_word_offset,
    input        core_req_valid,
    input        core_we,
    input [31:0] core_wdata,

    // Response path — to CPU-Side Slave FSM
    output        core_hit,
    output [31:0] core_rdata,

    // Fill path — from Memory-Side Master FSM
    input [ 5:0] fill_index,
    input [21:0] fill_tag,
    input        fill_word_en,
    input [ 1:0] fill_word_sel,
    input [31:0] fill_word_data,
    input        fill_commit
);

  // Internal wires connecting the three sub-blocks
  wire [21:0] stored_tag;
  wire        stored_valid;
  wire        we_gated;

  // Block 1: Tag Array + Valid Bits
  tag_valid_array u_tag_valid (
      .clk        (clk),
      .rst_n      (rst_n),
      .rd_index   (core_addr_index),
      .tag_out    (stored_tag),
      .valid_out  (stored_valid),
      .fill_index (fill_index),
      .fill_tag   (fill_tag),
      .fill_commit(fill_commit)
  );

  // Block 2: Comparator
  comparator u_comparator (
      .addr_tag  (core_addr_tag),
      .stored_tag(stored_tag),
      .valid     (stored_valid),
      .req_valid (core_req_valid),
      .hit       (core_hit)
  );

  // Write-hit enable: gated by this module's own hit result, not trusted from the FSM alone
  assign we_gated = core_we && core_hit;

  // Block 3: Data Array + Line Buffer
  data_line_array u_data_line (
      .clk           (clk),
      .rst_n         (rst_n),
      .rd_index      (core_addr_index),
      .word_offset   (core_word_offset),
      .rdata         (core_rdata),
      .we            (we_gated),
      .wr_index      (core_addr_index),
      .wr_word_offset(core_word_offset),
      .wdata         (core_wdata),
      .fill_word_en  (fill_word_en),
      .fill_word_sel (fill_word_sel),
      .fill_word_data(fill_word_data),
      .fill_index    (fill_index),
      .fill_commit   (fill_commit)
  );

endmodule
