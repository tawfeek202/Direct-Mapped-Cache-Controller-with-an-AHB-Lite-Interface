module cache_controller_top (
    // ---------------------------------------------------------------
    // Global signals (distributed clock/reset, per project convention)
    // ---------------------------------------------------------------
    input wire HCLK,
    input wire HRESETn,

    // ---------------------------------------------------------------
    // CPU-side AHB-Lite SLAVE port (this block is the slave)
    // ---------------------------------------------------------------
    input  wire [31:0] HADDR,
    input  wire [ 1:0] HTRANS,
    input  wire        HWRITE,
    input  wire [ 2:0] HSIZE,
    input  wire [ 2:0] HBURST,
    input  wire [31:0] HWDATA,
    output wire        HREADY,
    output wire [31:0] HRDATA,
    output wire [ 1:0] HRESP,

    // ---------------------------------------------------------------
    // Memory-side AHB-Lite MASTER port (this block is the master)
    // ---------------------------------------------------------------
    output wire [31:0] mHADDR,
    output wire [ 1:0] mHTRANS,
    output wire        mHWRITE,
    output wire [ 2:0] mHSIZE,
    output wire [ 2:0] mHBURST,
    output wire [31:0] mHWDATA,
    input  wire [31:0] mHRDATA,
    input  wire        mHREADY,
    input  wire [ 1:0] mHRESP
);

  // -----------------------------------------------------------------
  // Internal: cpu_side_slave_fsm <-> cache_core
  // -----------------------------------------------------------------
  wire [21:0] core_addr_tag;
  wire [ 5:0] core_addr_index;
  wire [ 1:0] core_word_offset;
  wire        core_req_valid;
  wire        core_we;
  wire [31:0] core_wdata;
  wire        core_hit;
  wire [31:0] core_rdata;

  // -----------------------------------------------------------------
  // Internal: cpu_side_slave_fsm <-> mem_side_master_fsm
  // -----------------------------------------------------------------
  wire        miss_req;
  wire [31:0] miss_addr;
  wire        miss_is_write;
  wire [31:0] miss_wdata;
  wire        mem_op_done;

  // -----------------------------------------------------------------
  // Internal: mem_side_master_fsm -> cache_core (fill bus)
  // -----------------------------------------------------------------
  wire [ 5:0] fill_index;
  wire [21:0] fill_tag;
  wire        fill_word_en;
  wire [ 1:0] fill_word_sel;
  wire [31:0] fill_word_data;
  wire        fill_commit;

  // -----------------------------------------------------------------
  // CPU-side AHB-Lite slave FSM
  // -----------------------------------------------------------------
  cpu_side_slave_fsm u_cpu_side_slave_fsm (
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

      .core_addr_tag   (core_addr_tag),
      .core_addr_index (core_addr_index),
      .core_word_offset(core_word_offset),
      .core_req_valid  (core_req_valid),
      .core_we         (core_we),
      .core_wdata      (core_wdata),
      .core_hit        (core_hit),
      .core_rdata      (core_rdata),

      .miss_req     (miss_req),
      .miss_addr    (miss_addr),
      .miss_is_write(miss_is_write),
      .miss_wdata   (miss_wdata),
      .mem_op_done  (mem_op_done)
  );

  // -----------------------------------------------------------------
  // Cache storage core (tag/valid + comparator + data array)
  // -----------------------------------------------------------------
  cache_core u_cache_core (
      .clk  (HCLK),
      .rst_n(HRESETn),

      .core_addr_tag   (core_addr_tag),
      .core_addr_index (core_addr_index),
      .core_word_offset(core_word_offset),
      .core_req_valid  (core_req_valid),
      .core_we         (core_we),
      .core_wdata      (core_wdata),
      .core_hit        (core_hit),
      .core_rdata      (core_rdata),

      .fill_index    (fill_index),
      .fill_tag      (fill_tag),
      .fill_word_en  (fill_word_en),
      .fill_word_sel (fill_word_sel),
      .fill_word_data(fill_word_data),
      .fill_commit   (fill_commit)
  );

  // -----------------------------------------------------------------
  // Memory-side AHB-Lite master FSM
  // -----------------------------------------------------------------
  mem_side_master_fsm u_mem_side_master_fsm (
      .HCLK   (HCLK),
      .HRESETn(HRESETn),

      .miss_req     (miss_req),
      .miss_addr    (miss_addr),
      .miss_is_write(miss_is_write),
      .miss_wdata   (miss_wdata),
      .mem_op_done  (mem_op_done),

      .fill_index    (fill_index),
      .fill_tag      (fill_tag),
      .fill_word_en  (fill_word_en),
      .fill_word_sel (fill_word_sel),
      .fill_word_data(fill_word_data),
      .fill_commit   (fill_commit),

      // Memory-side AHB master port, driven straight to the top
      .HADDR (mHADDR),
      .HTRANS(mHTRANS),
      .HWRITE(mHWRITE),
      .HSIZE (mHSIZE),
      .HBURST(mHBURST),
      .HWDATA(mHWDATA),
      .HRDATA(mHRDATA),
      .HREADY(mHREADY),
      .HRESP (mHRESP)
  );

endmodule
