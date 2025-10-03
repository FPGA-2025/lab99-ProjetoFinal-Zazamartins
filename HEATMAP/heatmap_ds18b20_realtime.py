"""
heatmap_ds18b20_realtime.py
---------------------------
Visualiza em tempo real um "mapa térmico" 2x2 usando 4 sensores DS18B20 nas bordas
de um retângulo, a partir de frames enviados pela UART:
  Frame = ADDR (F0..F3) + LSB + MSB (little-endian), em décimos de °C.

Posicionamento (coordenadas normalizadas em [0,1]x[0,1]):
    (0,1) S1 (F1)  -----  S2 (F2) (1,1)
           |                   |
           |     ÁREA          |
           |   MONITORADA      |
    (0,0) S0 (F0)  -----  S3 (F3) (1,0)

Interpolação: bilinear simples entre os quatro cantos.
Smoothing: média móvel exponencial (EMA) por sensor para reduzir tremulação.

Requisitos:
  pip install pyserial numpy matplotlib

Execução (exemplo):
  python heatmap_ds18b20_realtime.py --port COM4 --baud 115200 --alpha 0.3 --grid 80 --interval 100
  # Color scale fixa (melhor p/ alarme/incêndio, ex.: 15-60 °C)
  python heatmap_ds18b20_realtime.py --port COM4 --fixed 15 60
"""

import sys
import time
import argparse
import threading
import numpy as np
import matplotlib.pyplot as plt

ADDR2IDX = {0xF0: 0, 0xF1: 1, 0xF2: 2, 0xF3: 3}
# mapping para posições no retângulo (x,y)
S_POS = np.array([
    [0.0, 0.0],  # S0 (F0) bottom-left
    [0.0, 1.0],  # S1 (F1) top-left
    [1.0, 1.0],  # S2 (F2) top-right
    [1.0, 0.0],  # S3 (F3) bottom-right
], dtype=float)

def parse_args():
    ap = argparse.ArgumentParser(description="Heatmap 2x2 em tempo real para 4x DS18B20 via UART.")
    ap.add_argument("--port", required=True, help="Porta serial (ex.: COM4, /dev/ttyUSB0)")
    ap.add_argument("--baud", type=int, default=115200, help="Baud rate (padrão: 115200)")
    ap.add_argument("--grid", type=int, default=80, help="Resolução do grid de interpolação (padrão: 80)")
    ap.add_argument("--interval", type=int, default=100, help="Intervalo de atualização em ms (padrão: 100)")
    ap.add_argument("--alpha", type=float, default=0.3, help="EMA alpha (0..1), maior = responde mais rápido (padrão: 0.3)")
    ap.add_argument("--fixed", nargs=2, type=float, metavar=("VMIN","VMAX"),
                    help="Faixa fixa de temperatura (°C). Ex.: --fixed 15 60")
    ap.add_argument("--title", type=str, default="Mapa térmico - 4x DS18B20 (bilinear)",
                    help="Título do gráfico")
    return ap.parse_args()

class SerialReader(threading.Thread):
    def __init__(self, port, baud, on_value):
        super().__init__(daemon=True)
        self.port = port
        self.baud = baud
        self.on_value = on_value
        self._stop = threading.Event()

    def run(self):
        try:
            import serial
        except Exception as e:
            print("ERRO: pyserial não instalado. pip install pyserial", file=sys.stderr)
            return
        try:
            ser = serial.Serial(self.port, self.baud, timeout=0.1)
        except Exception as e:
            print(f"Falha ao abrir {self.port}: {e}", file=sys.stderr)
            return

        state = 0
        addr = 0
        lsb = 0
        try:
            while not self._stop.is_set():
                data = ser.read(256)
                for b in data:
                    if state == 0:
                        if b in ADDR2IDX:
                            addr = b
                            state = 1
                    elif state == 1:
                        lsb = b
                        state = 2
                    elif state == 2:
                        msb = b
                        raw = lsb | (msb << 8)
                        if raw & 0x8000:
                            raw -= 0x10000
                        temp_c = raw / 10.0
                        self.on_value(ADDR2IDX[addr], temp_c)
                        state = 0
        finally:
            try:
                ser.close()
            except Exception:
                pass

    def stop(self):
        self._stop.set()

