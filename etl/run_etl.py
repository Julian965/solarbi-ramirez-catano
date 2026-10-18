"""SolarBI Pascual | Grupo 01 | Punto de entrada único del flujo ETL.

    python etl/run_etl.py

Bronze  -> data/bronze/telemetria.csv (se genera solo si falta; nunca se modifica)
Silver  -> reglas de calidad con pandas -> data/silver/*.csv y tabla silver.lectura_5min (UPSERT)
Gold    -> resumen diario calculado con SQL dentro de PostgreSQL -> dwh.fact_energia_dia (UPSERT)

La conexión se toma de la variable de entorno SOLARBI_DB_URL o del archivo .env
(que NO se sube a GitHub). Ver .env.example.

Opciones:
    --sin-bd        solo genera Bronze/Silver en archivos, sin conectarse a PostgreSQL
    --log RUTA      además de mostrar el reporte, lo guarda en RUTA (evidencia)
"""
import argparse
import hashlib
import json
import os
import sys
from datetime import timedelta, timezone
from pathlib import Path

import pandas as pd

sys.path.insert(0, str(Path(__file__).resolve().parent))
from simulador import generar  # noqa: E402

RAIZ = Path(__file__).resolve().parents[1]
BRONZE = RAIZ / "data" / "bronze" / "telemetria.csv"
SILVER_CSV = RAIZ / "data" / "silver" / "lectura_5min.csv"
RECHAZOS_CSV = RAIZ / "data" / "silver" / "rechazos.csv"
METRICAS_JSON = RAIZ / "data" / "silver" / "metricas_calidad.json"
CONTRATO = RAIZ / "etl" / "contrato_datos.json"
SQL = RAIZ / "sql"
TZ_BOGOTA = timezone(timedelta(hours=-5))  # Colombia no tiene horario de verano

try:  # consola de Windows: evita errores con tildes
    sys.stdout.reconfigure(encoding="utf-8")
except AttributeError:
    pass


# ------------------------------------------------------------------ utilidades
def cargar_env():
    """Lee .env (CLAVE=valor) sin dependencias extra. No pisa variables ya definidas."""
    archivo = RAIZ / ".env"
    if not archivo.exists():
        return
    for linea in archivo.read_text(encoding="utf-8").splitlines():
        linea = linea.strip()
        if linea and not linea.startswith("#") and "=" in linea:
            clave, valor = linea.split("=", 1)
            os.environ.setdefault(clave.strip(), valor.strip())


