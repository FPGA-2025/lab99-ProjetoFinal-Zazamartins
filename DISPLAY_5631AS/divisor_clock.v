module divisor_clock#(
    parameter integer INPUT_FREQ_HZ = 25_000_000,
    parameter integer SLOW_HZ       = 180
)(
    input  wire clk,
    output reg  slow_clk = 1'b0
);
    // toggle a cada DIV ciclos do clk
    localparam integer DIV = (INPUT_FREQ_HZ/(2*SLOW_HZ)) > 0 ? (INPUT_FREQ_HZ/(2*SLOW_HZ)) : 1;
    localparam integer W   = (DIV > 1) ? $clog2(DIV) : 1;

    reg [W-1:0] contador = {W{1'b0}};

    always @(posedge clk) begin
        if (contador == DIV-1) begin
            contador <= 0;
            slow_clk <= ~slow_clk;
        end else begin
            contador <= contador + 1'b1;
        end
    end
endmodule

// INSTANCIANDO
// divisor_clock #(
//     .INPUT_FREQ_HZ(25_000_000),
//     .SLOW_HZ      (60)
// ) nome_modulo (
//     .clk(clk),
//     .slow_clk(slow_clk)
// );
