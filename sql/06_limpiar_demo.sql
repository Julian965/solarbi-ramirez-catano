-- Borra las lecturas de la demo de alerta (todo lo posterior al dataset del caso, 5-7 oct 2026).
DELETE FROM silver.lectura_5min WHERE ts >= TIMESTAMPTZ '2026-10-08 00:00:00-05';
SELECT COUNT(*) AS lecturas_silver FROM silver.lectura_5min;  -- debe volver a 837
