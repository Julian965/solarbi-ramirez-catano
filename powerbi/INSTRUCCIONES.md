# Power BI: página de energía y calidad de datos

Requisito: haber ejecutado `python etl/run_etl.py` (la base `solarbi` ya tiene las tablas `dwh.*`).

## 1. Conectar a PostgreSQL

1. Power BI Desktop → **Inicio → Obtener datos → Más… → Base de datos PostgreSQL**.
2. Servidor: `localhost` · Base de datos: `solarbi` · Modo: **Importar**.
3. Credenciales: pestaña **Base de datos**, usuario `solarbi_lector` (o `postgres`) y su clave.
   Si aparece un aviso de cifrado, acepte conectarse sin cifrado (es un servidor local).
4. En el navegador marque `dwh.dim_dispositivo`, `dwh.dim_fecha` y `dwh.fact_energia_dia` → **Cargar**.
5. Renombre las tablas (doble clic en el panel Datos) a `dim_dispositivo`, `dim_fecha` y `fact_energia_dia`.
   Así funcionan tal cual las medidas de `medidas.dax`.

`conexion_postgresql.m` tiene el mismo código en lenguaje M, por si prefieren pegarlo en el Editor avanzado.

## 2. Modelo

En la vista **Modelo** verifique estas relaciones (Power BI suele crearlas solo):

- `dim_fecha[fecha_key]` 1 → * `fact_energia_dia[fecha_key]`
- `dim_dispositivo[dispositivo_key]` 1 → * `fact_energia_dia[dispositivo_key]`

## 3. Medidas DAX

Seleccione la tabla `fact_energia_dia` → **Modelado → Nueva medida** y cree cada medida de `medidas.dax`.
Ponga `% Datos Validos` con formato **Porcentaje** y 2 decimales.

## 4. Página del reporte (lo que pide el taller)

| Visual | Configuración | Valor esperado |
|---|---|---|
| Tarjeta | Campo: `[Energia Total kWh]` | **78,07 kWh** |
| Gráfico de líneas | Eje X: `dim_fecha[fecha]` (elija *fecha*, no *Jerarquía de fechas*) · Eje Y: `[Energia Total kWh]` | 26,92 · 25,01 · 26,14 kWh |
| Tarjeta | Campo: `[% Datos Validos]` | **96,88 %** |

Sugerencia: agregue un título ("SolarBI Pascual · Energía y calidad de datos · Grupo 01") y una
segmentación por `dim_fecha[fecha]`. Al elegir el 6 de octubre se ve que ese día produjo menos
energía: es la falla de 11:00 a 11:40 que también muestra Grafana.

## 5. Guardar en el repositorio

- **Archivo → Guardar como → Proyecto de Power BI (.pbip)** dentro de esta carpeta `powerbi/`,
  con el nombre `SolarBI_G01`. Si no aparece la opción, actívela en **Archivo → Opciones →
  Características de vista previa → "Guardar como proyecto de Power BI (.pbip)"** y reinicie.
- Si no pueden usar .pbip, guarden `SolarBI_G01.pbix` en esta carpeta.
- El `.gitignore` ya excluye la caché y la configuración local del proyecto .pbip.

## 6. Captura para el PDF

Tome una captura de la página completa del reporte con las tres visualizaciones y, si
pueden, otra de la vista Modelo con las relaciones.
