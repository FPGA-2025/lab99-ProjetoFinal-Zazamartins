`timescale 1ns/1ps

// Envia em um único TX os dados de 4 sensores, por start (ex.: 1 Hz ou 0,25 s):
// Frame de 12 bytes no formato:
// [F0, LSB0, MSB0,  F1, LSB1, MSB1,  F2, LSB2, MSB2,  F3, LSB3, MSB3]
module multi_temperature_uart_4sensors #(
    parameter integer FREQUENCIA_FPGA = 25_000_000,  // ex.: 25 MHz
    parameter integer BAUD            = 115_200,
    parameter [7:0]  SENSOR0_ADDR     = 8'hF0,
    parameter [7:0]  SENSOR1_ADDR     = 8'hF1,
    parameter [7:0]  SENSOR2_ADDR     = 8'hF2,
    parameter [7:0]  SENSOR3_ADDR     = 8'hF3
)(
    input  wire        clk,
    input  wire        reset_n,       // reset síncrono, ativo-baixo
    input  wire        start,         // pulso para disparar o envio do frame
    input  wire [15:0] temperatura_0, // sensor 0
    input  wire [15:0] temperatura_1, // sensor 1
    input  wire [15:0] temperatura_2, // sensor 2
    input  wire [15:0] temperatura_3, // sensor 3
    output wire        tx             // UART TX único
);
  // --------- Timing UART (8N1 = 10 bits) ----------
  localparam integer CLKS_PER_BIT = (FREQUENCIA_FPGA + (BAUD/2)) / BAUD;
  localparam integer FRAME_CLKS   = CLKS_PER_BIT * 10;

  // --------- Edge detect de 'start' ----------
  reg start_d;
  always @(posedge clk) begin
    if (!reset_n) start_d <= 1'b0;
    else          start_d <= start;
  end
  wire start_rise = start & ~start_d;

  // --------- Snapshot das temperaturas ----------
  reg [15:0] snap0, snap1, snap2, snap3;
  wire [7:0] LSB0 = snap0[7:0];
  wire [7:0] MSB0 = snap0[15:8];
  wire [7:0] LSB1 = snap1[7:0];
  wire [7:0] MSB1 = snap1[15:8];
  wire [7:0] LSB2 = snap2[7:0];
  wire [7:0] MSB2 = snap2[15:8];
  wire [7:0] LSB3 = snap3[7:0];
  wire [7:0] MSB3 = snap3[15:8];

  // --------- UART TX (seu transmissor) ----------
  reg  [7:0] data_reg  = 8'h00;  // byte atual
  reg        start_reg = 1'b0;   // pulso 1 ciclo para TX
  wire       active_sig;
  wire       done_sig;

  uart_transmitter #(
    .BAUD(BAUD),
    .FREQUENCIA_FPGA(FREQUENCIA_FPGA)
  ) u_tx (
    .clk     (clk),
    .start   (start_reg),
    .data    (data_reg),
    .reset_n (reset_n),
    .active  (active_sig),   // não usado aqui
    .done    (done_sig),     // não usado aqui
    .tx      (tx)
  );

  // --------- FSM 4 estados ----------
  localparam [1:0]
    ST_LOAD  = 2'd0,
    ST_START = 2'd1,
    ST_WAIT  = 2'd2,
    ST_DONE  = 2'd3;

  // idx_byte: 0..11 => F0,LSB0,MSB0,  F1,LSB1,MSB1,  F2,LSB2,MSB2,  F3,LSB3,MSB3
  reg [1:0] state    = ST_LOAD;
  reg [3:0] idx_byte = 4'd0;      // 0..11
  reg [31:0] cnt     = 32'd0;

  always @(posedge clk) begin
    if (!reset_n) begin
      state     <= ST_LOAD;
      idx_byte  <= 4'd0;
      cnt       <= 32'd0;
      data_reg  <= 8'h00;
      start_reg <= 1'b0;
      snap0     <= 16'h0000;
      snap1     <= 16'h0000;
      snap2     <= 16'h0000;
      snap3     <= 16'h0000;
    end else begin
      // padrão: não iniciar nova transmissão (pulso de 1 ciclo em ST_START)
      start_reg <= 1'b0;

      case (state)
        // Escolhe o byte a enviar (primeiro espera start_rise; os demais seguem)
        ST_LOAD: begin
          if (idx_byte == 4'd0) begin
            if (start_rise) begin
              // tira snapshot de todos no início do frame
              snap0    <= temperatura_0;
              snap1    <= temperatura_1;
              snap2    <= temperatura_2;
              snap3    <= temperatura_3;
              data_reg <= SENSOR0_ADDR;     // byte 0
              state    <= ST_START;
            end
          end else begin
            // bytes subsequentes (1..11)
            case (idx_byte)
              4'd1:  data_reg <= LSB0;
              4'd2:  data_reg <= MSB0;
              4'd3:  data_reg <= SENSOR1_ADDR;
              4'd4:  data_reg <= LSB1;
              4'd5:  data_reg <= MSB1;
              4'd6:  data_reg <= SENSOR2_ADDR;
              4'd7:  data_reg <= LSB2;
              4'd8:  data_reg <= MSB2;
              4'd9:  data_reg <= SENSOR3_ADDR;
              4'd10: data_reg <= LSB3;
              default: data_reg <= MSB3;    // 4'd11
            endcase
            state <= ST_START;
          end
        end

        // Dispara a transmissão (pulso de 1 ciclo) e zera contador
        ST_START: begin
          start_reg <= 1'b1;
          cnt       <= 32'd0;
          state     <= ST_WAIT;
        end

        // Espera o tempo fixo de 1 quadro 8N1
        ST_WAIT: begin
          if (cnt < FRAME_CLKS-1) begin
            cnt <= cnt + 1'b1;
          end else begin
            if (idx_byte < 4'd11) begin
              idx_byte <= idx_byte + 1'b1;
              state    <= ST_LOAD;
            end else begin
              idx_byte <= 4'd0;      // pronto p/ próximo frame (próximo start)
              state    <= ST_DONE;
            end
          end
        end

        // Ocioso até próximo start_rise
        ST_DONE: begin
          if (start_rise)
            state <= ST_LOAD;
        end

        default: state <= ST_LOAD;
      endcase
    end
  end
endmodule
