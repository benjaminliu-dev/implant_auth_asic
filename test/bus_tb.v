`timescale 1ns/1ps
module bus_tb;
  reg clk = 0;
  always #5 clk = ~clk;
  reg rst_n = 0;
  wire [63:0] data_bus;
  reg [63:0] addr_bus = 0, write_data = 0;
  reg drive = 0, write_en = 0, read_en = 0;
  reg [63:0] receive_data_in = 0, encrypt_data_in = 0;
  reg receive_data_write = 0, encrypt_data_write = 0;
  wire [63:0] state_out, transmit_data_out, receive_data_out;
  wire [79:0] key_out;
  integer i;
  reg [63:0] value;
  assign data_bus = drive ? write_data : 64'bz;
  system_bus dut(.*);
  task write_reg(input [63:0] address, input [63:0] data);
    begin
      @(negedge clk); addr_bus = address; write_data = data; drive = 1; write_en = 1;
      @(posedge clk); #1;
      @(negedge clk); write_en = 0; drive = 0;
    end
  endtask
  task read_reg(input [63:0] address, input [63:0] expected);
    begin
      addr_bus = address; read_en = 1; #1;
      if (data_bus !== expected) $fatal(1, "bus read addr=%h expected=%h actual=%h", address, expected, data_bus);
      read_en = 0; #1;
      if (data_bus !== 64'bz) $fatal(1, "bus did not release");
    end
  endtask
  initial begin #100000; $fatal(1, "bus timeout"); end
  initial begin
    #1; rst_n = 1; #1; rst_n = 0; #1;
    if ({state_out,key_out,transmit_data_out,receive_data_out} !== 272'b0) $fatal(1, "bus reset");
    @(negedge clk); rst_n = 1;
    for (i = 0; i < 64; i = i + 1) begin
      value = 64'b1 << i;
      write_reg(0, value); read_reg(0, value);
      write_reg(8, ~value); read_reg(8, ~value);
      write_reg(16, value); read_reg(16, value);
      write_reg(24, ~value); read_reg(24, ~value);
      write_reg(32, value); read_reg(32, {48'b0,value[15:0]});
      if (key_out !== {~value,value[15:0]}) $fatal(1, "key split writes corrupt bits");
    end
    write_reg(64'h100, 0);
    read_reg(64'h100, 0);
    // Full 64-bit decode, no aliasing through only the low address bits.
    write_reg(64'h1000000000000000, 0); read_reg(0, value);
    write_reg(64'h1000000000000008, 0); read_reg(8, ~value);
    // No write without write enable; read wins if both enables are asserted.
    @(negedge clk); addr_bus = 0; drive = 1; write_data = 0;
    @(posedge clk); #1;
    if (state_out !== value) $fatal(1, "write without enable");
    @(negedge clk); drive = 0; write_en = 1; read_en = 1;
    @(posedge clk); #1;
    if (state_out !== value || data_bus !== value) $fatal(1, "simultaneous read/write");
    @(negedge clk); read_en = 0; write_en = 0;
    receive_data_in = 64'h0123456789abcdef; receive_data_write = 1;
    encrypt_data_in = 64'hfedcba9876543210; encrypt_data_write = 1;
    @(posedge clk); #1;
    read_reg(24, receive_data_in); read_reg(16, encrypt_data_in);
    @(negedge clk);
    // Explicit bus writes have priority over simultaneous side writes.
    addr_bus = 16; drive = 1; write_en = 1; write_data = 64'habc;
    @(posedge clk); #1;
    if (transmit_data_out !== 64'habc) $fatal(1, "TX write priority");
    @(negedge clk); addr_bus = 24;
    @(posedge clk); #1;
    if (receive_data_out !== 64'habc) $fatal(1, "RX write priority");
    @(negedge clk); write_en = 0; drive = 0; receive_data_write = 0; encrypt_data_write = 0;
    #2; rst_n = 0; #1;
    if ({state_out,key_out,transmit_data_out,receive_data_out} !== 272'b0) $fatal(1, "bus async clear");
    read_reg(0, 0); read_reg(8, 0); read_reg(16, 0); read_reg(24, 0); read_reg(32, 0);
    $display("PASS bus: all registers/bits, 64-bit decoding, enables, side writes, priorities, clear");
    $finish;
  end
endmodule
