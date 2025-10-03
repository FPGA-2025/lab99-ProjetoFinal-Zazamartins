module display_3digitos(
    input wire clk,
    input wire [15:0] numero,
    output reg [0:10] array_display // a_b_c_d_e_f_g_ponto_dig1_dig2_dig3 CONTAGEM ESQUERDA -> DIREITA
);

    // SLOW CLOCCK
    wire slow_clk;
    divisor_clock divisor_clock_display(.clk(clk), .slow_clk(slow_clk));

    // SINAIS INTERNOS PARA OS DÍGITOS // NÚMERO 252 = 25.2 °C
    wire [3:0] digito1, digito2, digito3;
    assign digito1 = (numero / 100);
    assign digito2 = (numero % 100) / 10;
    assign digito3 = (numero % 10);

    // CONTROLE DOS SEGMENTOS
    wire [0:7] segmentos_digito1, segmentos_digito2, segmentos_digito3;

    decoder_digito_display dec1(.numero(digito1), .segmentos(segmentos_digito1));
    decoder_digito_display dec2(.numero(digito2), .segmentos(segmentos_digito2));
    decoder_digito_display dec3(.numero(digito3), .segmentos(segmentos_digito3));

    // MÁQUINA DE ESTADOS
    reg [1:0] estado_atual, proximo_estado;

    localparam DIGITO_1 = 2'b00,
               DIGITO_2 = 2'b01,
               DIGITO_3 = 2'b10;
    
    initial estado_atual = DIGITO_1;

    // LÓGICA SEQUENCIAL
    always @(posedge slow_clk)
        begin
            estado_atual <= proximo_estado;
        end
    
    // LÓGICA COMBINACIONAL
    always @(*)
        begin
            // defaults: evitam latch e loops
            proximo_estado     = estado_atual;
            array_display      = 11'b0;   // zera todos os 11 bits
            array_display[8]   = 1'b1;    // D1 desativado (ativo-baixo)
            array_display[9]   = 1'b1;    // D2 desativado
            array_display[10]  = 1'b1;    // D3 desativado

            case (estado_atual)
                DIGITO_1:
                    begin
                        // DÍGITO 1, 2, 3
                        array_display[8] = 1'b0;
                        array_display[9] = 1'b1;
                        array_display[10] = 1'b1;
                        array_display[0:7] = segmentos_digito1;
                        proximo_estado = DIGITO_2;
                    end
                DIGITO_2:
                    begin
                        // DÍGITO 1, 2, 3
                        array_display[8] = 1'b1;
                        array_display[9] = 1'b0;
                        array_display[10] = 1'b1;
                        array_display[0:7] = segmentos_digito2;
                        array_display[7] = 1'b1; // SOBRESCREVE PARA O PONTO APARECER AQUI
                        proximo_estado = DIGITO_3;
                    end
                DIGITO_3:
                    begin
                        // DÍGITO 1, 2, 3
                        array_display[8] = 1'b1;
                        array_display[9] = 1'b1;
                        array_display[10] = 1'b0;
                        array_display[0:7] = segmentos_digito3;
                        proximo_estado = DIGITO_1;
                    end
                default:
                    proximo_estado = DIGITO_1;
                    
            endcase
        end



endmodule