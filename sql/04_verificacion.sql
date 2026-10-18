-- Consultas de control para pgAdmin (sirven para las capturas del Paso 3).
-- Correr después de cada ejecución del ETL: los conteos de silver y dwh deben ser iguales
-- en la 1.ª y en la 2.ª ejecución; control.etl_ejecucion sí crece (es la bitácora).

-- 1) Conteos por tabla
SELECT 'silver.lectura_5min'   AS tabla, COUNT(*) AS filas FROM silver.lectura_5min
UNION ALL SELECT 'dwh.dim_fecha',        COUNT(*) FROM dwh.dim_fecha
UNION ALL SELECT 'dwh.dim_dispositivo',  COUNT(*) FROM dwh.dim_dispositivo
UNION ALL SELECT 'dwh.fact_energia_dia', COUNT(*) FROM dwh.fact_energia_dia;

-- 2) Resumen diario (Gold)
SELECT d.fecha, f.dispositivo_key, f.energia_kwh, f.lecturas_validas, f.pct_datos_validos, f.yield_kwh_kwp
FROM dwh.fact_energia_dia f
JOIN dwh.dim_fecha d USING (fecha_key)
ORDER BY d.fecha;

-- 3) Energía total
SELECT SUM(energia_kwh) AS energia_total_kwh FROM dwh.fact_energia_dia;

-- 4) Bitácora de ejecuciones
SELECT id, ejecutado_en, filas_leidas, rech_faltantes, rech_formato, rech_duplicados, rech_rango,
       filas_validas, pct_validos, filas_silver, filas_gold
FROM control.etl_ejecucion
ORDER BY id;

-- 5) Fallas: lecturas en cero entre 09:00 y 15:00 (lo que vigila Grafana)
SELECT ts AT TIME ZONE 'America/Bogota' AS hora_local, p_ac_kw, irradiancia_wm2
FROM silver.lectura_5min
WHERE p_ac_kw = 0
  AND (ts AT TIME ZONE 'America/Bogota')::time BETWEEN TIME '09:00' AND TIME '15:00'
ORDER BY ts;
