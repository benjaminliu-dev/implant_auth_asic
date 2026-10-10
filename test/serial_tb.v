`timescale 1ns/1ps
module serial_tb;
  reg clk = 0;
  always #5 clk = ~clk;
  reg rst_n = 0, start = 0, sdi = 0;
  reg [63:0] transmit_data = 0;
  wire sdo, receive_data_valid, busy, done;
  wire [63:0] receive_data;
  integer i;
  serial dut(.*);
  task transfer(input [63:0] tx, input [63:0] rx);
    integer bit_index;
    begin
      @(negedge clk); transmit_data = tx; start = 1;
      @(posedge clk); #1;
      if (busy !== 1 || done !== 0) $fatal(1, "serial start");
      @(negedge clk); start = 0; transmit_data = ~tx;
      for (bit_index = 63; bit_index >= 0; bit_index = bit_index - 1) begin
        sdi = rx[bit_index];
        // Starts while active must not reload the TX shift register.
        start = bit_index == 40;
        if (sdo !== tx[bit_index] || busy !== 1 || done !== 0)
          $fatal(1, "serial TX bit %0d expected=%b actual=%b", bit_index, tx[bit_index], sdo);
        @(posedge clk); #1;
        if (bit_index > 0 && (receive_data_valid !== 0 || busy !== 1)) $fatal(1, "serial early completion");
        if (bit_index == 0 && (receive_data !== rx || done !== 1 || busy !== 0 || sdo !== 0))
          $fatal(1, "serial RX expected=%h actual=%h", rx, receive_data);
        @(negedge clk);
      end
      start = 0;
      @(posedge clk); #1;
      if (done !== 0 || receive_data_valid !== 0 || receive_data !== rx) $fatal(1, "serial done/hold");
    end
  endtask
  initial begin #1000000; $fatal(1, "serial timeout"); end
  initial begin
    #1; rst_n = 1; #1; rst_n = 0; #1;
    if (receive_data !== 0 || busy !== 0 || sdo !== 0 || done !== 0) $fatal(1, "serial reset");
    @(negedge clk); rst_n = 1;
    transfer(0, 64'hffffffffffffffff);
    transfer(64'hffffffffffffffff, 0);
    transfer(64'h0123456789abcdef, 64'hfedcba9876543210);
    for (i = 0; i < 64; i = i + 1) transfer(64'b1 << i, ~(64'b1 << i));
    for (i = 0; i < 32; i = i + 1) transfer({$random,$random}, {$random,$random});
    @(negedge clk); transmit_data = -1; start = 1;
    @(negedge clk); start = 0; sdi = 1;
    repeat (17) @(negedge clk);
    #2; rst_n = 0; #1;
    if (receive_data !== 0 || busy !== 0 || sdo !== 0 || done !== 0 || dut.tx_shift !== 0 || dut.rx_shift !== 0)
      $fatal(1, "serial abort clear");
    @(negedge clk); rst_n = 1;
    transfer(64'h8000000000000001, 64'h8000000000000001);
    $display("PASS serial: 100 duplex packets, MSB order, exact 64 bits, busy starts, captured TX, abort/restart");
    $finish;
  end
endmodule
