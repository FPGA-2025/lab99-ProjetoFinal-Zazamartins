`timescale 1ns/1ps
module top_module(
    // ENTRADAS
    input  wire clk,
    input  wire reset_n,                // ativo-baixo
    inout  wire wire_data_ds18b20_0,    // DQ sensor 0 (pull-up ~4.7k a 3V3)
    inout  wire wire_data_ds18b20_1,    // DQ sensor 1
    inout  wire wire_data_ds18b20_2,    // DQ sensor 2
    inout  wire wire_data_ds18b20_3,    // DQ sensor 3

    // SAÍDAS
    output wire [0:43] array_display,   // mostra sensor 0 por enquanto
    output wire        tx               // UART TX único
);
    // ======================
    // DS18B20 (décimos °C)
    // ======================
    wire [15:0] temperatura_0;
    wire [15:0] temperatura_1;
    wire [15:0] temperatura_2;
    wire [15:0] temperatura_3;

    ds18b20_simple ds18b20_0(
        .clk(clk),
        .rst_n(reset_n),
        .dq(wire_data_ds18b20_0),
        .temperature_x10(temperatura_0)
    );

    ds18b20_simple ds18b20_1(
        .clk(clk),
        .rst_n(reset_n),
        .dq(wire_data_ds18b20_1),
        .temperature_x10(temperatura_1)
    );

    ds18b20_simple ds18b20_2(
        .clk(clk),
        .rst_n(reset_n),
        .dq(wire_data_ds18b20_2),
        .temperature_x10(temperatura_2)
    );

    ds18b20_simple ds18b20_3(
        .clk(clk),
        .rst_n(reset_n),
        .dq(wire_data_ds18b20_3),
        .temperature_x10(temperatura_3)
    );

    // ======================
    // DISPLAYS
    // ======================
    display_3digitos d0(
        .clk(clk),
        .numero(temperatura_0),
        .array_display(array_display[0:10])
    );

    display_3digitos d1(
        .clk(clk),
        .numero(temperatura_1),
        .array_display(array_display[11:21])
    );

    display_3digitos d2(
        .clk(clk),
        .numero(temperatura_2),
        .array_display(array_display[22:32])
    );
    display_3digitos d3(
        .clk(clk),
        .numero(temperatura_3),
        .array_display(array_display[33:43])
    );



    // ======================
    // PULSO START (mantive o seu gerador de 0,25 s)
    // ======================
    wire start_tx;
    start_uart_ds18b20 GEN (
        .clk(clk),
        .reset_n(reset_n),
        .start(start_tx)
    );
    // Se quiser 1 segundo, troque por start_pulse_1s com .FREQ_HZ(25_000_000).

    // ======================
    // MUX de 4 sensores para 1 UART
    // ======================
    multi_temperature_uart_4sensors #(
        .FREQUENCIA_FPGA(25_000_000),
        .BAUD(115_200),
        .SENSOR0_ADDR(8'hF0),
        .SENSOR1_ADDR(8'hF1),
        .SENSOR2_ADDR(8'hF2),
        .SENSOR3_ADDR(8'hF3)
    ) MUXTX (
        .clk(clk),
        .reset_n(reset_n),
        .start(start_tx),
        .temperatura_0(temperatura_0),
        .temperatura_1(temperatura_1),
        .temperatura_2(temperatura_2),
        .temperatura_3(temperatura_3),
        .tx(tx)
    );
endmodule
