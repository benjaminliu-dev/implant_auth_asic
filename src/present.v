`default_nettype none

module present80_encrypt (
  input  wire        clk,
  input  wire        rst_n,
  input  wire        start,
  input  wire [63:0] plaintext,
  input  wire [79:0] key,
  output reg  [63:0] ciphertext,
  output wire        busy,
  output reg         done
);
  reg [63:0] state_reg;
  reg [79:0] key_reg;
  reg [4:0] round_counter;
  reg active;

  wire [63:0] round_key;
  wire [79:0] next_key;
  wire [63:0] add_round_key_state;
  wire [63:0] sbox_state;
  wire [63:0] round_state;

  assign busy = active;
  assign add_round_key_state = state_reg ^ round_key;

  present80_key_update key_update_inst (
    .key_in(key_reg),
    .round_counter(round_counter),
    .round_key(round_key),
    .key_out(next_key)
  );

  present_sbox_layer sbox_layer_inst (
    .in(add_round_key_state),
    .out(sbox_state)
  );

  present_p_layer p_layer_inst (
    .in(sbox_state),
    .out(round_state)
  );

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_reg <= 64'b0;
      key_reg <= 80'b0;
      round_counter <= 5'd1;
      ciphertext <= 64'b0;
      active <= 1'b0;
      done <= 1'b0;
    end else begin
      done <= 1'b0;

      if (start && !active) begin
        state_reg <= plaintext;
        key_reg <= key;
        round_counter <= 5'd1;
        active <= 1'b1;
      end else if (active) begin
        if (round_counter == 5'd31) begin
          ciphertext <= round_state ^ next_key[79:16];
          state_reg <= round_state;
          key_reg <= next_key;
          round_counter <= 5'd1;
          active <= 1'b0;
          done <= 1'b1;
        end else begin
          state_reg <= round_state;
          key_reg <= next_key;
          round_counter <= round_counter + 5'd1;
        end
      end
    end
  end
endmodule
