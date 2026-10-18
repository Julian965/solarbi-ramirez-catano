-- Regla de alerta de Grafana (respuesta D5 de la Parte A):
-- "si el promedio de p_ac_kw en los últimos 15 minutos es 0 entre las 9:00 y las 15:00,
--  enviar un correo al técnico de planta".
--
-- En Grafana: Alerting > Alert rules > New alert rule
--   Consulta A  : este SQL (formato Table)
--   Expresión B : Threshold  ->  A  IS ABOVE  0
--   Evaluación  : cada 5 min, pending period 5 min
--   Contact point: correo del técnico de planta
--
-- Devuelve 1 (falla) o 0 (normal). Fuera de 09:00-15:00 siempre devuelve 0, así no alerta de noche.
-- Exige al menos 3 lecturas para no confundir "no llegan datos" con "potencia cero".
SELECT CASE WHEN COUNT(*) >= 3 AND AVG(p_ac_kw) = 0 THEN 1 ELSE 0 END AS falla_potencia_cero
FROM silver.lectura_5min
WHERE dispositivo_id = 1
  AND ts > NOW() - INTERVAL '15 minutes'
  AND (NOW() AT TIME ZONE 'America/Bogota')::time BETWEEN TIME '09:00' AND TIME '15:00';
