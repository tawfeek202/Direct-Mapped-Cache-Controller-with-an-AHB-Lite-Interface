module data_line_array (
    input clk,
    input rst_n,

    // Read path (combinational)
    input  [ 5:0] rd_index,
    input  [ 1:0] word_offset,
    output [31:0] rdata,

    // Write-hit path (synchronous, single word)
    input        we,
    input [ 5:0] wr_index,
    input [ 1:0] wr_word_offset,
    input [31:0] wdata,

    // Fill path (synchronous, buffer then atomic commit)
    input        fill_word_en,
    input [ 1:0] fill_word_sel,
    input [31:0] fill_word_data,
    input [ 5:0] fill_index,
    input        fill_commit
);

  reg [127:0] data_array  [0:63];
  reg [127:0] line_buffer;

  // Job 1: combinational read
  assign rdata = data_array[rd_index][word_offset*32+:32];

  always @(posedge clk) begin
    // Job 2: write-hit — partial-word update, only if not also committing this cycle
    if (we) data_array[wr_index][wr_word_offset*32+:32] <= wdata;

    // Job 3a: accumulate incoming burst word into the staging buffer
    if (fill_word_en) line_buffer[fill_word_sel*32+:32] <= fill_word_data;

    // Job 3b: atomic commit of the whole assembled line
    if (fill_commit) data_array[fill_index] <= line_buffer;
  end

endmodule
