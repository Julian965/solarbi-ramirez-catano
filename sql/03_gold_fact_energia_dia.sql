-- Gold: el resumen diario se calcula DENTRO de PostgreSQL a partir de Silver (parte ELT del flujo,
-- como se explicó en la respuesta E1 de la Parte A). Idempotente gracias a ON CONFLICT.

-- 1) Dimensión fecha: un registro por cada día que aparece en Silver
INSERT INTO dwh.dim_fecha (fecha_key, fecha, anio, mes, dia, nombre_dia)
SELECT TO_CHAR(d, 'YYYYMMDD')::int,
       d,
       EXTRACT(YEAR  FROM d)::smallint,
       EXTRACT(MONTH FROM d)::smallint,
       EXTRACT(DAY   FROM d)::smallint,
       (ARRAY['lunes','martes','miércoles','jueves','viernes','sábado','domingo'])[EXTRACT(ISODOW FROM d)::int]
FROM (SELECT DISTINCT (ts AT TIME ZONE 'America/Bogota')::date AS d FROM silver.lectura_5min) AS dias
ON CONFLICT (fecha_key) DO NOTHING;

-- 2) Hecho diario: energía = suma de (potencia x 5/60 h); % válidos = lecturas válidas / 288 esperadas
INSERT INTO dwh.fact_energia_dia
       (fecha_key, dispositivo_key, energia_kwh, lecturas_validas, pct_datos_validos, yield_kwh_kwp, actualizado_en)
SELECT TO_CHAR((l.ts AT TIME ZONE 'America/Bogota')::date, 'YYYYMMDD')::int AS fecha_key,
       dd.dispositivo_key,
       ROUND(SUM(l.p_ac_kw) * 5 / 60.0, 4)                         AS energia_kwh,
       COUNT(*)                                                     AS lecturas_validas,
       ROUND(COUNT(*) * 100.0 / 288, 2)                             AS pct_datos_validos,
       ROUND(SUM(l.p_ac_kw) * 5 / 60.0 / dd.potencia_kwp, 3)        AS yield_kwh_kwp,
       now()
FROM silver.lectura_5min AS l
JOIN dwh.dim_dispositivo AS dd ON dd.dispositivo_id = l.dispositivo_id
GROUP BY 1, dd.dispositivo_key, dd.potencia_kwp
ON CONFLICT (fecha_key, dispositivo_key) DO UPDATE SET
    energia_kwh       = EXCLUDED.energia_kwh,
    lecturas_validas  = EXCLUDED.lecturas_validas,
    pct_datos_validos = EXCLUDED.pct_datos_validos,
    yield_kwh_kwp     = EXCLUDED.yield_kwh_kwp,
    actualizado_en    = EXCLUDED.actualizado_en;
