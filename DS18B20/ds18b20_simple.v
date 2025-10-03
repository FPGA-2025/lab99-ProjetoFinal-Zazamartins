`timescale 1ns/1ps
// ds18b20_simple — leitor enxuto do DS18B20 (Verilog-2001)
// Entradas : clk (25 MHz), rst_n, dq (1-Wire com pull-up externo ~4.7k)
// Saída    : temperature_x10 (signed, décimos de °C: 253 => 25.3°C)

module ds18b20_simple #(
    parameter integer SYSCLK_HZ = 25_000_000, // 25 MHz por padrão
    parameter integer T_CONV_US = 750_000      // tempo máx. conversão (12 bits)
)(
    input  wire clk,
    input  wire rst_n,
    inout  wire dq,
    output reg  signed [15:0] temperature_x10
);

    // ========= Tick de 1 us =========
    localparam integer CYCLES_PER_US = (SYSCLK_HZ/1_000_000);

    reg [31:0] us_div;
    wire us_tick = (us_div == CYCLES_PER_US-1);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) us_div <= 32'd0;
        else        us_div <= us_tick ? 32'd0 : (us_div + 32'd1);
    end

    // ========= Open-drain no 1-Wire =========
    reg dq_oe;                 // 1: força LOW, 0: solta (pull-up leva a HIGH)
    assign dq = dq_oe ? 1'b0 : 1'bz;
    wire dq_in = dq;

    // ========= Tempos em microssegundos =========
    localparam integer T_RSTL       = 480;
    localparam integer T_PRESAMPLE  = 70;
    localparam integer T_SLOT       = 64;
    localparam integer T_W1L        = 6;
    localparam integer T_W0L        = 60;
    localparam integer T_RL         = 6;
    localparam integer T_R_SAMPLE   = 15;

    // ========= Estados (codificação simples) =========
    localparam [4:0]
        S_IDLE           = 5'd0,
        S_RESETL         = 5'd1,
        S_RESETH_WAIT    = 5'd2,
        S_PRESENCE_DONE  = 5'd3,
        S_W_SKIP         = 5'd4,
        S_W_CONVERT      = 5'd5,
        S_WAIT_CONV      = 5'd6,
        S_RESETL2        = 5'd7,
        S_RESETH2_WAIT   = 5'd8,
        S_PRESENCE2_DONE = 5'd9,
        S_W_SKIP2        = 5'd10,
        S_W_READSCR      = 5'd11,
        S_R_TEMPL        = 5'd12,
        S_R_TEMPH        = 5'd13,
        S_LATCH          = 5'd14;

    reg [4:0] state;

    // ========= Controles e dados =========
    reg [31:0] us_cnt;
    reg [7:0]  cur_byte;
    reg [2:0]  bit_idx;
    reg signed [15:0] temp_raw;
    reg signed [18:0] mult5;   // para multiplicar por 5 e depois >> 3

    // ========= Submáquina de slots =========
    localparam [1:0]
        SLOT_IDLE  = 2'd0,
        SLOT_WRITE = 2'd1,
        SLOT_READ  = 2'd2;

    reg [1:0]  slot_mode;
    reg [31:0] slot_us;
    reg        slot_bit;
    reg        rd_bit;

    // ========= Controle de byte =========
    reg        byte_busy;
    reg        byte_is_read;
    reg [7:0]  byte_acc;

    // --------- Tarefas (sintetizáveis) ---------
    task start_write_bit; input b; begin
        slot_mode <= SLOT_WRITE; slot_bit <= b; slot_us <= 32'd0; dq_oe <= 1'b1;
    end endtask

    task start_read_bit; begin
        slot_mode <= SLOT_READ; slot_us <= 32'd0; dq_oe <= 1'b1;
    end endtask

    task step_slot; begin
        if (slot_mode == SLOT_WRITE) begin
            if (slot_us == (slot_bit ? T_W1L : T_W0L)) dq_oe <= 1'b0; // solta
            if (slot_us >= T_SLOT) begin
                slot_mode <= SLOT_IDLE;
                dq_oe     <= 1'b0;
            end
            slot_us <= slot_us + 32'd1;
        end
        else if (slot_mode == SLOT_READ) begin
            if (slot_us == T_RL) dq_oe <= 1'b0;        // solta para o escravo
            if (slot_us == T_R_SAMPLE) rd_bit <= dq_in; // amostra
            if (slot_us >= T_SLOT) begin
                slot_mode <= SLOT_IDLE;
                dq_oe     <= 1'b0;
            end
            slot_us <= slot_us + 32'd1;
        end
    end endtask

    task start_write_byte; input [7:0] b; begin
        byte_acc     <= b;
        bit_idx      <= 3'd0;
        byte_is_read <= 1'b0;
        byte_busy    <= 1'b1;
        start_write_bit(b[0]);
    end endtask

    task start_read_byte; begin
        byte_acc     <= 8'd0;
        bit_idx      <= 3'd0;
        byte_is_read <= 1'b1;
        byte_busy    <= 1'b1;
        start_read_bit();
    end endtask

    task step_byte; begin
        if (slot_mode != SLOT_IDLE) begin
            step_slot();
        end else if (byte_busy) begin
            if (byte_is_read) byte_acc[bit_idx] <= rd_bit;
            if (bit_idx == 3'd7) begin
                byte_busy <= 1'b0;
            end else begin
                bit_idx <= bit_idx + 3'd1;
                if (byte_is_read) start_read_bit();
                else              start_write_bit(byte_acc[bit_idx+1]);
            end
        end
    end endtask

    // ========= FSM principal =========
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state           <= S_IDLE;
            dq_oe           <= 1'b0;
            us_cnt          <= 32'd0;
            slot_mode       <= SLOT_IDLE;
            slot_us         <= 32'd0;
            byte_busy       <= 1'b0;
            temperature_x10 <= 16'sd0;
            temp_raw        <= 16'sd0;
            mult5           <= 19'sd0;
        end else if (us_tick) begin
            // avança byte/slot a cada 1 us
            step_byte();

            case (state)
            S_IDLE: begin
                dq_oe  <= 1'b1;    // força reset LOW
                us_cnt <= 32'd0;
                state  <= S_RESETL;
            end

            S_RESETL: begin
                if (us_cnt >= T_RSTL) begin
                    dq_oe  <= 1'b0;       // solta
                    us_cnt <= 32'd0;
                    state  <= S_RESETH_WAIT;
                end else us_cnt <= us_cnt + 32'd1;
            end

            S_RESETH_WAIT: begin
                // Aqui poderíamos checar presença em ~70us (dq_in==0),
                // mas seguimos adiante após ~480us solto.
                if (us_cnt >= T_RSTL) begin
                    us_cnt <= 32'd0;
                    state  <= S_PRESENCE_DONE;
                end else us_cnt <= us_cnt + 32'd1;
            end

            S_PRESENCE_DONE: begin
                start_write_byte(8'hCC); // Skip ROM
                state <= S_W_SKIP;
            end

            S_W_SKIP: begin
                if (!byte_busy) begin
                    start_write_byte(8'h44); // Convert T
                    state <= S_W_CONVERT;
                end
            end

            S_W_CONVERT: begin
                if (!byte_busy) begin
                    us_cnt <= 32'd0;
                    state  <= S_WAIT_CONV;
                end
            end

            S_WAIT_CONV: begin
                if (us_cnt >= T_CONV_US) begin
                    dq_oe  <= 1'b1;       // novo reset
                    us_cnt <= 32'd0;
                    state  <= S_RESETL2;
                end else us_cnt <= us_cnt + 32'd1;
            end

            S_RESETL2: begin
                if (us_cnt >= T_RSTL) begin
                    dq_oe  <= 1'b0;
                    us_cnt <= 32'd0;
                    state  <= S_RESETH2_WAIT;
                end else us_cnt <= us_cnt + 32'd1;
            end

            S_RESETH2_WAIT: begin
                if (us_cnt >= T_RSTL) begin
                    us_cnt <= 32'd0;
                    state  <= S_PRESENCE2_DONE;
                end else us_cnt <= us_cnt + 32'd1;
            end

            S_PRESENCE2_DONE: begin
                start_write_byte(8'hCC); // Skip ROM
                state <= S_W_SKIP2;
            end

            S_W_SKIP2: begin
                if (!byte_busy) begin
                    start_write_byte(8'hBE); // Read Scratchpad
                    state <= S_W_READSCR;
                end
            end

            S_W_READSCR: begin
                if (!byte_busy) begin
                    start_read_byte();     // LSB
                    state <= S_R_TEMPL;
                end
            end

            S_R_TEMPL: begin
                if (!byte_busy) begin
                    temp_raw[7:0] <= byte_acc;
                    start_read_byte();     // MSB
                    state <= S_R_TEMPH;
                end
            end

            S_R_TEMPH: begin
                if (!byte_busy) begin
                    temp_raw[15:8] <= byte_acc;
                    state <= S_LATCH;
                end
            end

            S_LATCH: begin
                // temp_raw está em 1/16°C (signed).
                // Converter para 0.1°C ≈ (x * 10) / 16 = (x*5)>>3
                mult5 <= temp_raw * 5;            // signed * 5
                temperature_x10 <= mult5 >>> 3;   // divisão aritmética por 8
                state <= S_IDLE;                  // recomeça ciclo
            end

            default: state <= S_IDLE;
            endcase
        end
    end

endmodule