# ------------------------------------------------------------------ Silver
def aplicar_reglas(contrato):
    """Aplica las reglas de calidad del contrato de datos. Devuelve (validas, rechazos, metricas)."""
    campos = [c["nombre"] for c in contrato["campos"]]
    df = pd.read_csv(BRONZE, dtype=str, keep_default_na=False)

    # Regla 0 - esquema: si la fuente cambia un campo sin avisar, el ETL se detiene (G3).
    if list(df.columns) != campos:
        raise SystemExit(
            f"ERROR de contrato: columnas recibidas {list(df.columns)}; se esperaban {campos}. "
            "No se carga nada hasta publicar una nueva versión del contrato."
        )

    df.insert(0, "fila_bronze", range(2, len(df) + 2))  # n.º de línea en el CSV (trazabilidad)
    df["regla"] = ""

    # R1 - datos faltantes: cualquier campo obligatorio vacío
    vacio = df[campos].apply(lambda s: s.str.strip() == "").any(axis=1)
    df.loc[vacio, "regla"] = "R1_faltante"

    # R2 - formato: el valor no se puede convertir al tipo del contrato
    ts = pd.to_datetime(df["ts"], format="%Y-%m-%d %H:%M:%S", errors="coerce")
    num = {c: pd.to_numeric(df[c], errors="coerce") for c in campos[1:]}
    mal_formato = ts.isna() | pd.concat(num.values(), axis=1).isna().any(axis=1)
    df.loc[(df["regla"] == "") & mal_formato, "regla"] = "R2_formato"

    pendientes = df["regla"] == ""
    df["ts_dt"] = ts
    for c, s in num.items():
        df[c + "_n"] = s

    # R3 - duplicados: misma lectura (ts, dispositivo) ya vista; se conserva la primera
    dup = df[pendientes].duplicated(subset=["ts_dt", "dispositivo_id_n"], keep="first")
    df.loc[dup[dup].index, "regla"] = "R3_duplicado"

    # R4 - rango físico y dominio, según los límites del contrato
    lim = {c["nombre"]: (c["min"], c["max"]) for c in contrato["campos"] if "min" in c}
    fuera = pd.Series(False, index=df.index)
    for c, (mn, mx) in lim.items():
        fuera |= ~df[c + "_n"].between(mn, mx)
    fuera |= df["dispositivo_id_n"] != 1          # debe existir en el catálogo de dispositivos
    fuera |= df["ts_dt"].dt.minute % 5 != 0       # una lectura cada 5 minutos exactos
    df.loc[(df["regla"] == "") & fuera, "regla"] = "R4_rango"

    validas = df[df["regla"] == ""].copy()
    validas = pd.DataFrame({
        "ts": validas["ts_dt"],
        "dispositivo_id": validas["dispositivo_id_n"].astype(int),
        "p_ac_kw": validas["p_ac_kw_n"],
        "irradiancia_wm2": validas["irradiancia_wm2_n"],
        "temp_modulo_c": validas["temp_modulo_c_n"],
    }).sort_values(["ts", "dispositivo_id"]).reset_index(drop=True)
    rechazos = df[df["regla"] != ""][["fila_bronze", *campos, "regla"]]

    conteo = rechazos["regla"].value_counts()
    leidas = len(df)
    metricas = {
        "bronze_archivo": "data/bronze/telemetria.csv",
        "bronze_sha256": hashlib.sha256(BRONZE.read_bytes()).hexdigest(),
        "contrato_version": contrato["version"],
        "filas_leidas": leidas,
        "rechazos": {
            "R1_faltante": int(conteo.get("R1_faltante", 0)),
            "R2_formato": int(conteo.get("R2_formato", 0)),
            "R3_duplicado": int(conteo.get("R3_duplicado", 0)),
            "R4_rango": int(conteo.get("R4_rango", 0)),
        },
        "filas_validas": len(validas),
        "pct_datos_validos": round(100 * len(validas) / leidas, 2),
    }
    assert metricas["filas_validas"] + sum(metricas["rechazos"].values()) == leidas, "Los conteos no cuadran"

    # Silver en archivos (para el repositorio y para revisar a mano)
    SILVER_CSV.parent.mkdir(parents=True, exist_ok=True)
    validas.assign(ts=validas["ts"].dt.strftime("%Y-%m-%d %H:%M:%S")).to_csv(SILVER_CSV, index=False, lineterminator="\n")
    rechazos.to_csv(RECHAZOS_CSV, index=False, lineterminator="\n")
    METRICAS_JSON.write_text(json.dumps(metricas, indent=2, ensure_ascii=False) + "\n", encoding="utf-8", newline="\n")

    # % de datos válidos por día frente a las 288 lecturas esperadas (lo que va a Gold)
    por_dia = validas.groupby(validas["ts"].dt.date).size()
    metricas["por_dia"] = {
        str(d): {"lecturas_validas": int(n), "pct_sobre_288": round(100 * n / contrato["lecturas_esperadas_por_dia"], 2)}
        for d, n in por_dia.items()
    }
    return validas, rechazos, metricas


