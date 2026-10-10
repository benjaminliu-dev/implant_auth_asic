`timescale 1ns/1ps
module top_flow_tb #(
  parameter [79:0] EXPECTED_MASTER_KEY = 80'b0,
  parameter [63:0] RESTART_CIPHER = 64'h5579c1387b228445
);
  reg clk = 0;
  always #5 clk = ~clk;
  reg rst_n = 0, ena = 1;
  reg [7:0] ui_in = 2, uio_in = 0;
  wire [7:0] uo_out, uio_out, uio_oe;
  reg [63:0] plaintext, expected, packet;
  integer fd, status, count = 0, phase;
  tt_um_implant_auth_top dut(.*);
  initial begin #1000000; $fatal(1, "top timeout"); end
  // Protocol stimulus uses external pins only. Internal observations check clearing.
  always @(negedge clk) begin
    if (uo_out[7:1] !== 0 || uio_out !== 0 || uio_oe !== 0) $fatal(1, "unexpected external control pins");
  end
  task check_clear;
    begin
      if (uo_out !== 0 || dut.state_data !== 0 || dut.key_data !== 0 ||
          dut.transmit_data !== 0 || dut.receive_data_bus !== 0 ||
          dut.serial_inst.tx_shift !== 0 || dut.serial_inst.rx_shift !== 0 ||
          dut.serial_receive_data !== 0 || dut.serial_busy !== 0 ||
          dut.present_inst.state_reg !== 0 || dut.present_inst.key_reg !== 0 ||
          dut.ciphertext_data !== 0 || dut.present_busy !== 0 ||
          dut.serial_done !== 0 || dut.present_done !== 0 ||
          dut.bus_write_en !== 0 || dut.serial_start !== 0 || dut.present_start !== 0)
        $fatal(1, "top EN/reset did not clear storage");
    end
  endtask
  task clear;
    begin
      @(negedge clk); #2; ui_in[1] = 1; #1; check_clear;
      repeat (3) @(negedge clk);
      check_clear;
    end
  endtask
  task read_packet(output [63:0] data);
    integer bit_index;
    begin
      // Called at the falling edge preceding the first sample edge.
      for (bit_index = 63; bit_index >= 0; bit_index = bit_index - 1) begin
        data[bit_index] = uo_out[0];
        @(posedge clk); #1;
        if (bit_index > 0) @(negedge clk);
      end
    end
  endtask
  task begin_session;
    integer clocks;
    reg found;
    begin
      @(negedge clk); ui_in[1] = 0; found = 0;
      for (clocks = 0; clocks < 12 && !found; clocks = clocks + 1) begin
        @(negedge clk);
        if (uo_out[0] === 1) found = 1;
      end
      if (!found) $fatal(1, "no start packet");
      read_packet(packet);
      if (packet !== 64'ha500000000000000) $fatal(1, "start packet %h", packet);
      if (dut.key_data !== EXPECTED_MASTER_KEY) $fatal(1, "ROM-to-bus key programming");
    end
  endtask
  task send_plaintext(input [63:0] data);
    integer bit_index;
    begin
      // Four controller edges after the last start-packet bit launch RX.
      repeat (4) begin @(posedge clk); #1; end
      for (bit_index = 63; bit_index >= 0; bit_index = bit_index - 1) begin
        @(negedge clk); ui_in[0] = data[bit_index];
        if (uo_out[0] !== 0) $fatal(1, "RX phase must transmit zero");
        @(posedge clk); #1;
      end
    end
  endtask
  initial begin
    // Generate an explicit reset edge even when EN is high at power-up.
    #1; ui_in[1] = 0; rst_n = 1; #1; rst_n = 0; ui_in[1] = 1; #1; check_clear;
    @(negedge clk); rst_n = 1;
    fd = $fopen("top_vectors.txt", "r");
    if (!fd) $fatal(1, "missing top vectors");
    status = $fscanf(fd, "%h %h\n", plaintext, expected);
    while (status == 2) begin
      begin_session;
      send_plaintext(plaintext);
      // Fixed external timing: 31 rounds plus register/control transfer edges.
      repeat (37) begin @(posedge clk); #1; end
      @(negedge clk); read_packet(packet);
      if (packet !== expected) $fatal(1, "top vector %0d p=%h expected=%h actual=%h", count, plaintext, expected, packet);
      if (dut.state_data !== plaintext) $fatal(1, "received state mismatch");
      repeat (12) begin @(negedge clk); ui_in[0] = ~ui_in[0]; end
      if (uo_out !== 0 || dut.serial_busy !== 0 || dut.present_busy !== 0) $fatal(1, "restarted while EN stayed low");
      clear;
      count = count + 1;
      status = $fscanf(fd, "%h %h\n", plaintext, expected);
    end
    // Abort in boot, start TX, RX, encryption, and ciphertext TX; verify restart.
    for (phase = 0; phase < 5; phase = phase + 1) begin
      @(negedge clk); ui_in[1] = 0; ui_in[0] = 1;
      case (phase)
        0: repeat (2) @(negedge clk);
        1: repeat (20) @(negedge clk);
        2: repeat (100) @(negedge clk);
        3: repeat (145) @(negedge clk);
        4: repeat (190) @(negedge clk);
      endcase
      clear;
      begin_session; send_plaintext(0);
      repeat (37) begin @(posedge clk); #1; end
      @(negedge clk); read_packet(packet);
      if (packet !== RESTART_CIPHER) $fatal(1, "top restart phase %0d", phase);
      clear;
    end
    begin_session; send_plaintext(64'h123456789abcdef0);
    #2; rst_n = 0; #1; check_clear;
    // Keep EN high before releasing reset to avoid an unintended new session.
    ui_in[1] = 1; @(negedge clk); rst_n = 1; clear;
    $display("PASS top: %0d pin-driven transactions, five EN abort/restarts, global reset, idle and clear", count);
    $finish;
  end
endmodule
