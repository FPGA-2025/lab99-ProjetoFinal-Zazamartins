`timescale 1ns/1ps
///////////////////////////////////////////////////////////
// Module Name : clk_div
// Description : Gera clock ~204.8 kHz (≈ 5 us por slot) a partir de 25 MHz
//               Compatível “drop-in” com o projeto original.
//               25e6 / (2*(60+1)) ≈ 204.918 kHz
// Editor      : você + ChatGPT
// Time        : 2025-09-21
///////////////////////////////////////////////////////////

module clk_div
(
    input  wire clk_in,   // AGORA: 25 MHz
    input  wire rst_n,
    output reg  clk_out
);

    // Contador de meio-período (0..60) => 61 ciclos de 25 MHz
    reg [5:0] cnt;

    always @(posedge clk_in or negedge rst_n) begin
        if (!rst_n) begin
            cnt     <= 6'd0;
            clk_out <= 1'b0;
        end else begin
            if (cnt == 6'd60) begin
                clk_out <= ~clk_out;
                cnt     <= 6'd0;
            end else begin
                cnt <= cnt + 6'd1;
            end
        end
    end

endmodule
