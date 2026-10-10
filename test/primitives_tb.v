`timescale 1ns/1ps
module primitives_tb;
  reg [3:0] nibble;
  wire [3:0] substituted;
  reg [63:0] state;
  wire [63:0] sbox_layer, permutation;
  reg [79:0] key_in;
  reg [4:0] round_counter;
  wire [79:0] key_out, rom;
  wire [63:0] round_key;
  reg [7:0] a, b;
  wire [7:0] y;
  reg [3:0] table_sbox [0:15];
  reg [79:0] expected_key;
  integer i, j, fd, status, count = 0;
  present_sbox4 sb(nibble, substituted);
  present_sbox_layer sl(state, sbox_layer);
  present_p_layer pl(state, permutation);
  present80_key_update ku(key_in, round_counter, round_key, key_out);
  gate_rom_strip gr(rom);
  xor8 xx(a, b, y);
  initial begin
    {table_sbox[0], table_sbox[1], table_sbox[2], table_sbox[3],
     table_sbox[4], table_sbox[5], table_sbox[6], table_sbox[7],
     table_sbox[8], table_sbox[9], table_sbox[10], table_sbox[11],
     table_sbox[12], table_sbox[13], table_sbox[14], table_sbox[15]} = 64'hc56b90ad3ef84712;
    for (i = 0; i < 16; i = i + 1) begin
      nibble = i; state = {16{nibble}}; #1;
      if (substituted !== table_sbox[i] || sbox_layer !== {16{table_sbox[i]}})
        $fatal(1, "S-box input %h", nibble);
    end
    for (i = 0; i < 16; i = i + 1) begin
      for (j = 0; j < 16; j = j + 1) state[4*j +: 4] = (i+j)%16;
      #1;
      for (j = 0; j < 16; j = j + 1)
        if (sbox_layer[4*j +: 4] !== table_sbox[(i+j)%16]) $fatal(1, "S-box lane");
    end
    for (i = 0; i < 64; i = i + 1) begin
      state = 64'b1 << i; #1;
      if (permutation !== (64'b1 << (16*(i%4)+i/4))) $fatal(1, "permutation bit %0d", i);
    end
    for (i = 0; i < 256; i = i + 1)
      for (j = 0; j < 256; j = j + 1) begin
        a = i; b = j; #1;
        if (y !== (a ^ b)) $fatal(1, "XOR");
      end
    fd = $fopen("key_vectors.txt", "r");
    if (!fd) $fatal(1, "missing key vectors");
    status = $fscanf(fd, "%h %h %h\n", key_in, round_counter, expected_key);
    while (status == 3) begin
      #1;
      if (key_out !== expected_key || round_key !== key_in[79:16]) $fatal(1, "key schedule");
      count = count + 1;
      status = $fscanf(fd, "%h %h %h\n", key_in, round_counter, expected_key);
    end
    if (rom !== 80'b0) $fatal(1, "ROM content");
    $display("PASS primitives: S-box/lane coverage, 64 permutation bits, 65536 XOR pairs, %0d key updates", count);
    $finish;
  end
endmodule
