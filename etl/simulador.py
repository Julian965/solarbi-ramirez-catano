"""Bronze: genera 3 días de telemetría de un inversor de 5 kWp (simulador base del curso).

Cambios frente al simulador base del docente:
  1. Semilla fija (SEMILLA) para que los datos sean reproducibles en cualquier equipo.
  2. Si data/bronze/telemetria.csv ya existe, NO se toca (Bronze no se modifica).
  3. Se inyecta una falla operativa (enfoque del Grupo 01: detección de fallas):
     el 6 de octubre de 2026 entre las 11:00 y las 11:40 el inversor entrega 0 kW
     aunque hay sol. Sirve para probar el umbral y la alerta de Grafana.

Uso:  python etl/simulador.py
"""
import csv
import math
import random
from datetime import datetime, timedelta
from pathlib import Path

SEMILLA = 2026_01  # año + grupo 01
INICIO = datetime(2026, 10, 5, 0, 0)
FALLA_INICIO = datetime(2026, 10, 6, 11, 0)
FALLA_FIN = datetime(2026, 10, 6, 11, 40)  # incluida

RUTA_BRONZE = Path(__file__).resolve().parents[1] / "data" / "bronze" / "telemetria.csv"


def generar(destino: Path = RUTA_BRONZE) -> bool:
    """Crea el CSV crudo. Devuelve False si ya existía (no lo sobrescribe)."""
    if destino.exists():
        return False
    destino.parent.mkdir(parents=True, exist_ok=True)
    rng = random.Random(SEMILLA)
    with destino.open("w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["ts", "dispositivo_id", "p_ac_kw", "irradiancia_wm2", "temp_modulo_c"])
        for i in range(3 * 288):  # 3 días, cada 5 min
            ts = INICIO + timedelta(minutes=5 * i)
            sol = max(0.0, math.sin(math.pi * (ts.hour + ts.minute / 60 - 6) / 12))
            irr = round(1000 * sol * rng.uniform(0.7, 1.0), 1)
            p_ac = round(5.0 * irr / 1000 * rng.uniform(0.80, 0.90), 3)
            if FALLA_INICIO <= ts <= FALLA_FIN:
                p_ac = 0.0  # falla: el inversor se dispara y deja de entregar potencia
            fila = [ts.isoformat(sep=" "), 1, p_ac, irr, round(22 + 30 * sol, 1)]
            r = rng.random()
            if r < 0.02:
                fila[2] = -1  # anomalía: potencia negativa
            elif r < 0.04:
                fila[3] = ""  # anomalía: dato faltante
            w.writerow(fila)
            if r > 0.98:
                w.writerow(fila)  # anomalía: fila duplicada
    return True


if __name__ == "__main__":
    creado = generar()
    print(("Bronze creado: " if creado else "Bronze ya existe, no se modifica: ") + str(RUTA_BRONZE))
