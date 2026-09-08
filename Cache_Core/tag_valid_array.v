module tag_valid_array (
    input clk,
    input rst_n,

    // Read (combinational)
    input  [ 5:0] rd_index,
    output [21:0] tag_out,
    output        valid_out,

    // Write (synchronous, on commit only)
    input [ 5:0] fill_index,
    input [21:0] fill_tag,
    input        fill_commit
);

  reg [21:0] tag_array  [0:63];
  reg        valid_array[0:63];

  // Combinational read
  assign tag_out   = tag_array[rd_index];
  assign valid_out = valid_array[rd_index];

  // Synchronous write, async reset on valid bits only
  integer i;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (i = 0; i < 64; i = i + 1) valid_array[i] <= 1'b0;
    end else if (fill_commit) begin
      tag_array[fill_index]   <= fill_tag;
      valid_array[fill_index] <= 1'b1;
    end
  end

endmodule