def bilinear_grid(vals, n):
    """Gera grade NxN pela interpolação bilinear dos 4 cantos (S0,S1,S2,S3)."""
    # vals: [S0, S1, S2, S3]
    T00 = vals[0]  # (0,0)
    T01 = vals[1]  # (0,1)
    T11 = vals[2]  # (1,1)
    T10 = vals[3]  # (1,0)
    xs = np.linspace(0, 1, n)
    ys = np.linspace(0, 1, n)
    X, Y = np.meshgrid(xs, ys)
    # bilinear: (1-x)(1-y)T00 + x(1-y)T10 + (1-x)yT01 + xyT11
    G = (1 - X) * (1 - Y) * T00 + X * (1 - Y) * T10 + (1 - X) * Y * T01 + X * Y * T11
    return G

def main():
    args = parse_args()

    # estados compartilhados
    ema = [np.nan, np.nan, np.nan, np.nan]
    lock = threading.Lock()

    def on_value(idx, temp_c):
        nonlocal ema
        with lock:
            if np.isnan(ema[idx]):
                ema[idx] = temp_c
            else:
                ema[idx] = args.alpha * temp_c + (1 - args.alpha) * ema[idx]

    # inicia leitura serial em thread
    reader = SerialReader(args.port, args.baud, on_value)
    reader.start()

    # prepara figure
    n = args.grid
    fig, ax = plt.subplots(figsize=(6, 5), dpi=100)
    ax.set_title(args.title)
    ax.set_xlim(0, 1)
    ax.set_ylim(0, 1)
    ax.set_xlabel("x")
    ax.set_ylabel("y")

    # imagem inicial (sem colormap explícito)
    img = ax.imshow(np.zeros((n, n)), origin="lower", extent=[0, 1, 0, 1], aspect="equal")
    # scatter dos sensores
    scat = ax.scatter(S_POS[:,0], S_POS[:,1], s=60)
    # textos com temperaturas
    txts = [
        ax.text(0.02, 0.02, "S0: --.-°C", ha="left", va="bottom", fontsize=9),
        ax.text(0.02, 0.98, "S1: --.-°C", ha="left", va="top", fontsize=9),
        ax.text(0.98, 0.98, "S2: --.-°C", ha="right", va="top", fontsize=9),
        ax.text(0.98, 0.02, "S3: --.-°C", ha="right", va="bottom", fontsize=9),
    ]

    # loop de atualização
    last_vmin = None
    last_vmax = None
    try:
        while plt.fignum_exists(fig.number):
            with lock:
                vals = ema.copy()

            if not any(np.isnan(vals)):
                grid = bilinear_grid(vals, n)

                # escala de cores: fixa ou adaptativa
                if args.fixed:
                    vmin, vmax = float(args.fixed[0]), float(args.fixed[1])
                else:
                    # adaptativa com margem
                    vmin = min(vals) - 0.5
                    vmax = max(vals) + 0.5
                    # evita faixa vazia se todos iguais
                    if abs(vmax - vmin) < 0.1:
                        vmin -= 0.5
                        vmax += 0.5

                img.set_data(grid)
                # só atualiza clim se mudou significativamente (evita "piscadas")
                if (last_vmin is None or abs(vmin - last_vmin) > 0.05 or
                    last_vmax is None or abs(vmax - last_vmax) > 0.05):
                    img.set_clim(vmin=vmin, vmax=vmax)
                    last_vmin, last_vmax = vmin, vmax

                # atualiza textos
                txts[0].set_text(f"S0: {vals[0]:.1f}°C")
                txts[1].set_text(f"S1: {vals[1]:.1f}°C")
                txts[2].set_text(f"S2: {vals[2]:.1f}°C")
                txts[3].set_text(f"S3: {vals[3]:.1f}°C")

            plt.pause(args.interval / 1000.0)
    except KeyboardInterrupt:
        pass
    finally:
        reader.stop()
        time.sleep(0.2)

if __name__ == "__main__":
    main()
