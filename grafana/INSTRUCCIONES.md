# Grafana: tablero de monitoreo operativo

Requisito: haber ejecutado `python etl/run_etl.py` (misma base `solarbi` que usa Power BI).

## 1. Instalar Grafana OSS (elija una opción)

**A. Instalador de Windows.** Descargue *Grafana OSS* desde https://grafana.com/grafana/download?edition=oss
(Windows installer), instálelo y abra http://localhost:3000. Usuario `admin`, clave `admin`
(le pedirá cambiarla).

**B. Docker.**

```bash
docker run -d -p 3000:3000 --name grafana grafana/grafana-oss
```

Con Docker, en el paso 2 el host de PostgreSQL es `host.docker.internal:5432`, no `localhost`.

## 2. Agregar PostgreSQL como data source

**Connections → Data sources → Add data source → PostgreSQL**

| Campo | Valor |
|---|---|
| Name | `PostgreSQL SolarBI` |
| Host URL | `localhost:5432` (Docker: `host.docker.internal:5432`) |
| Database name | `solarbi` |
| Username / Password | `solarbi_lector` (solo lectura, ver `sql/00_usuario_lectura.sql`) o `postgres` |
| TLS/SSL Mode | `disable` |

**Save & test** debe decir *Database Connection OK*. → **Captura para el PDF.**

## 3. Importar el tablero

**Dashboards → New → Import → Upload dashboard JSON file →** `grafana/dashboard.json` →
en *PostgreSQL SolarBI* elija el data source del paso 2 → **Import**.

El tablero abre en el rango 5–8 de octubre de 2026 (hora de Bogotá). Contiene:

| Panel | Qué muestra | Requisito del taller |
|---|---|---|
| Potencia AC cada 5 minutos e irradiancia | Serie de tiempo con `$__timeFilter(ts)` y línea de umbral | Panel de series de tiempo |
| Fallas: lecturas en 0 kW entre 09:00 y 15:00 | Se pone **rojo** si hay ≥ 1 lectura en cero en horario de sol | Umbral (threshold) |
| Energía del día seleccionado | Lee `dwh.fact_energia_dia` según la variable **Día** | Panel stat |
| % datos válidos | Verde si ≥ 95 % (meta del contrato de datos) | — |
| Potencia promedio por hora | Consulta de la respuesta D4 con `$__timeGroupAlias` | — |
| Detalle de fallas | Tabla con hora, potencia e irradiancia de cada lectura en cero | — |

Elija **Día = 2026-10-06** para ver la falla simulada de 11:00 a 11:40 (potencia en 0 con irradiancia
de 700–990 W/m²). Valores esperados: energía del 6 de octubre **25,01 kWh**, fallas **9**.

## 4. Regla de alerta (respuesta D5)

**Alerting → Alert rules → New alert rule**

1. Nombre: `Potencia cero en horario de sol`.
2. Consulta A: data source *PostgreSQL SolarBI*, modo **Code**, formato **Table**, pegue
   `grafana/alerta_potencia_cero.sql`.
3. Expresiones: deje *Reduce* (Last) y *Threshold*: **IS ABOVE 0**.
4. Carpeta `SolarBI`, grupo de evaluación `planta` cada **5m**, pending period **5m**.
5. Contact point: correo del técnico de planta. (Para que el correo salga de verdad, Grafana
   necesita SMTP en `grafana.ini` o en variables `GF_SMTP_*`; esas claves **nunca** van al repositorio.)
6. **Save rule and exit.**

**Probarla:** los datos del caso son de octubre de 2026 y la regla mira los "últimos 15 minutos",
así que con ellos no se dispara (estado *Normal*). Para verla en *Firing*, entre 09:00 y 15:00
ejecute en pgAdmin `sql/05_demo_falla_en_vivo.sql`, espere 5–10 minutos y tome la captura de la
lista de reglas. Después ejecute **`sql/06_limpiar_demo.sql`** (vuelve a 837 lecturas).

Opcional: exporte la regla (**Alert rules → Export**) y guárdela como `grafana/alert_rule.yaml`.

## 5. Exportar el tablero al repositorio

Cuando el tablero esté como lo quieren: icono **Share/Export → Export → Export as JSON →**
active **"Export the dashboard to use in another instance"** → **Download file** y reemplace
`grafana/dashboard.json` por ese archivo. Haga commit (así queda versionado, respuesta V1).

## 6. Capturas para el PDF

1. Data source *Database Connection OK*.
2. Tablero completo con el día 2026-10-06 (se ve la falla y el umbral en rojo).
3. Lista de reglas de alerta (ideal: en estado *Firing* con la demo).
