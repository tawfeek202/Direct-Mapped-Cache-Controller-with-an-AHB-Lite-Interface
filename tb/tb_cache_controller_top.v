`timescale 1ns / 1ps
module tb_cache_controller_top;

  reg            HCLK;
  reg            HRESETn;

  // CPU-master-driven AHB-Lite slave port into cache_controller_top
  reg     [31:0] HADDR;
  reg     [ 1:0] HTRANS;
  reg            HWRITE;
  reg     [ 2:0] HSIZE;
  reg     [ 2:0] HBURST;
  reg     [31:0] HWDATA;
  wire           HREADY;
  wire    [31:0] HRDATA;
  wire    [ 1:0] HRESP;

  // cache_controller_top's exposed memory-side AHB master port
  wire    [31:0] mHADDR;
  wire    [ 1:0] mHTRANS;
  wire           mHWRITE;
  wire    [ 2:0] mHSIZE;
  wire    [ 2:0] mHBURST;
  wire    [31:0] mHWDATA;
  wire    [31:0] mHRDATA;
  wire           mHREADY;
  wire    [ 1:0] mHRESP;

  integer        errors;
  integer        checks;

  localparam TR_IDLE = 2'b00;
  localparam TR_NONSEQ = 2'b10;

  // ---- DUT: the new top-level module -----------------------------
  cache_controller_top dut_top (
      .HCLK   (HCLK),
      .HRESETn(HRESETn),

      .HADDR (HADDR),
      .HTRANS(HTRANS),
      .HWRITE(HWRITE),
      .HSIZE (HSIZE),
      .HBURST(HBURST),
      .HWDATA(HWDATA),
      .HREADY(HREADY),
      .HRDATA(HRDATA),
      .HRESP (HRESP),

      .mHADDR (mHADDR),
      .mHTRANS(mHTRANS),
      .mHWRITE(mHWRITE),
      .mHSIZE (mHSIZE),
      .mHBURST(mHBURST),
      .mHWDATA(mHWDATA),
      .mHRDATA(mHRDATA),
      .mHREADY(mHREADY),
      .mHRESP (mHRESP)
  );

  // ---- External backing memory (verification stand-in only) -----
  ahb_mem_model dut_mem (
      .HCLK   (HCLK),
      .HRESETn(HRESETn),
      .HADDR  (mHADDR),
      .HTRANS (mHTRANS),
      .HWRITE (mHWRITE),
      .HSIZE  (mHSIZE),
      .HWDATA (mHWDATA),
      .HRDATA (mHRDATA),
      .HREADY (mHREADY),
      .HRESP  (mHRESP)
  );

  initial HCLK = 0;
  always #5 HCLK = ~HCLK;

  task check_eq;
    input [8*80-1:0] name;
    input [31:0] got;
    input [31:0] exp;
    begin
      checks = checks + 1;
      if (got !== exp) begin
        errors = errors + 1;
        $display("[FAIL] %0s : got=0x%0h expected=0x%0h (time=%0t)", name, got, exp, $time);
      end else begin
        $display("[PASS] %0s : 0x%0h", name, got);
      end
    end
  endtask

  task check_bit;
    input [8*80-1:0] name;
    input got;
    input exp;
    begin
      checks = checks + 1;
      if (got !== exp) begin
        errors = errors + 1;
        $display("[FAIL] %0s : got=%0b expected=%0b (time=%0t)", name, got, exp, $time);
      end else begin
        $display("[PASS] %0s : %0b", name, got);
      end
    end
  endtask

  // Same well-behaved-master transfer task as tb_full_chain.v
  task ahb_transfer;
    input [31:0] addr;
    input write;
    input [31:0] wdata_in;
    output [31:0] rdata_out;
    integer guard;
    begin
      HADDR  = addr;
      HTRANS = TR_NONSEQ;
      HWRITE = write;
      HSIZE  = 3'b010;
      HBURST = 3'b000;
      HWDATA = wdata_in;
      #1;
      guard = 0;
      while (HREADY !== 1'b1 && guard < 200) begin
        @(posedge HCLK);
        #1;
        guard = guard + 1;
      end
      rdata_out = HRDATA;
      @(posedge HCLK);
      #1;
      HTRANS = TR_IDLE;
      @(posedge HCLK);
      #1;
    end
  endtask

  reg [31:0] rdata;

  initial begin
    errors = 0;
    checks = 0;

    $display("==== cache_controller_top wrapper testbench start ====");

    HRESETn = 0;
    HADDR   = 0;
    HTRANS  = TR_IDLE;
    HWRITE  = 0;
    HSIZE   = 3'b010;
    HBURST  = 3'b000;
    HWDATA  = 0;
    #1;
    @(posedge HCLK);
    @(posedge HCLK);
    #1;
    HRESETn = 1;
    @(posedge HCLK);
    #1;

    $display("\n-- Test 1: cold read at addr=0x40 (expect miss then correct data) --");
    ahb_transfer(32'h40, 1'b0, 32'h0, rdata);
    check_eq("T1: read data after miss-fill", rdata, 32'hCCCC_0010);

    $display("\n-- Test 2: re-read same address (expect fast hit) --");
    ahb_transfer(32'h40, 1'b0, 32'h0, rdata);
    check_eq("T2: read data on hit matches", rdata, 32'hCCCC_0010);

    $display("\n-- Test 3: write-hit then read-back --");
    ahb_transfer(32'h40, 1'b1, 32'hDEAD_BEEF, rdata);
    ahb_transfer(32'h40, 1'b0, 32'h0, rdata);
    check_eq("T3: read-back after write-hit", rdata, 32'hDEAD_BEEF);

    $display("\n-- Test 4: write-through reached backing memory --");
    check_eq("T4: memory array updated by write-through", dut_mem.mem[32'h40>>2], 32'hDEAD_BEEF);

    $display("\n-- Test 5: second independent line at addr=0x80 --");
    ahb_transfer(32'h80, 1'b0, 32'h0, rdata);
    check_eq("T5: second line reads correct data", rdata, 32'hCCCC_0020);
    ahb_transfer(32'h40, 1'b0, 32'h0, rdata);
    check_eq("T5: first line still holds written value", rdata, 32'hDEAD_BEEF);

    $display("\n-- Test 6: back-to-back transfer immediately after completion --");
    ahb_transfer(32'hC0, 1'b0, 32'h0, rdata);
    check_eq("T6: third line reads correct data", rdata, 32'hCCCC_0030);
    check_bit("T6: back in IDLE (HREADY=1 with no pending req)", HREADY, 1'b1);

    $display("\n==== SUMMARY: %0d checks run, %0d failed ====", checks, errors);
    if (errors == 0) $display("==== ALL TESTS PASSED ====");
    else $display("==== %0d TEST(S) FAILED ====", errors);

    $stop;
  end

  initial begin
    #100000;
    $display("\n[TIMEOUT] Simulation did not finish in time.");
    $stop;
  end

endmodule
