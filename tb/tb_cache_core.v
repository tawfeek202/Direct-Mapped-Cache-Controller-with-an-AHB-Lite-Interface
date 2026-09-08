`timescale 1ns / 1ps

module tb_cache_core;

  reg            clk;
  reg            rst_n;

  reg     [21:0] core_addr_tag;
  reg     [ 5:0] core_addr_index;
  reg     [ 1:0] core_word_offset;
  reg            core_req_valid;
  reg            core_we;
  reg     [31:0] core_wdata;
  wire           core_hit;
  wire    [31:0] core_rdata;

  reg     [ 5:0] fill_index;
  reg     [21:0] fill_tag;
  reg            fill_word_en;
  reg     [ 1:0] fill_word_sel;
  reg     [31:0] fill_word_data;
  reg            fill_commit;

  integer        errors;
  integer        checks;

  cache_core dut (
      .clk             (clk),
      .rst_n           (rst_n),
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

  // 100MHz clock
  initial clk = 0;
  always #5 clk = ~clk;

  task reset_dut;
    begin
      rst_n            = 0;
      core_addr_tag    = 0;
      core_addr_index  = 0;
      core_word_offset = 0;
      core_req_valid   = 0;
      core_we          = 0;
      core_wdata       = 0;
      fill_index       = 0;
      fill_tag         = 0;
      fill_word_en     = 0;
      fill_word_sel    = 0;
      fill_word_data   = 0;
      fill_commit      = 0;
      #1;
      @(posedge clk);
      @(posedge clk);
      #1;
      rst_n = 1;
      @(posedge clk);
      #1;
    end
  endtask

  // Holds the result of the most recent do_request call.
  reg        hit;
  reg [31:0] rdata;

  // Drive a read/write request combinationally, capture hit/rdata after settle.
  task do_request;
    input [21:0] tag;
    input [5:0] index;
    input [1:0] offset;
    input we;
    input [31:0] wdata_in;
    begin
      core_addr_tag    = tag;
      core_addr_index  = index;
      core_word_offset = offset;
      core_we          = we;
      core_wdata       = wdata_in;
      core_req_valid   = 1;
      #1;  // allow combinational hit/rdata to settle before sampling
      hit   = core_hit;
      rdata = core_rdata;
      @(posedge clk);
      #1;
      core_req_valid = 0;
      core_we        = 0;
      @(posedge clk);
      #1;
    end
  endtask

  task do_line_fill;
    input [5:0] index;
    input [21:0] tag;
    input [31:0] w0;
    input [31:0] w1;
    input [31:0] w2;
    input [31:0] w3;
    integer i;
    reg [31:0] word_i;
    begin
      for (i = 0; i < 4; i = i + 1) begin
        case (i)
          0: word_i = w0;
          1: word_i = w1;
          2: word_i = w2;
          default: word_i = w3;
        endcase
        fill_word_en   = 1;
        fill_word_sel  = i[1:0];
        fill_word_data = word_i;
        #1;
        @(posedge clk);
        #1;
      end
      fill_word_en = 0;
      #1;

      fill_index  = index;
      fill_tag    = tag;
      fill_commit = 1;
      #1;
      @(posedge clk);  // this edge performs the atomic commit into data_array
      #1;
      fill_commit = 0;
      @(posedge clk);
      #1;
    end
  endtask

  task check_eq;
    input [8*64-1:0] name;  // fixed-width byte string, Verilog has no `string` type
    input [31:0] got;
    input [31:0] exp;
    begin
      checks = checks + 1;
      if (got !== exp) begin
        errors = errors + 1;
        $display("[FAIL] %0s : got=0x%0h expected=0x%0h  (time=%0t)", name, got, exp, $time);
      end else begin
        $display("[PASS] %0s : 0x%0h", name, got);
      end
    end
  endtask

  task check_bit;
    input [8*64-1:0] name;
    input got;
    input exp;
    begin
      checks = checks + 1;
      if (got !== exp) begin
        errors = errors + 1;
        $display("[FAIL] %0s : got=%0b expected=%0b  (time=%0t)", name, got, exp, $time);
      end else begin
        $display("[PASS] %0s : %0b", name, got);
      end
    end
  endtask

  // ---- Test sequence --------------------------------------------------

  initial begin
    errors = 0;
    checks = 0;

    $display("==== cache_core testbench start ====");
    $dumpfile("cache_core_tb.vcd");
    $dumpvars(0, tb_cache_core);

    reset_dut;

    // -----------------------------------------------------------------
    // Test 1: Cold-start compulsory miss.
    // Deliberately use tag=0, index=0 -- the "all zeros" case that would
    // falsely hit if the valid-bit AND were missing from the comparator.
    // -----------------------------------------------------------------
    $display("\n-- Test 1: cold-start miss on tag=0, index=0 --");
    do_request(22'h0, 6'h0, 2'b00, 1'b0, 32'h0);
    check_bit("T1: cold-start must be a MISS", hit, 1'b0);

    // -----------------------------------------------------------------
    // Test 2: Fill line at index=0, tag=0x1, words = A0,A1,A2,A3
    // Then confirm all four word offsets now hit and return correct data.
    // -----------------------------------------------------------------
    $display("\n-- Test 2: fill index=0 then check all 4 words hit --");
    do_line_fill(6'h0, 22'h1, 32'hAAAA_0000, 32'hAAAA_1111, 32'hAAAA_2222, 32'hAAAA_3333);

    do_request(22'h1, 6'h0, 2'b00, 1'b0, 32'h0);
    check_bit("T2: word0 hit", hit, 1'b1);
    check_eq("T2: word0 data", rdata, 32'hAAAA_0000);

    do_request(22'h1, 6'h0, 2'b01, 1'b0, 32'h0);
    check_bit("T2: word1 hit", hit, 1'b1);
    check_eq("T2: word1 data", rdata, 32'hAAAA_1111);

    do_request(22'h1, 6'h0, 2'b10, 1'b0, 32'h0);
    check_bit("T2: word2 hit", hit, 1'b1);
    check_eq("T2: word2 data", rdata, 32'hAAAA_2222);

    do_request(22'h1, 6'h0, 2'b11, 1'b0, 32'h0);
    check_bit("T2: word3 hit", hit, 1'b1);
    check_eq("T2: word3 data", rdata, 32'hAAAA_3333);

    // -----------------------------------------------------------------
    // Test 3: Tag mismatch at same index must miss (index-conflict / aliasing)
    // -----------------------------------------------------------------
    $display("\n-- Test 3: index-conflict miss (same index, different tag) --");
    do_request(22'h2, 6'h0, 2'b00, 1'b0, 32'h0);
    check_bit("T3: different tag same index must MISS", hit, 1'b0);

    // -----------------------------------------------------------------
    // Test 4: Write-hit at word1, then confirm neighbors (word0,2,3)
    // are NOT clobbered by the partial-word write.
    // -----------------------------------------------------------------
    $display("\n-- Test 4: write-hit partial-word integrity --");
    do_request(22'h1, 6'h0, 2'b01, 1'b1, 32'hDEAD_BEEF);
    check_bit("T4: write-hit reports hit", hit, 1'b1);

    do_request(22'h1, 6'h0, 2'b01, 1'b0, 32'h0);
    check_eq("T4: word1 now updated", rdata, 32'hDEAD_BEEF);

    do_request(22'h1, 6'h0, 2'b00, 1'b0, 32'h0);
    check_eq("T4: word0 unchanged (neighbor integrity)", rdata, 32'hAAAA_0000);

    do_request(22'h1, 6'h0, 2'b10, 1'b0, 32'h0);
    check_eq("T4: word2 unchanged (neighbor integrity)", rdata, 32'hAAAA_2222);

    do_request(22'h1, 6'h0, 2'b11, 1'b0, 32'h0);
    check_eq("T4: word3 unchanged (neighbor integrity)", rdata, 32'hAAAA_3333);

    // -----------------------------------------------------------------
    // Test 5: A second, independent line at a different index must not
    // be affected by anything done to index 0 (index independence).
    // -----------------------------------------------------------------
    $display("\n-- Test 5: independent line at index=5 --");
    do_request(22'h3, 6'd5, 2'b00, 1'b0, 32'h0);
    check_bit("T5: index=5 cold miss (unaffected by index=0 activity)", hit, 1'b0);

    do_line_fill(6'd5, 22'h3, 32'hBBBB_0000, 32'hBBBB_1111, 32'hBBBB_2222, 32'hBBBB_3333);

    do_request(22'h3, 6'd5, 2'b10, 1'b0, 32'h0);
    check_bit("T5: index=5 hit after its own fill", hit, 1'b1);
    check_eq("T5: index=5 word2 data", rdata, 32'hBBBB_2222);

    // index=0 must still be untouched by index=5's fill
    do_request(22'h1, 6'h0, 2'b00, 1'b0, 32'h0);
    check_bit("T5: index=0 still hits (unaffected by index=5 fill)", hit, 1'b1);
    check_eq("T5: index=0 word0 still correct", rdata, 32'hAAAA_0000);

    // -----------------------------------------------------------------
    // Test 6: req_valid=0 must never assert hit, even with matching
    // tag/index left on the bus from a previous cycle.
    // -----------------------------------------------------------------
    $display("\n-- Test 6: req_valid gating --");
    core_addr_tag   = 22'h1;
    core_addr_index = 6'h0;
    core_req_valid  = 0;
    #1;
    check_bit("T6: hit must be 0 when req_valid=0", core_hit, 1'b0);
    @(posedge clk);
    #1;

    // -----------------------------------------------------------------
    // Test 7: Write-miss then re-check as a hit (write miss fills the
    // line, then behaves as a write-hit).
    // -----------------------------------------------------------------
    $display("\n-- Test 7: write-miss at index=10, tag=0x7 --");
    do_request(22'h7, 6'd10, 2'b00, 1'b1, 32'hCAFEF00D);
    check_bit("T7: write to unfilled line must MISS", hit, 1'b0);
    do_line_fill(6'd10, 22'h7, 32'h0, 32'h0, 32'h0, 32'h0);
    do_request(22'h7, 6'd10, 2'b00, 1'b1, 32'hCAFEF00D);
    check_bit("T7: write-hit after fill", hit, 1'b1);
    do_request(22'h7, 6'd10, 2'b00, 1'b0, 32'h0);
    check_eq("T7: word now holds written value", rdata, 32'hCAFEF00D);

    // -----------------------------------------------------------------
    // Summary
    // -----------------------------------------------------------------
    $display("\n==== SUMMARY: %0d checks run, %0d failed ====", checks, errors);
    if (errors == 0) $display("==== ALL TESTS PASSED ====");
    else $display("==== %0d TEST(S) FAILED ====", errors);

    $stop;
  end

endmodule
