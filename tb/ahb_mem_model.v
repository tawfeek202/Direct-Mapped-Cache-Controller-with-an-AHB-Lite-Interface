// Simple AHB-Lite slave memory model. Fixed 1-cycle latency (HREADY always 1).
// ahb_mem_model.v is a verification
// stand-in only and is NOT part of the project just simulating a real memory used in the testbench;
module ahb_mem_model (
    input             HCLK,
    input             HRESETn,
    input      [31:0] HADDR,
    input      [ 1:0] HTRANS,
    input             HWRITE,
    input      [ 2:0] HSIZE,
    input      [31:0] HWDATA,
    output reg [31:0] HRDATA,
    output            HREADY,
    output     [ 1:0] HRESP
);

  localparam HTRANS_NONSEQ = 2'b10;
  localparam HTRANS_SEQ = 2'b11;

  reg [31:0] mem                                                         [0:255];

  reg        pending_valid;
  reg [31:0] pending_addr;
  reg        pending_write;
  reg [31:0] pending_wdata;  // latched alongside the address -- must not
                             // read HWDATA "live" at commit time

  assign HREADY = 1'b1;
  assign HRESP  = 2'b00;

  integer i;
  initial begin
    for (i = 0; i < 256; i = i + 1) mem[i] = 32'hCCCC_0000 + i;
  end

  always @(posedge HCLK or negedge HRESETn) begin
    if (!HRESETn) begin
      pending_valid <= 1'b0;
      pending_addr  <= 32'd0;
      pending_write <= 1'b0;
      pending_wdata <= 32'd0;
      HRDATA        <= 32'd0;
    end else begin
      if (pending_valid) begin
        if (pending_write) mem[pending_addr[9:2]] <= pending_wdata;
        else HRDATA <= mem[pending_addr[9:2]];
      end

      if (HTRANS == HTRANS_NONSEQ || HTRANS == HTRANS_SEQ) begin
        pending_valid <= 1'b1;
        pending_addr  <= HADDR;
        pending_write <= HWRITE;
        pending_wdata <= HWDATA;
      end else begin
        pending_valid <= 1'b0;
      end
    end
  end

endmodule
