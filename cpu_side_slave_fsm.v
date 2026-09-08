module cpu_side_slave_fsm (
    // Global Signals
    input wire HCLK,
    input wire HRESETn,

    // CPU AHB Slave Signals
    input  wire [31:0] HADDR,
    input  wire [ 1:0] HTRANS,  // 2'b10: NONSEQ starts a new request, 2'b11
    input  wire        HWRITE,
    input  wire [ 2:0] HSIZE,
    input  wire [ 2:0] HBURST,
    input  wire [31:0] HWDATA,
    output reg         HREADY,
    output reg  [31:0] HRDATA,
    output wire [ 1:0] HRESP,

    // Interface to Cache Core
    output wire [21:0] core_addr_tag,
    output wire [ 5:0] core_addr_index,
    output wire [ 1:0] core_word_offset,
    output reg         core_req_valid,
    output reg         core_we,
    output reg  [31:0] core_wdata,
    input  wire        core_hit,
    input  wire [31:0] core_rdata,

    // Interface to Memory Side Master FSM
    output reg         miss_req,
    output reg  [31:0] miss_addr,
    output reg         miss_is_write,
    output reg  [31:0] miss_wdata,
    input  wire        mem_op_done
);

  // AHB HTRANS Parameters
  localparam TR_NONSEQ = 2'b10;
  localparam TR_SEQ = 2'b11;

  // FSM States
  localparam STATE_IDLE = 2'b00;
  localparam STATE_MISS_WAIT = 2'b01;
  localparam STATE_WRITE_WAIT = 2'b10;
  localparam STATE_COMPLETE = 2'b11;

  reg [1:0] current_state, next_state;


  assign core_addr_tag    = HADDR[31:10];
  assign core_addr_index  = HADDR[9:4];
  assign core_word_offset = HADDR[3:2];
  assign HRESP            = 2'b00;

  wire valid_ahb_req = (HTRANS == TR_NONSEQ || HTRANS == TR_SEQ);


  always @(posedge HCLK or negedge HRESETn) begin
    if (!HRESETn) current_state <= STATE_IDLE;
    else current_state <= next_state;
  end


  always @(*) begin

    next_state     = current_state;
    HREADY         = 1'b1;
    HRDATA         = 32'b0;
    core_req_valid = 1'b0;
    core_we        = 1'b0;
    core_wdata     = HWDATA;
    miss_req       = 1'b0;
    miss_addr      = HADDR;
    miss_is_write  = HWRITE;
    miss_wdata     = HWDATA;

    case (current_state)
      STATE_IDLE: begin
        if (valid_ahb_req) begin
          core_req_valid = 1'b1;
          if (core_hit) begin
            if (HWRITE) begin

              core_we    = 1'b1;
              miss_req   = 1'b1;
              HREADY     = 1'b0;
              next_state = STATE_WRITE_WAIT;
            end else begin

              HRDATA     = core_rdata;
              HREADY     = 1'b1;
              next_state = STATE_IDLE;
            end
          end else begin

            miss_req      = 1'b1;
            miss_is_write = 1'b0;
            HREADY        = 1'b0;
            next_state    = STATE_MISS_WAIT;
          end
        end
      end

      STATE_MISS_WAIT: begin
        HREADY        = 1'b0;
        miss_req      = 1'b1;
        miss_is_write = 1'b0;

        if (mem_op_done) begin
          next_state = STATE_COMPLETE;
        end
      end

      STATE_WRITE_WAIT: begin
        HREADY        = 1'b0;
        miss_req      = 1'b1;
        miss_is_write = 1'b1;

        if (mem_op_done) begin
          HREADY     = 1'b1;
          next_state = STATE_IDLE;
        end
      end

      STATE_COMPLETE: begin

        core_req_valid = 1'b1;

        if (!HWRITE) begin

          HRDATA     = core_rdata;
          HREADY     = 1'b1;
          next_state = STATE_IDLE;
        end else begin

          core_we       = 1'b1;
          miss_req      = 1'b1;
          miss_is_write = 1'b1;
          HREADY        = 1'b0;
          next_state    = STATE_WRITE_WAIT;
        end
      end

      default: next_state = STATE_IDLE;
    endcase
  end

endmodule
