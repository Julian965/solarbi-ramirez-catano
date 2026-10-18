-- Carga de una lectura limpia en Silver. La usa etl/run_etl.py (un marcador de parámetro por columna).
-- ON CONFLICT sobre la llave (ts, dispositivo_id): si la lectura ya existe se actualiza,
-- si no existe se inserta. Por eso repetir la carga no duplica filas.
INSERT INTO silver.lectura_5min (ts, dispositivo_id, p_ac_kw, irradiancia_wm2, temp_modulo_c)
VALUES (%s, %s, %s, %s, %s)
ON CONFLICT (ts, dispositivo_id) DO UPDATE SET
    p_ac_kw         = EXCLUDED.p_ac_kw,
    irradiancia_wm2 = EXCLUDED.irradiancia_wm2,
    temp_modulo_c   = EXCLUDED.temp_modulo_c
