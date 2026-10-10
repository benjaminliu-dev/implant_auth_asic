/*
 * Copyright (c) 2024 Your Name
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_implant_auth_top (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);
  localparam [63:0] STATE_ADDR = 64'h0000_0000_0000_0000;
  localparam [63:0] KEY_ADDR   = 64'h0000_0000_0000_0008;
  localparam [63:0] TX_ADDR    = 64'h0000_0000_0000_0010;
  localparam [63:0] RX_ADDR    = 64'h0000_0000_0000_0018;
  localparam [63:0] KEY_TAIL_ADDR = 64'h0000_0000_0000_0020;
  localparam [63:0] START_PACKET = 64'hA5_00_00_00_00_00_00_00;

  localparam [3:0] ST_BOOT_KEY_HI = 4'd0;
  localparam [3:0] ST_BOOT_KEY_LO = 4'd1;
  localparam [3:0] ST_LOAD_START_TX = 4'd2;
  localparam [3:0] ST_SEND_START = 4'd3;
  localparam [3:0] ST_WAIT_START = 4'd4;
  localparam [3:0] ST_LOAD_RECV_TX = 4'd5;
  localparam [3:0] ST_RECV_STATE = 4'd6;
  localparam [3:0] ST_WAIT_RECV = 4'd7;
  localparam [3:0] ST_START_PRESENT = 4'd8;
  localparam [3:0] ST_WAIT_PRESENT = 4'd9;
  localparam [3:0] ST_SEND_CIPHER = 4'd10;
  localparam [3:0] ST_WAIT_CIPHER = 4'd11;
  localparam [3:0] ST_DONE = 4'd12;

  wire sdi = ui_in[0];
  wire en_pin = ui_in[1];
  wire active_reset_n = rst_n && !en_pin;

  reg [3:0] controller_state;
  reg [63:0] bus_addr;
  reg [63:0] bus_write_data;
  reg bus_write_en;
  reg serial_start;
  reg present_start;

  wire [63:0] bus_data;
  wire [63:0] state_data;
  wire [79:0] key_data;
  wire [63:0] transmit_data;
  wire [63:0] receive_data_bus;
  wire [63:0] serial_receive_data;
  wire serial_receive_valid;
  wire serial_busy;
  wire serial_done;
  wire sdo;
  wire [63:0] ciphertext_data;
  wire present_busy;
  wire present_done;
  wire [79:0] rom_key_data;

  assign bus_data = bus_write_en ? bus_write_data : 64'bz;

  always @(posedge clk or negedge active_reset_n) begin
    if (!active_reset_n) begin
      controller_state <= ST_BOOT_KEY_HI;
      bus_addr <= 64'b0;
      bus_write_data <= 64'b0;
      bus_write_en <= 1'b0;
      serial_start <= 1'b0;
      present_start <= 1'b0;
    end else begin
      bus_write_en <= 1'b0;
      serial_start <= 1'b0;
      present_start <= 1'b0;

      case (controller_state)
        ST_BOOT_KEY_HI: begin
          bus_addr <= KEY_ADDR;
          bus_write_data <= rom_key_data[79:16];
          bus_write_en <= 1'b1;
          controller_state <= ST_BOOT_KEY_LO;
        end

        ST_BOOT_KEY_LO: begin
          bus_addr <= KEY_TAIL_ADDR;
          bus_write_data <= {48'b0, rom_key_data[15:0]};
          bus_write_en <= 1'b1;
          controller_state <= ST_LOAD_START_TX;
        end

        ST_LOAD_START_TX: begin
          bus_addr <= TX_ADDR;
          bus_write_data <= START_PACKET;
          bus_write_en <= 1'b1;
          controller_state <= ST_SEND_START;
        end

        ST_SEND_START: begin
          serial_start <= 1'b1;
          controller_state <= ST_WAIT_START;
        end

        ST_WAIT_START: begin
          if (serial_done) begin
            controller_state <= ST_LOAD_RECV_TX;
          end
        end

        ST_LOAD_RECV_TX: begin
          bus_addr <= TX_ADDR;
          bus_write_data <= 64'b0;
          bus_write_en <= 1'b1;
          controller_state <= ST_RECV_STATE;
        end

        ST_RECV_STATE: begin
          serial_start <= 1'b1;
          controller_state <= ST_WAIT_RECV;
        end

        ST_WAIT_RECV: begin
          if (serial_receive_valid) begin
            bus_addr <= STATE_ADDR;
            bus_write_data <= serial_receive_data;
            bus_write_en <= 1'b1;
            controller_state <= ST_START_PRESENT;
          end
        end

        ST_START_PRESENT: begin
          present_start <= 1'b1;
          controller_state <= ST_WAIT_PRESENT;
        end

        ST_WAIT_PRESENT: begin
          if (present_done) begin
            controller_state <= ST_SEND_CIPHER;
          end
        end

        ST_SEND_CIPHER: begin
          serial_start <= 1'b1;
          controller_state <= ST_WAIT_CIPHER;
        end

        ST_WAIT_CIPHER: begin
          if (serial_done) begin
            controller_state <= ST_DONE;
          end
        end

        default: begin
          controller_state <= ST_DONE;
        end
      endcase
    end
  end

  gate_rom_strip key_rom_inst (
    .key_data(rom_key_data)
  );

  system_bus bus_inst (
    .clk(clk),
    .rst_n(active_reset_n),
    .data_bus(bus_data),
    .addr_bus(bus_addr),
    .write_en(bus_write_en),
    .read_en(1'b0),
    .receive_data_in(serial_receive_data),
    .receive_data_write(serial_receive_valid),
    .encrypt_data_in(ciphertext_data),
    .encrypt_data_write(present_done),
    .state_out(state_data),
    .key_out(key_data),
    .transmit_data_out(transmit_data),
    .receive_data_out(receive_data_bus)
  );

  serial serial_inst (
    .clk(clk),
    .rst_n(active_reset_n),
    .start(serial_start),
    .sdi(sdi),
    .transmit_data(transmit_data),
    .sdo(sdo),
    .receive_data(serial_receive_data),
    .receive_data_valid(serial_receive_valid),
    .busy(serial_busy),
    .done(serial_done)
  );

  present80_encrypt present_inst (
    .clk(clk),
    .rst_n(active_reset_n),
    .start(present_start),
    .plaintext(state_data),
    .key(key_data),
    .ciphertext(ciphertext_data),
    .busy(present_busy),
    .done(present_done)
  );

  assign uo_out = {7'b0, sdo};
  assign uio_out = 8'b0;
  assign uio_oe = 8'b0;

  wire _unused = &{
    ena,
    ui_in[7:2],
    uio_in,
    receive_data_bus,
    serial_busy,
    present_busy,
    controller_state,
    1'b0
  };
endmodule
