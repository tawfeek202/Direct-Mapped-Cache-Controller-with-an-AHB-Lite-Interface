`timescale 1ns / 1ps

module tb_full_chain;

  reg            HCLK;
  reg            HRESETn;

  // CPU-master-driven AHB-Lite slave port into cpu_side_slave_fsm
  reg     [31:0] HADDR;
  reg     [ 1:0] HTRANS;
  reg            HWRITE;
  reg     [ 2:0] HSIZE;
  reg     [ 2:0] HBURST;
  reg     [31:0] HWDATA;
  wire           HREADY;
  wire    [31:0] HRDATA;
  wire    [ 1:0] HRESP;

  // cpu_side_slave_fsm <-> cache_core
  wire    [21:0] core_addr_tag;
  wire    [ 5:0] core_addr_index;
  wire    [ 1:0] core_word_offset;
  wire           core_req_valid;
  wire           core_we;
  wire    [31:0] core_wdata;
  wire           core_hit;
  wire    [31:0] core_rdata;

  // cpu_side_slave_fsm <-> mem_side_master_fsm
  wire           miss_req;
  wire    [31:0] miss_addr;
  wire           miss_is_write;
  wire    [31:0] miss_wdata;
  wire           mem_op_done;

  // mem_side_master_fsm <-> cache_core (fill bus)
  wire    [ 5:0] fill_index;
  wire    [21:0] fill_tag;
  wire           fill_word_en;
  wire    [ 1:0] fill_word_sel;
  wire    [31:0] fill_word_data;
  wire           fill_commit;

  // mem_side_master_fsm <-> ahb_mem_model
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
  integer        fill_commit_count;
  reg            monitor_fill_commit;

  localparam TR_IDLE = 2'b00;
  localparam TR_NONSEQ = 2'b10;

  // ---- DUTs -------------------------------------------------------

  cpu_side_slave_fsm dut_cpu (
      .HCLK            (HCLK),
      .HRESETn         (HRESETn),
      .HADDR           (HADDR),
      .HTRANS          (HTRANS),
      .HWRITE          (HWRITE),
      .HSIZE           (HSIZE),
      .HBURST          (HBURST),
      .HWDATA          (HWDATA),
      .HREADY          (HREADY),
      .HRDATA          (HRDATA),
      .HRESP           (HRESP),
      .core_addr_tag   (core_addr_tag),
      .core_addr_index (core_addr_index),
      .core_word_offset(core_word_offset),
      .core_req_valid  (core_req_valid),
      .core_we         (core_we),
      .core_wdata      (core_wdata),
      .core_hit        (core_hit),
      .core_rdata      (core_rdata),
      .miss_req        (miss_req),
      .miss_addr       (miss_addr),
      .miss_is_write   (miss_is_write),
      .miss_wdata      (miss_wdata),
      .mem_op_done     (mem_op_done)
  );

  cache_core dut_core (
      .clk             (HCLK),
      .rst_n           (HRESETn),
      .core_addr_tag   (core_addr_tag),
      .core_addr_index (core_addr_index),
      .core_word_offset(core_word_offset),
      .core_req_valid  (core_req_valid),
      .core_we         (core_we),
      .core_wdata      (core_wdata),
      .core_hit        (core_hit),
      .core_rdata      (core_rdata),
      .fill_index      (fill_index),
      .fill_tag        (fill_tag),
      .fill_word_en    (fill_word_en),
      .fill_word_sel   (fill_word_sel),
      .fill_word_data  (fill_word_data),
      .fill_commit     (fill_commit)
  );

  mem_side_master_fsm dut_mem_fsm (
      .HCLK          (HCLK),
      .HRESETn       (HRESETn),
      .miss_req      (miss_req),
      .miss_addr     (miss_addr),
      .miss_is_write (miss_is_write),
      .miss_wdata    (miss_wdata),
      .HREADY        (mHREADY),
      .HRDATA        (mHRDATA),
      .HRESP         (mHRESP),
      .mem_op_done   (mem_op_done),
      .fill_index    (fill_index),
      .fill_tag      (fill_tag),
      .fill_word_en  (fill_word_en),
      .fill_word_sel (fill_word_sel),
      .fill_word_data(fill_word_data),
      .fill_commit   (fill_commit),
      .HADDR         (mHADDR),
      .HTRANS        (mHTRANS),
      .HWRITE        (mHWRITE),
      .HSIZE         (mHSIZE),
      .HBURST        (mHBURST),
      .HWDATA        (mHWDATA)
  );

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

  // Trace fill_commit pulses and count them while monitor_fill_commit is
  // active, to directly check for spurious re-triggered fills caused by
  // miss_req staying asserted after mem_op_done.
  always @(posedge HCLK) begin
    if (fill_commit) begin
      $display("[FILL t=%0t] fill_commit=1 index=%0d tag=%0h", $time, fill_index, fill_tag);
      if (monitor_fill_commit) fill_commit_count = fill_commit_count + 1;
    end
  end

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

  // CPU-master-style single transfer: drive address/control, hold until
  // HREADY=1, then release. This models a real CPU that keeps its
  // request signals stable while HREADY=0 (the correct AHB-Lite master
  // behavior), which will show us whether the FSMs work under realistic
  // conditions, not just under a testbench that changes HADDR every cycle.
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
      // Hold address/control stable (real AHB master behavior) until HREADY=1
      guard = 0;
      while (HREADY !== 1'b1 && guard < 200) begin
        @(posedge HCLK);
        #1;
        guard = guard + 1;
      end
      // Capture data at the point HREADY=1 completes the transfer
      rdata_out = HRDATA;
      @(posedge HCLK);
      #1;
      // Return bus to IDLE between transfers
      HTRANS = TR_IDLE;
      @(posedge HCLK);
      #1;
    end
  endtask

  reg [31:0] rdata;

  initial begin
    errors = 0;
    checks = 0;
    fill_commit_count = 0;
    monitor_fill_commit = 0;

    $display("==== Full-chain integration testbench start ====");
    $dumpfile("full_chain_tb.vcd");
    $dumpvars(0, tb_full_chain);

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

    // -----------------------------------------------------------------
    // Test 1: Cold read-miss at address 0x40 (line-aligned).
    // Memory model returns mem[16]=CCCC0010 for this address.
    // -----------------------------------------------------------------
    $display("\n-- Test 1: cold read at addr=0x40 (expect miss then correct data) --");
    ahb_transfer(32'h40, 1'b0, 32'h0, rdata);
    check_eq("T1: read data after miss-fill", rdata, 32'hCCCC_0010);

    // -----------------------------------------------------------------
    // Test 2: Immediately re-read the SAME address. Should now be a
    // fast hit with no stall.
    // -----------------------------------------------------------------
    $display("\n-- Test 2: re-read same address (expect fast hit) --");
    ahb_transfer(32'h40, 1'b0, 32'h0, rdata);
    check_eq("T2: read data on hit matches", rdata, 32'hCCCC_0010);

    // -----------------------------------------------------------------
    // Test 3: Write-hit to the same line, then read back.
    // -----------------------------------------------------------------
    $display("\n-- Test 3: write-hit then read-back --");
    ahb_transfer(32'h40, 1'b1, 32'hDEAD_BEEF, rdata);
    ahb_transfer(32'h40, 1'b0, 32'h0, rdata);
    check_eq("T3: read-back after write-hit", rdata, 32'hDEAD_BEEF);

    // -----------------------------------------------------------------
    // Test 4: Confirm the write-through actually reached memory (not
    // just the cache) by checking the memory model's array directly.
    // -----------------------------------------------------------------
    $display("\n-- Test 4: write-through reached backing memory --");
    check_eq("T4: memory array updated by write-through", dut_mem.mem[32'h40>>2], 32'hDEAD_BEEF);

    // -----------------------------------------------------------------
    // Test 5: A second, different address (different line) -- read
    // it, confirm correct data, and confirm the FIRST line is
    // untouched (index independence at full-chain level).
    // -----------------------------------------------------------------
    $display("\n-- Test 5: second independent line at addr=0x80 --");
    ahb_transfer(32'h80, 1'b0, 32'h0, rdata);
    check_eq("T5: second line reads correct data", rdata, 32'hCCCC_0020);

    ahb_transfer(32'h40, 1'b0, 32'h0, rdata);
    check_eq("T5: first line still holds written value", rdata, 32'hDEAD_BEEF);

    // -----------------------------------------------------------------
    // Test 6: Immediately issue a THIRD transfer right after a completed
    // one, checking whether the lingering miss_req behavior (flagged
    // during code review) causes a spurious extra miss-service cycle.
    // We check this by confirming the FSM returns to STATE_IDLE cleanly
    // and a subsequent read at a brand new address behaves correctly
    // and doesn't hang or double-service.
    // -----------------------------------------------------------------
    $display("\n-- Test 6: back-to-back transfer immediately after completion --");
    ahb_transfer(32'hC0, 1'b0, 32'h0, rdata);
    check_eq("T6: third line reads correct data", rdata, 32'hCCCC_0030);
    check_bit("T6: cpu FSM back in IDLE (HREADY=1 with no pending req)", HREADY, 1'b1);

    // -----------------------------------------------------------------
    // Test 7: miss_req level-sensitivity hazard check.
    // Concern from design review: mem_side_master_fsm's IDLE state uses
    // "if (miss_req)" (level, not edge). cpu_side_slave_fsm asserts
    // miss_req for the ENTIRE duration of STATE_MISS_WAIT/STATE_WRITE_WAIT,
    // not as a single pulse. If, on the exact cycle mem_op_done fires,
    // the memory-side FSM has already returned to IDLE while miss_req is
    // still high, it could spuriously start a SECOND fill of the same
    // line with no new CPU request. We check this directly by watching
    // fill_commit pulse count during ONE single CPU transfer -- it must
    // fire EXACTLY once, not twice.
    // -----------------------------------------------------------------
    $display("\n-- Test 7: miss_req level-sensitivity / spurious re-trigger check --");
    fill_commit_count   = 0;
    monitor_fill_commit = 1;
    ahb_transfer(32'h140, 1'b0, 32'h0, rdata);
    // Give a few extra idle cycles after the transfer completes, in case
    // a spurious second fill is triggered with some delay.
    repeat (10) begin
      @(posedge HCLK);
      #1;
    end
    monitor_fill_commit = 0;
    check_eq("T7: read data correct on new line 0x140", rdata, 32'hCCCC_0050);
    check_eq("T7: fill_commit pulsed EXACTLY once (no spurious re-trigger)", fill_commit_count,
             32'd1);

    // -----------------------------------------------------------------
    // Test 8: Address-latching hazard check.
    // Concern from design review: cpu_side_slave_fsm derives
    // core_addr_tag/core_addr_index combinationally from LIVE HADDR
    // (not a latched register), and branches on live HWRITE in
    // STATE_COMPLETE. If HADDR changes while a miss is still being
    // serviced (which our ahb_transfer task normally prevents by
    // holding HADDR stable, mimicking a well-behaved non-pipelined
    // master), the in-flight miss could be corrupted.
    // Here we deliberately misbehave: change HADDR mid-miss-service to
    // see whether the fill lands at the WRONG index/tag as a result.
    // -----------------------------------------------------------------
    $display("\n-- Test 8: address-latching hazard (HADDR changed mid-miss) --");
    HADDR  = 32'h180;
    HTRANS = TR_NONSEQ;
    HWRITE = 1'b0;
    HSIZE  = 3'b010;
    HBURST = 3'b000;
    HWDATA = 32'h0;
    #1;
    @(posedge HCLK);
    #1;  // one cycle into the miss-service window
    // Now, mid-miss, change HADDR to a DIFFERENT line -- a real AHB
    // master would never do this (it must hold the address stable
    // until HREADY=1), so this test deliberately violates protocol to
    // see how the FSM responds to that violation, not to imply this is
    // expected/legal traffic.
    HADDR = 32'h1C0;
    #1;
    begin : wait_t8
      integer guard8;
      for (guard8 = 0; guard8 < 100; guard8 = guard8 + 1) begin
        if (HREADY) disable wait_t8;
        @(posedge HCLK);
        #1;
      end
    end
    rdata = HRDATA;
    @(posedge HCLK);
    #1;
    HTRANS = TR_IDLE;
    @(posedge HCLK);
    #1;
    $display("[INFO] T8: with HADDR changed mid-miss (0x180 -> 0x1C0), FSM returned data=%h",
             rdata);
    $display("[INFO] T8: this is a PROTOCOL VIOLATION by the master (address must be held");
    $display("[INFO] T8: stable until HREADY=1) -- documenting behavior, not asserting pass/fail,");
    $display(
        "[INFO] T8: since a well-behaved master (as used in all other tests) never does this.");

    // -----------------------------------------------------------------
    // Summary
    // -----------------------------------------------------------------
    $display("\n==== SUMMARY: %0d checks run, %0d failed ====", checks, errors);
    if (errors == 0) $display("==== ALL TESTS PASSED ====");
    else $display("==== %0d TEST(S) FAILED ====", errors);

    $finish;
  end

  // Safety timeout in case of a hang (e.g. the FSMs deadlock)
  initial begin
    #100000;
    $display(
        "\n[TIMEOUT] Simulation did not finish in time -- likely a hang/deadlock in the FSMs.");
    $display("==== SUMMARY: %0d checks run, %0d failed (plus TIMEOUT) ====", checks, errors + 1);
    $finish;
  end

endmodule
