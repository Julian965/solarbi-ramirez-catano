# SolarBI Pascual · Grupo 01 · Ramirez – Cataño

> *"One governed dataset, two views: Grafana for real-time operations and Power BI for business decisions."*

| | |
|---|---|
| **Integrantes** | Julián Ramirez Molina · Nicolas Cataño Durango |
| **Curso** | Inteligencia de Negocios · Grupo 01 · Semestre 2026-II |
| **Docente** | Ramiro Grisales Montoya |
| **Institución** | Institución Universitaria Pascual Bravo |
| **Enfoque del grupo** | Monitoreo operativo: potencia en el tiempo y detección de fallas |

## Descripción

Flujo de datos pequeño pero completo para un inversor solar simulado de 5 kWp:

```
simulador.py ──► Bronze (CSV crudo, no se modifica)
                   │  reglas de calidad con pandas (contrato de datos)
                   ▼
                 Silver (data/silver + silver.lectura_5min en PostgreSQL)
                   │  resumen diario calculado con SQL dentro de PostgreSQL
                   ▼
                 Gold  (dwh.fact_energia_dia + dim_fecha + dim_dispositivo)
                   │
         ┌─────────┴──────────┐
     Grafana (lee Silver)   Power BI (lee Gold)
     operador de planta     directivos / análisis
```

El simulador es el del curso con tres cambios: semilla fija (datos reproducibles), protección del
Bronze (si existe no se reescribe) y una **falla inyectada** el 6 de octubre de 2026 de 11:00 a 11:40
(potencia 0 kW con sol) para probar el umbral y la alerta de Grafana.

## Resultados de la práctica

| Métrica | Valor |
|---|---:|
| Filas leídas (Bronze) | 887 |
| R1 · rechazadas por dato faltante | 14 |
| R2 · rechazadas por formato | 0 |
| R3 · rechazadas por duplicado | 23 |
| R4 · rechazadas por rango físico | 13 |
| Filas válidas (Silver) | 837 |
| **% de datos válidos** (válidas / leídas) | **94,36 %** |
| Días en `dwh.fact_energia_dia` | 3 |
| Energía total | 78,0711 kWh |
| % datos válidos frente a lo esperado (837 / 864) | 96,88 % |

| Fecha | Energía (kWh) | Lecturas válidas | % válidos (/288) |
|---|---:|---:|---:|
| 2026-10-05 | 26,9212 | 279 | 96,88 % |
| 2026-10-06 | 25,0088 | 281 | 97,57 % |
| 2026-10-07 | 26,1411 | 277 | 96,18 % |

Hay dos porcentajes y miden cosas distintas: **94,36 %** compara contra las filas que llegaron
(incluye las duplicadas); **96,88 %** compara contra las 288 lecturas que debían llegar cada día,
que es el `pct_datos_validos` de Gold y la tarjeta de Power BI.

### Reglas de calidad (definidas en `etl/contrato_datos.json`)

| Regla | Qué rechaza | Por qué |
|---|---|---|
| R0 · Esquema | Si cambian los nombres de columnas, el ETL **se detiene** y no carga nada | El contrato de datos protege el tablero (G3) |
| R1 · Faltantes | Cualquier campo obligatorio vacío | Una lectura sin irradiancia no se puede evaluar |
| R2 · Formato | Fecha o número que no se puede convertir | Evita errores de tipo en PostgreSQL |
| R3 · Duplicados | Misma pareja (`ts`, `dispositivo_id`) ya vista; se conserva la primera | Duplicar inflaría la energía |
| R4 · Rango físico | `p_ac_kw` fuera de 0–5, irradiancia fuera de 0–1200, temperatura fuera de −10–90, dispositivo fuera del catálogo o minuto no múltiplo de 5 | Valores imposibles para un inversor de 5 kWp |

Las filas rechazadas quedan en `data/silver/rechazos.csv` con la regla que las rechazó (trazabilidad).

## Cómo reproducir

Requisitos: Python 3.10+, PostgreSQL 14+ (con pgAdmin), Power BI Desktop y Grafana OSS.

