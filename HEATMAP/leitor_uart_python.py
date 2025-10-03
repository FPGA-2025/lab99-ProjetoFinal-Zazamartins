import serial

PORT = "COM4" 
BAUD = 115200

ADDR2IDX = {0xF0: 0, 0xF1: 1, 0xF2: 2, 0xF3: 3}  # F0..F3 -> sensor0..3

with serial.Serial(PORT, BAUD, timeout=0.1) as ser:
    print(f"Lendo {PORT} @ {BAUD} (Ctrl+C para sair)")
    state = 0           # 0: espera ADDR, 1: LSB, 2: MSB
    addr = 0
    lsb = 0

    # últimos valores (°C) e máscara de quais sensores já foram atualizados
    last_c = [None, None, None, None]
    updated_mask = 0

    try:
        while True:
            data = ser.read(256)
            for b in data:
                if state == 0:
                    if b in ADDR2IDX:
                        addr = b
                        state = 1
                    # senão ignora byte lixo
                elif state == 1:
                    lsb = b
                    state = 2
                elif state == 2:
                    msb = b
                    # junta little-endian
                    raw = lsb | (msb << 8)
                    # trata negativos (se seu FPGA enviar signed 16-bit em décimos °C)
                    if raw & 0x8000:
                        raw -= 0x10000
                    temp_c = raw / 10.0

                    idx = ADDR2IDX[addr]
                    last_c[idx] = temp_c
                    updated_mask |= (1 << idx)

                    # (opcional) descomente para ver cada frame individual:
                    # print(f"frame: sensor{idx} (addr=0x{addr:02X}) -> {temp_c:.1f} °C (raw={raw})")

                    # quando tiver os 4 atualizados, imprime linha consolidada e zera a máscara
                    if updated_mask == 0b1111:
                        s0 = f"{last_c[0]:.1f}°C" if last_c[0] is not None else "--"
                        s1 = f"{last_c[1]:.1f}°C" if last_c[1] is not None else "--"
                        s2 = f"{last_c[2]:.1f}°C" if last_c[2] is not None else "--"
                        s3 = f"{last_c[3]:.1f}°C" if last_c[3] is not None else "--"
                        print(f"S0={s0} | S1={s1} | S2={s2} | S3={s3}")
                        updated_mask = 0

                    state = 0  # volta a procurar próximo ADDR
    except KeyboardInterrupt:
        print("\nEncerrando.")
