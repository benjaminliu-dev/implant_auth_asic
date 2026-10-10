`timescale 1ns/1ps
module present_core_tb;
  reg clk = 0;
  always #5 clk = ~clk;
  reg rst_n = 0, start = 0;
  reg [63:0] plaintext;
  reg [79:0] key;
  wire [63:0] ciphertext;
  wire busy, done;
  reg [63:0] expected;
  integer fd, status, count = 0, cycle;
  present80_encrypt dut(.*);
  initial begin #200000; $fatal(1, "core timeout"); end
  initial begin
    #1; rst_n = 1; #1; rst_n = 0;
    #1;
    if (ciphertext !== 0 || busy !== 0 || done !== 0) $fatal(1, "core reset");
    @(negedge clk); rst_n = 1;
    fd = $fopen("core_vectors.txt", "r");
    if (!fd) $fatal(1, "missing core vectors; use run_functional.py");
    status = $fscanf(fd, "%h %h %h\n", plaintext, key, expected);
    while (status == 3) begin
      start = 1;
      @(posedge clk); #1;
      if (busy !== 1 || done !== 0) $fatal(1, "core start handshake");
      @(negedge clk); start = 0;
      // Inputs are captured once; a start pulse while busy is ignored.
      plaintext = ~plaintext; key = ~key;
      for (cycle = 1; cycle <= 31; cycle = cycle + 1) begin
        start = cycle == 5;
        @(posedge clk); #1;
        if (cycle < 31 && (busy !== 1 || done !== 0)) $fatal(1, "early core completion");
        if (cycle == 31 && (busy !== 0 || done !== 1 || ciphertext !== expected))
          $fatal(1, "core vector %0d expected=%h actual=%h", count, expected, ciphertext);
        @(negedge clk);
      end
      start = 0;
      @(posedge clk); #1;
      if (done !== 0 || busy !== 0 || ciphertext !== expected) $fatal(1, "core done pulse/hold");
      @(negedge clk);
      count = count + 1;
      status = $fscanf(fd, "%h %h %h\n", plaintext, key, expected);
    end
    $fclose(fd);
    plaintext = 0; key = 0; start = 1;
    @(negedge clk); start = 0;
    repeat (7) @(negedge clk);
    #2; rst_n = 0; #1;
    if (busy !== 0 || done !== 0 || ciphertext !== 0 || dut.state_reg !== 0 || dut.key_reg !== 0)
      $fatal(1, "core abort did not clear");
    @(negedge clk); rst_n = 1; start = 1;
    @(negedge clk); start = 0;
    repeat (31) @(posedge clk);
    #1;
    if (done !== 1 || ciphertext !== 64'h5579c1387b228445) $fatal(1, "core restart");
    $display("PASS core: %0d vectors, latency, input capture, busy start, abort/restart", count);
    $finish;
  end
endmodule