# ------------------------------------------------------------------ Gold / PostgreSQL
def cargar_postgres(validas, metricas, dsn):
    try:
        import psycopg
    except ImportError:
        raise SystemExit("Falta psycopg. Instale dependencias: pip install -r requirements.txt")

    filas = [
        (r.ts.to_pydatetime().replace(tzinfo=TZ_BOGOTA), int(r.dispositivo_id),
         float(r.p_ac_kw), float(r.irradiancia_wm2), float(r.temp_modulo_c))
        for r in validas.itertuples(index=False)
    ]
    with psycopg.connect(dsn) as con:  # una sola transacción: o carga todo o nada
        with con.cursor() as cur:
            cur.execute((SQL / "01_esquema.sql").read_text(encoding="utf-8"))
            cur.executemany((SQL / "02_upsert_silver.sql").read_text(encoding="utf-8"), filas)
            cur.execute((SQL / "03_gold_fact_energia_dia.sql").read_text(encoding="utf-8"))

            cur.execute("SELECT COUNT(*) FROM silver.lectura_5min")
            n_silver = cur.fetchone()[0]
            cur.execute("SELECT COUNT(*), COALESCE(SUM(energia_kwh), 0) FROM dwh.fact_energia_dia")
            n_gold, energia = cur.fetchone()
            cur.execute("""
                SELECT d.fecha, f.energia_kwh, f.lecturas_validas, f.pct_datos_validos
                FROM dwh.fact_energia_dia f JOIN dwh.dim_fecha d USING (fecha_key) ORDER BY d.fecha""")
            detalle = cur.fetchall()

            r = metricas["rechazos"]
            cur.execute(
                """INSERT INTO control.etl_ejecucion
                   (bronze_sha256, filas_leidas, rech_faltantes, rech_formato, rech_duplicados, rech_rango,
                    filas_validas, pct_validos, filas_silver, filas_gold)
                   VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s) RETURNING id""",
                (metricas["bronze_sha256"], metricas["filas_leidas"], r["R1_faltante"], r["R2_formato"],
                 r["R3_duplicado"], r["R4_rango"], metricas["filas_validas"], metricas["pct_datos_validos"],
                 n_silver, n_gold))
            id_ejecucion = cur.fetchone()[0]
    return {"id_ejecucion": id_ejecucion, "silver": n_silver, "gold": n_gold,
            "energia_total_kwh": float(energia), "detalle": detalle}


# ------------------------------------------------------------------ reporte
def reporte(metricas, carga):
    r = metricas["rechazos"]
    t = [
        "=" * 60,
        " SolarBI Pascual | ETL Grupo 01",
        "=" * 60,
        f" Bronze SHA-256 ........ {metricas['bronze_sha256'][:16]}... (no cambia)",
        f" Filas leídas .......... {metricas['filas_leidas']}",
        f" R1 faltantes .......... {r['R1_faltante']}",
        f" R2 formato ............ {r['R2_formato']}",
        f" R3 duplicados ......... {r['R3_duplicado']}",
        f" R4 rango físico ....... {r['R4_rango']}",
        f" Filas válidas ......... {metricas['filas_validas']}",
        f" % datos válidos ....... {metricas['pct_datos_validos']:.2f} %  (válidas / leídas)",
    ]
    if carga:
        t += [
            "-" * 60,
            f" Ejecución n.º ......... {carga['id_ejecucion']}  (control.etl_ejecucion)",
            f" silver.lectura_5min ... {carga['silver']} filas",
            f" dwh.fact_energia_dia .. {carga['gold']} filas",
            f" Energía total ......... {carga['energia_total_kwh']:.4f} kWh",
            "-" * 60,
            " Fecha        Energía kWh  Lect. válidas  % válidos (/288)",
        ]
        t += [f" {d}   {e:>10.4f}  {n:>13}  {p:>8.2f} %" for d, e, n, p in carga["detalle"]]
    else:
        t += ["-" * 60, " Modo --sin-bd: no se cargó PostgreSQL (solo archivos Silver)."]
    t.append("=" * 60)
    return "\n".join(t)


def main():
    ap = argparse.ArgumentParser(description="ETL SolarBI Pascual (Grupo 01)")
    ap.add_argument("--sin-bd", action="store_true", help="no conectarse a PostgreSQL")
    ap.add_argument("--log", help="ruta donde guardar el reporte de la ejecución")
    args = ap.parse_args()

    cargar_env()
    contrato = json.loads(CONTRATO.read_text(encoding="utf-8"))
    generar(BRONZE)  # crea Bronze solo si no existe
    validas, _, metricas = aplicar_reglas(contrato)

    carga = None
    if not args.sin_bd:
        dsn = os.getenv("SOLARBI_DB_URL")
        if not dsn:
            raise SystemExit("Falta SOLARBI_DB_URL. Copie .env.example como .env y ponga su conexión.")
        carga = cargar_postgres(validas, metricas, dsn)

    texto = reporte(metricas, carga)
    print(texto)
    if args.log:
        destino = (RAIZ / args.log) if not Path(args.log).is_absolute() else Path(args.log)
        destino.parent.mkdir(parents=True, exist_ok=True)
        destino.write_text(texto + "\n", encoding="utf-8", newline="\n")


if __name__ == "__main__":
    main()