```bash
# 1. Clonar e instalar dependencias
git clone https://github.com/USUARIO/solarbi-ramirez-catano.git
cd solarbi-ramirez-catano
pip install -r requirements.txt

# 2. Crear la base vacía (pgAdmin o psql)
createdb -U postgres solarbi

# 3. Configurar la conexión SIN subirla a GitHub
copy .env.example .env        # Windows   (Linux/Mac: cp .env.example .env)
#    editar .env con su usuario y clave

# 4. Ejecutar el ETL (un solo comando) y repetirlo para comprobar la idempotencia
python etl/run_etl.py
python etl/run_etl.py
```

En las dos ejecuciones `silver.lectura_5min` queda con 837 filas y `dwh.fact_energia_dia` con 3:
la carga usa `INSERT … ON CONFLICT … DO UPDATE` sobre las llaves primarias `(ts, dispositivo_id)`
y `(fecha_key, dispositivo_key)`. La única tabla que crece es `control.etl_ejecucion`, que es la
bitácora (una fila por ejecución). `sql/04_verificacion.sql` muestra los conteos en pgAdmin.

Opcional: `python etl/run_etl.py --sin-bd` genera solo los archivos Bronze y Silver, sin
conectarse a la base. `--log docs/evidencias/ejecucion_1.txt` guarda el reporte como evidencia.

Después siga `powerbi/INSTRUCCIONES.md` y `grafana/INSTRUCCIONES.md`.

## Programación diaria (no implementada; solo se deja la configuración)

**cron (Linux/Mac)**, todos los días a la medianoche:

```cron
0 0 * * * cd /home/usuario/solarbi-ramirez-catano && /usr/bin/python3 etl/run_etl.py >> logs/etl.log 2>&1
```

**Programador de tareas de Windows**, equivalente en una línea (cmd):

```bat
schtasks /Create /SC DAILY /ST 00:00 /TN "SolarBI_ETL" /TR "cmd /c cd /d C:\ruta\solarbi-ramirez-catano && py etl\run_etl.py >> logs\etl.log 2>&1"
```

Como la carga es idempotente, si la tarea se ejecuta dos veces el mismo día no duplica nada.

## Estructura

```
solarbi-ramirez-catano/
├── README.md
├── .gitignore
├── .env.example            plantilla de conexión (el .env real no se sube)
├── requirements.txt
├── docs/                   PDF de la consulta y evidencias de las ejecuciones
├── data/
│   ├── bronze/             telemetria.csv (crudo)
│   └── silver/             lectura_5min.csv, rechazos.csv, metricas_calidad.json
├── etl/                    simulador.py, run_etl.py, contrato_datos.json
├── sql/                    esquema, UPSERT, Gold, verificación, usuario lector, demo de alerta
├── powerbi/                proyecto .pbip / .pbix, medidas.dax, conexión M, instrucciones
└── grafana/                dashboard.json exportado, SQL de la alerta, instrucciones
```

## Seguridad y manejo de la información

- Ninguna contraseña ni cadena de conexión está en el repositorio: el ETL lee `SOLARBI_DB_URL` de
  `.env`, que está en `.gitignore`.
- Power BI y Grafana se conectan con `solarbi_lector`, un usuario de **solo lectura**.
- Los datos son de un equipo (inversor), no de personas; no se registra qué operador atiende cada
  alarma (Ley 1581 de 2012, respuesta G5).

## Quién hizo qué

| Integrante | Aportes |
|---|---|
| Julián Ramirez Molina | Estructura del repositorio, simulador y capa Bronze, reglas de calidad y capa Silver (`run_etl.py`), tablero de Grafana y regla de alerta |
| Nicolas Cataño Durango | Esquema PostgreSQL y capa Gold (`sql/`), prueba de idempotencia y evidencias, reporte de Power BI con medidas DAX, README y PDF final |

*(Ajusten esta tabla a lo que realmente hizo cada uno; debe coincidir con el historial de commits.)*
