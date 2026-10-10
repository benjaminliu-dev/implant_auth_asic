`default_nettype none

module system_bus (
  input  wire        clk,
  input  wire        rst_n,
  inout  wire [63:0] data_bus,
  input  wire [63:0] addr_bus,
  input  wire        write_en,
  input  wire        read_en,
  input  wire [63:0] receive_data_in,
  input  wire        receive_data_write,
  input  wire [63:0] encrypt_data_in,
  input  wire        encrypt_data_write,
  output wire [63:0] state_out,
  output wire [79:0] key_out,
  output wire [63:0] transmit_data_out,
  output wire [63:0] receive_data_out
);
  localparam [63:0] STATE_ADDR = 64'h0000_0000_0000_0000;
  localparam [63:0] KEY_ADDR   = 64'h0000_0000_0000_0008;
  localparam [63:0] TX_ADDR    = 64'h0000_0000_0000_0010;
  localparam [63:0] RX_ADDR    = 64'h0000_0000_0000_0018;
  localparam [63:0] KEY_TAIL_ADDR = 64'h0000_0000_0000_0020;

  reg [63:0] state_reg;
  reg [79:0] key_reg;
  reg [63:0] transmit_data_reg;
  reg [63:0] receive_data_reg;

  wire state_sel = addr_bus == STATE_ADDR;
  wire key_sel = addr_bus == KEY_ADDR;
  wire tx_sel = addr_bus == TX_ADDR;
  wire rx_sel = addr_bus == RX_ADDR;
  wire key_tail_sel = addr_bus == KEY_TAIL_ADDR;
  wire do_write = write_en && !read_en;

  reg [63:0] read_data;

  always @(*) begin
    case (1'b1)
      state_sel: read_data = state_reg;
      key_sel: read_data = key_reg[79:16];
      tx_sel: read_data = transmit_data_reg;
      rx_sel: read_data = receive_data_reg;
      key_tail_sel: read_data = {48'b0, key_reg[15:0]};
      default: read_data = 64'b0;
    endcase
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_reg <= 64'b0;
      key_reg <= 80'b0;
      transmit_data_reg <= 64'b0;
      receive_data_reg <= 64'b0;
    end else begin
      if (receive_data_write) begin
        receive_data_reg <= receive_data_in;
      end

      if (encrypt_data_write) begin
        transmit_data_reg <= encrypt_data_in;
      end

      if (do_write) begin
        if (state_sel) begin
          state_reg <= data_bus;
        end else if (key_sel) begin
          key_reg[79:16] <= data_bus;
        end else if (tx_sel) begin
          transmit_data_reg <= data_bus;
        end else if (rx_sel) begin
          receive_data_reg <= data_bus;
        end else if (key_tail_sel) begin
          key_reg[15:0] <= data_bus[15:0];
        end
      end
    end
  end

  assign data_bus = read_en ? read_data : 64'bz;
  assign state_out = state_reg;
  assign key_out = key_reg;
  assign transmit_data_out = transmit_data_reg;
  assign receive_data_out = receive_data_reg;
endmodule
