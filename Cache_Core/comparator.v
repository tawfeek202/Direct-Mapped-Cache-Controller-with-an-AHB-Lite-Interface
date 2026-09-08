module comparator (
    input  [21:0] addr_tag,
    input  [21:0] stored_tag,
    input         valid,
    input         req_valid,
    output        hit
);

  assign hit = req_valid && (addr_tag == stored_tag) && valid;

endmodule
