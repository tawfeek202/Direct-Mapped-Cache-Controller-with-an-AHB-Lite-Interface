module mem_side_master_fsm (
    input wire HCLK,
    input wire HRESETn,
    input wire miss_req,
    input wire [31:0] miss_addr,
    input wire miss_is_write,
    input wire [31:0] miss_wdata,
    input wire HREADY,
    input wire [31:0] HRDATA,
    input wire [1:0] HRESP,
    output reg mem_op_done,
    output reg [5:0] fill_index,
    output reg [21:0] fill_tag,
    output reg fill_word_en,
    output reg [1:0] fill_word_sel,
    output reg [31:0] fill_word_data,
    output reg fill_commit,
    output reg [31:0] HADDR,
    output reg [1:0] HTRANS,
    output reg HWRITE,
    output reg [2:0] HSIZE,
    output reg [2:0] HBURST,
    output reg [31:0] HWDATA
);

  localparam HTRANS_IDLE = 2'b00;
  localparam HTRANS_NONSEQ = 2'b10;
  localparam HTRANS_SEQ = 2'b11;
  localparam HBURST_SINGLE = 3'b000;
  localparam HBURST_INCR4 = 3'b011;
  localparam HSIZE_WORD = 3'b010;

  localparam IDLE = 3'd0,
    RD_ADDR = 3'd1,
    RD_DATA = 3'd2,
    RD_COMMIT = 3'd3,
    WR_ADDR = 3'd4,
    WR_DATA = 3'd5,
    DONE = 3'd6,
    RD_WAIT = 3'd7;

  reg [2:0] state, next_state;
  reg  [31:0] addr_reg;
  reg  [31:0] wdata_reg;
  reg  [ 1:0] beat_cnt;
  reg  [31:0] line_base;

  wire [21:0] addr_tag = addr_reg[31:10];
  wire [ 5:0] addr_index = addr_reg[9:4];

  always @(posedge HCLK or negedge HRESETn) begin
    if (!HRESETn) state <= IDLE;
    else state <= next_state;
  end
  //request
  always @(posedge HCLK or negedge HRESETn) begin
    if (!HRESETn) begin
      addr_reg  <= 32'd0;
      wdata_reg <= 32'd0;
      line_base <= 32'd0;
    end else if (state == IDLE && miss_req) begin
      addr_reg  <= miss_addr;
      wdata_reg <= miss_wdata;
      line_base <= {miss_addr[31:4], 4'b0000};
    end
  end

  //beat counter
  always @(posedge HCLK or negedge HRESETn) begin
    if (!HRESETn) beat_cnt <= 2'd0;
    else if (state == IDLE) beat_cnt <= 2'd0;
    else if (state == RD_DATA && HREADY) beat_cnt <= beat_cnt + 2'd1;
  end

  //next state logic
  always @(*) begin
    next_state = state;
    case (state)
      IDLE: begin
        if (miss_req) next_state = miss_is_write ? WR_ADDR : RD_ADDR;
      end

      RD_ADDR: begin
        next_state = RD_WAIT;
      end

      RD_WAIT: begin
        // One dedicated cycle where the address is held stable on the
        // bus and we wait for the memory model's data-phase latency to
        // elapse before treating HRDATA as valid for this beat.
        next_state = RD_DATA;
      end

      RD_DATA: begin
        if (HREADY) begin
          if (beat_cnt == 2'd3) next_state = RD_COMMIT;
          else next_state = RD_ADDR;
        end
      end

      RD_COMMIT: begin
        next_state = DONE;
      end

      WR_ADDR: begin
        next_state = WR_DATA;
      end

      WR_DATA: begin
        if (HREADY) next_state = DONE;
      end

      DONE: begin
        next_state = IDLE;
      end

      default: next_state = IDLE;
    endcase
  end

  //output logic 
  always @(*) begin
    HADDR = 32'd0;
    HTRANS = HTRANS_IDLE;
    HWRITE = 1'b0;
    HSIZE = HSIZE_WORD;
    HBURST = HBURST_SINGLE;
    HWDATA = 32'd0;

    fill_index = addr_index;
    fill_tag = addr_tag;
    fill_word_en = 1'b0;
    fill_word_sel = beat_cnt;
    fill_word_data = HRDATA;
    fill_commit = 1'b0;
    mem_op_done = 1'b0;

    case (state)
      RD_ADDR: begin
        HADDR  = line_base + {28'd0, beat_cnt, 2'b00};
        HTRANS = (beat_cnt == 2'd0) ? HTRANS_NONSEQ : HTRANS_SEQ;
        HWRITE = 1'b0;
        HBURST = HBURST_INCR4;
      end

      RD_WAIT: begin
        // Keep the address phase signals stable while waiting for the
        // memory's data-phase latency to elapse.
        HADDR  = line_base + {28'd0, beat_cnt, 2'b00};
        HTRANS = (beat_cnt == 2'd0) ? HTRANS_NONSEQ : HTRANS_SEQ;
        HBURST = HBURST_INCR4;
      end

      RD_DATA: begin
        HADDR  = line_base + {28'd0, beat_cnt, 2'b00};
        HTRANS = (beat_cnt == 2'd0) ? HTRANS_NONSEQ : HTRANS_SEQ;
        HBURST = HBURST_INCR4;
        if (HREADY) fill_word_en = 1'b1;
      end

      RD_COMMIT: begin
        fill_commit = 1'b1;
      end

      WR_ADDR: begin
        HADDR  = addr_reg;
        HTRANS = HTRANS_NONSEQ;
        HWRITE = 1'b1;
        HWDATA = wdata_reg;
      end

      WR_DATA: begin
        HADDR  = addr_reg;
        HTRANS = HTRANS_NONSEQ;
        HWRITE = 1'b1;
        HWDATA = wdata_reg;
      end

      DONE: begin
        mem_op_done = 1'b1;
      end

      default: ;
    endcase
  end
endmodule
