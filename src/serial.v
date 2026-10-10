`default_nettype none

module serial (
  input  wire        clk,
  input  wire        rst_n,
  input  wire        start,
  input  wire        sdi,
  input  wire [63:0] transmit_data,
  output wire        sdo,
  output reg  [63:0] receive_data,
  output reg         receive_data_valid,
  output wire        busy,
  output wire        done
);
  reg [63:0] tx_shift;
  reg [63:0] rx_shift;
  reg [6:0] bit_count;
  reg active;

  assign sdo = active ? tx_shift[63] : 1'b0;
  assign busy = active;
  assign done = receive_data_valid;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      tx_shift <= 64'b0;
      rx_shift <= 64'b0;
      receive_data <= 64'b0;
      receive_data_valid <= 1'b0;
      bit_count <= 7'b0;
      active <= 1'b0;
    end else begin
      receive_data_valid <= 1'b0;

      if (start && !active) begin
        tx_shift <= transmit_data;
        rx_shift <= 64'b0;
        bit_count <= 7'b0;
        active <= 1'b1;
      end else if (active) begin
        tx_shift <= {tx_shift[62:0], 1'b0};
        rx_shift <= {rx_shift[62:0], sdi};

        if (bit_count == 7'd63) begin
          receive_data <= {rx_shift[62:0], sdi};
          receive_data_valid <= 1'b1;
          active <= 1'b0;
          bit_count <= 7'b0;
        end else begin
          bit_count <= bit_count + 7'b1;
        end
      end
    end
  end
endmodule
