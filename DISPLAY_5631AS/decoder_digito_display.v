// RECEBE NÚMERO (0 À 9) E DEVOLVE 8 SEGMENTOS
module decoder_digito_display(
    // ENTRADAS
    input wire [3:0] numero,

    // SAÍDAS a_b_c_d_e_f_g_ponto
    output reg [7:0] segmentos
);

    always @(numero)
        begin
            case (numero)
                4'd0:
                    segmentos = 8'b1111_1100;
                4'd1:
                    segmentos = 8'b0110_0000;
                4'd2:
                    segmentos = 8'b1101_1010;
                4'd3:
                    segmentos = 8'b1111_0010;
                4'd4:
                    segmentos = 8'b0110_0110;
                4'd5:
                    segmentos = 8'b1011_0110;
                4'd6:
                    segmentos = 8'b1011_1110;
                4'd7:
                    segmentos = 8'b1110_0000;
                4'd8:
                    segmentos = 8'b1111_1110;
                4'd9:
                    segmentos = 8'b1111_0110;
                default:
                    segmentos = 8'b1111_1100;

            endcase
        end

endmodule