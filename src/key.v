`default_nettype none

module gate_rom_strip (
  output wire [79:0] key_data
);
  assign key_data = 80'h0000_0000_0000_0000_0000;
endmodule

module present80_key_update (
  input  wire [79:0] key_in,
  input  wire [4:0]  round_counter,
  output wire [63:0] round_key,
  output wire [79:0] key_out
);
  wire [79:0] rotated_key;
  wire [3:0] sbox_key_bits;

  assign round_key = key_in[79:16];
  assign rotated_key = {key_in[18:0], key_in[79:19]};

  present_sbox4 key_sbox_inst (
    .in(rotated_key[79:76]),
    .out(sbox_key_bits)
  );

  assign key_out = {
    sbox_key_bits,
    rotated_key[75:20],
    rotated_key[19:15] ^ round_counter,
    rotated_key[14:0]
  };
endmodule
