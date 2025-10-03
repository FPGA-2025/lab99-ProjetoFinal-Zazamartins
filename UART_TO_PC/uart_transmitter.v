`timescale 1ns/1ps

module uart_transmitter(
    // ENTRADAS
    input  wire       clk,
    input  wire       start,     // ideal: pulso de 1 ciclo
    input  wire [7:0] data,
    input  wire       reset_n,   // reset síncrono, ativo-BAIXO

    // SAÍDAS
    output wire       active,
    output wire       done,
    output reg        tx
);
    // PARÂMETROS
    parameter integer BAUD            = 115_200;
    parameter integer FREQUENCIA_FPGA = 25_000_000; // 25 MHz

    // CLKS POR BIT (arredondado p/ inteiro mais próximo)
    localparam integer CLKS_PER_BIT = (FREQUENCIA_FPGA + (BAUD/2)) / BAUD;

    // Largura do contador (mínimo 1)
    localparam integer tamanho_minimo = (CLKS_PER_BIT <= 1) ? 1 : $clog2(CLKS_PER_BIT);

    // REGISTRADORES
    reg [tamanho_minimo-1:0] reg_clock_count = {tamanho_minimo{1'b0}};
    reg [7:0]                reg_data        = 8'd0;
    reg [2:0]                bit_idx         = 3'd0;
    reg                      reg_active      = 1'b0;
    reg                      reg_done        = 1'b0;

    assign active = reg_active;
    assign done   = reg_done;

    // FSM
    reg [1:0] state = 2'b00;
    localparam IDLE      = 2'b00;
    localparam START     = 2'b01;
    localparam DATA_BITS = 2'b10;
    localparam STOP      = 2'b11;

    // (Opcional) Detector de borda de subida para 'start'
    reg start_d = 1'b0;
    wire start_rise = start & ~start_d;

    always @(posedge clk) begin
        if (!reset_n) begin
            tx              <= 1'b1;   // linha idle = alta
            reg_clock_count <= {tamanho_minimo{1'b0}};
            reg_data        <= 8'd0;
            bit_idx         <= 3'd0;
            reg_active      <= 1'b0;
            reg_done        <= 1'b0;
            state           <= IDLE;
            start_d         <= 1'b0;
        end else begin
            // atualiza histórico do start (p/ edge detector)
            start_d <= start;

            // 'done' é pulso de 1 ciclo: zera a cada clock
            reg_done <= 1'b0;

            case (state)
                // ---------------- IDLE ----------------
                IDLE: begin
                    tx              <= 1'b1;   // nível de repouso
                    reg_active      <= 1'b0;
                    reg_clock_count <= {tamanho_minimo{1'b0}};
                    bit_idx         <= 3'd0;

                    // Início da transmissão
                    if (start_rise) begin
                        reg_data   <= data;    // latch do byte
                        reg_active <= 1'b1;
                        state      <= START;
                    end
                end

                // --------------- START ----------------
                START: begin
                    tx <= 1'b0; // start bit = 0

                    if (reg_clock_count < CLKS_PER_BIT-1) begin
                        reg_clock_count <= reg_clock_count + 1'b1;
                    end else begin
                        reg_clock_count <= {tamanho_minimo{1'b0}};
                        state           <= DATA_BITS;
                    end
                end

                // ------------- DATA_BITS --------------
                DATA_BITS: begin
                    tx <= reg_data[bit_idx]; // LSB-first

                    if (reg_clock_count < CLKS_PER_BIT-1) begin
                        reg_clock_count <= reg_clock_count + 1'b1;
                    end else begin
                        reg_clock_count <= {tamanho_minimo{1'b0}};
                        if (bit_idx < 3'd7) begin
                            bit_idx <= bit_idx + 1'b1;
                        end else begin
                            bit_idx <= 3'd0;
                            state   <= STOP;
                        end
                    end
                end

                // ---------------- STOP ----------------
                STOP: begin
                    tx <= 1'b1; // stop bit = 1

                    if (reg_clock_count < CLKS_PER_BIT-1) begin
                        reg_clock_count <= reg_clock_count + 1'b1;
                    end else begin
                        reg_clock_count <= {tamanho_minimo{1'b0}};
                        reg_active      <= 1'b0;
                        reg_done        <= 1'b1;  // pulso
                        state           <= IDLE;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end
endmodule
