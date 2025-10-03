`timescale 1ns/1ps

// temperature_to_uart — envia 3 bytes via UART no formato:
//   [0] SENSOR_ADDR (ex.: 0x00)
//   [1] LSB de temperatura
//   [2] MSB de temperatura
// Estilo enxuto com 4 estados: ST_LOAD -> ST_START -> ST_WAIT -> ST_DONE.
// Usa espera por tempo fixo (FRAME_CLKS) para cada quadro 8N1.
module temperature_to_uart #(
    parameter integer FREQUENCIA_FPGA = 25_000_000,  // ex.: 25 MHz
    parameter integer BAUD            = 115_200,
    parameter [7:0]  SENSOR_ADDR      = 8'hF0        // endereço deste sensor
)(
    input  wire        clk,
    input  wire        reset_n,        // reset síncrono, ativo-baixo
    input  wire        start,          // pulso para disparar o envio (borda de subida)
    input  wire [15:0] temperatura,  // ex.: 256 => 25.6°C
    output wire        tx              // saída UART TX
);
  // ---------------- Clocks por bit e duração do quadro (8N1 = 10 bits) ----------------
  localparam integer CLKS_PER_BIT = (FREQUENCIA_FPGA + (BAUD/2)) / BAUD;
  localparam integer FRAME_CLKS   = CLKS_PER_BIT * 10;

  // ---------------- Edge detect de 'start' (borda de subida) ----------------
  reg start_d;
  always @(posedge clk) begin
    if (!reset_n) start_d <= 1'b0;
    else          start_d <= start;
  end
  wire start_rise = start & ~start_d;

  // ---------------- Snapshot da temperatura e fatiamento ----------------
  reg [15:0] snap;
  wire [7:0] LSB = snap[7:0];
  wire [7:0] MSB = snap[15:8];

  // ---------------- Instância do seu UART TX ----------------
  reg  [7:0] data_reg  = 8'h00;  // byte atual para o TX
  reg        start_reg = 1'b0;   // pulso de 1 ciclo para o TX

  // (saídas não usadas; síntese otimiza se não forem necessárias)
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
    .active  (active_sig),
    .done    (done_sig),
    .tx      (tx)
  );

  // ---------------- FSM: 4 estados ----------------
  localparam [1:0]
    ST_LOAD  = 2'd0,
    ST_START = 2'd1,
    ST_WAIT  = 2'd2,
    ST_DONE  = 2'd3;

  // idx percorre os 3 bytes: 0=ADDR, 1=LSB, 2=MSB
  reg [1:0]  state = ST_LOAD;
  reg [1:0]  idx   = 2'd0;
  reg [31:0] cnt   = 32'd0;

  always @(posedge clk) begin
    if (!reset_n) begin
      state     <= ST_LOAD;
      idx       <= 2'd0;
      cnt       <= 32'd0;
      data_reg  <= 8'h00;
      start_reg <= 1'b0;
      snap      <= 16'h0000;
    end else begin
      // padrão: não iniciar nova transmissão (pulso de 1 ciclo em ST_START)
      start_reg <= 1'b0;

      case (state)
        // Escolhe o byte a enviar: ADDR, LSB, MSB
        ST_LOAD: begin
          // só inicia um novo trio quando houver start_rise; bytes seguintes continuam sem novo start
          if (start_rise || idx != 2'd0) begin
            if (idx == 2'd0) begin
              // primeiro byte do trio: captura leitura estável
              snap     <= temperatura;
              data_reg <= SENSOR_ADDR;
            end else if (idx == 2'd1) begin
              data_reg <= LSB;
            end else begin // idx == 2'd2
              data_reg <= MSB;
            end
            state <= ST_START;
          end
        end

        // Dispara a transmissão (pulso de 1 ciclo) e zera contador
        ST_START: begin
          start_reg <= 1'b1;
          cnt       <= 32'd0;
          state     <= ST_WAIT;
        end

        // Espera o tempo fixo de 1 quadro 8N1 (10 bits)
        ST_WAIT: begin
          if (cnt < FRAME_CLKS-1) begin
            cnt <= cnt + 1'b1;
          end else begin
            if (idx < 2) begin
              idx   <= idx + 1'b1;  // próximo byte
              state <= ST_LOAD;
            end else begin
              idx   <= 2'd0;        // pronto para próximo trio
              state <= ST_DONE;     // encerra ciclo atual
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
