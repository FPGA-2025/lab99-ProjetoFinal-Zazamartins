// GERA PULSO START PARA UART ENVIAR DADOS
module start_uart_ds18b20(
    // ENTRADAS
    input wire clk, 
    input wire reset_n,

    // SAÍDAS
    output reg start
);

    parameter integer FREQUENCIA_FPGA = 25_000_000;
    // CONTADOR 
    localparam integer TEMPO_PULSO = (FREQUENCIA_FPGA / 4); // Um pulso de start a cada 1/4 segundo
    localparam integer width = $clog2(TEMPO_PULSO); 
    reg [width -1:0] count;

    always @(posedge clk)
        begin
            if (!reset_n)
                begin
                    count <= 0;
                    start <= 1'b0;
                end
            else
                begin
                    if (count == TEMPO_PULSO - 1)
                        begin
                            count <= 0;
                            start <= 1'b1;
                        end
                    else
                        begin
                            count <= count + 1;
                            start <= 1'b0;
                        end
                end
        end
endmodule