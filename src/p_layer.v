`default_nettype none

module present_p_layer (
  input  wire [63:0] in,
  output wire [63:0] out
);
  genvar i;

  generate
    for (i = 0; i < 63; i = i + 1) begin : permute_gen
      assign out[(16 * i) % 63] = in[i];
    end
  endgenerate

  assign out[63] = in[63];
endmodule
