-- DEMO para ver la alerta de Grafana en estado "Firing".
-- Los datos del caso son del 5 al 7 de octubre de 2026, así que una regla que mira los
-- "últimos 15 minutos" nunca se activa con ellos. Este script simula que el inversor
-- está en falla AHORA: inserta 4 lecturas de 0 kW con sol (últimos 15 minutos).
-- Ejecútelo entre las 09:00 y las 15:00 (hora de Bogotá) y espere 5 a 10 minutos.
--
-- IMPORTANTE: al terminar ejecute 06_limpiar_demo.sql ANTES de volver a correr el ETL.

INSERT INTO silver.lectura_5min (ts, dispositivo_id, p_ac_kw, irradiancia_wm2, temp_modulo_c)
SELECT to_timestamp(floor(extract(epoch FROM now()) / 300) * 300) - (n * INTERVAL '5 minutes'),
       1, 0.000, 850.0, 48.0
FROM generate_series(0, 3) AS n
ON CONFLICT (ts, dispositivo_id) DO NOTHING;

SELECT ts AT TIME ZONE 'America/Bogota' AS hora_local, p_ac_kw
FROM silver.lectura_5min
WHERE ts > now() - INTERVAL '20 minutes'
ORDER BY ts;
