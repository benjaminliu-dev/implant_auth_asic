`default_nettype none

module present_sbox4 (
  input  wire [3:0] in,
  output reg  [3:0] out
);
  always @(*) begin
    case (in)
      4'h0: out = 4'hc;
      4'h1: out = 4'h5;
      4'h2: out = 4'h6;
      4'h3: out = 4'hb;
      4'h4: out = 4'h9;
      4'h5: out = 4'h0;
      4'h6: out = 4'ha;
      4'h7: out = 4'hd;
      4'h8: out = 4'h3;
      4'h9: out = 4'he;
      4'ha: out = 4'hf;
      4'hb: out = 4'h8;
      4'hc: out = 4'h4;
      4'hd: out = 4'h7;
      4'he: out = 4'h1;
      default: out = 4'h2;
    endcase
  end
endmodule

module present_sbox_layer (
  input  wire [63:0] in,
  output wire [63:0] out
);
  genvar i;

  generate
    for (i = 0; i < 16; i = i + 1) begin : sbox_gen
      present_sbox4 sbox_inst (
        .in(in[(i * 4) +: 4]),
        .out(out[(i * 4) +: 4])
      );
    end
  endgenerate
endmodule
