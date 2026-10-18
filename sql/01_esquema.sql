-- SolarBI Pascual | Grupo 01 | Esquema en PostgreSQL
-- Se puede ejecutar muchas veces: todo usa IF NOT EXISTS / ON CONFLICT.
-- Capas: silver (lecturas limpias de 5 min), dwh (Gold: estrella mínima), control (bitácora del ETL).

CREATE SCHEMA IF NOT EXISTS silver;
CREATE SCHEMA IF NOT EXISTS dwh;
CREATE SCHEMA IF NOT EXISTS control;

-- ---------------------------------------------------------------- Silver
CREATE TABLE IF NOT EXISTS silver.lectura_5min (
    ts               timestamptz   NOT NULL,              -- hora local de Bogotá (-05:00)
    dispositivo_id   integer       NOT NULL,
    p_ac_kw          numeric(6,3)  NOT NULL CHECK (p_ac_kw BETWEEN 0 AND 5),
    irradiancia_wm2  numeric(7,1)  NOT NULL CHECK (irradiancia_wm2 BETWEEN 0 AND 1200),
    temp_modulo_c    numeric(5,1)  NOT NULL CHECK (temp_modulo_c BETWEEN -10 AND 90),
    -- energía del intervalo = potencia x 5/60 h
    energia_kwh      numeric(9,6)  GENERATED ALWAYS AS (p_ac_kw * 5 / 60) STORED,
    PRIMARY KEY (ts, dispositivo_id)
);

-- ---------------------------------------------------------------- Gold (dwh)
CREATE TABLE IF NOT EXISTS dwh.dim_dispositivo (
    dispositivo_key  integer       PRIMARY KEY,
    dispositivo_id   integer       NOT NULL UNIQUE,      -- id que llega en la telemetría
    nombre           text          NOT NULL,
    tipo             text          NOT NULL,
    potencia_kwp     numeric(6,2)  NOT NULL,
    sitio            text          NOT NULL
);

CREATE TABLE IF NOT EXISTS dwh.dim_fecha (
    fecha_key        integer       PRIMARY KEY,          -- AAAAMMDD
    fecha            date          NOT NULL UNIQUE,
    anio             smallint      NOT NULL,
    mes              smallint      NOT NULL,
    dia              smallint      NOT NULL,
    nombre_dia       text          NOT NULL
);

CREATE TABLE IF NOT EXISTS dwh.fact_energia_dia (
    fecha_key          integer       NOT NULL REFERENCES dwh.dim_fecha (fecha_key),
    dispositivo_key    integer       NOT NULL REFERENCES dwh.dim_dispositivo (dispositivo_key),
    energia_kwh        numeric(10,4) NOT NULL CHECK (energia_kwh >= 0),
    lecturas_validas   integer       NOT NULL CHECK (lecturas_validas BETWEEN 0 AND 288),
    pct_datos_validos  numeric(5,2)  NOT NULL CHECK (pct_datos_validos BETWEEN 0 AND 100),
    yield_kwh_kwp      numeric(6,3)  NOT NULL,           -- energía / potencia instalada
    actualizado_en     timestamptz   NOT NULL DEFAULT now(),
    PRIMARY KEY (fecha_key, dispositivo_key)              -- llave que hace idempotente el UPSERT
);

-- ---------------------------------------------------------------- Control
-- Bitácora: a propósito agrega UNA fila por ejecución (trazabilidad / data lineage).
-- No es parte de la prueba de idempotencia; esa se mide en silver y dwh.
CREATE TABLE IF NOT EXISTS control.etl_ejecucion (
    id                 serial        PRIMARY KEY,
    ejecutado_en       timestamptz   NOT NULL DEFAULT now(),
    bronze_sha256      text          NOT NULL,
    filas_leidas       integer       NOT NULL,
    rech_faltantes     integer       NOT NULL,
    rech_formato       integer       NOT NULL,
    rech_duplicados    integer       NOT NULL,
    rech_rango         integer       NOT NULL,
    filas_validas      integer       NOT NULL,
    pct_validos        numeric(5,2)  NOT NULL,
    filas_silver       integer       NOT NULL,
    filas_gold         integer       NOT NULL
);

-- Catálogo de dispositivos (dimensión estática del caso)
INSERT INTO dwh.dim_dispositivo (dispositivo_key, dispositivo_id, nombre, tipo, potencia_kwp, sitio)
VALUES (1, 1, 'Inversor 01', 'inversor', 5.00, 'sitio01')
ON CONFLICT (dispositivo_key) DO UPDATE SET
    nombre = EXCLUDED.nombre, tipo = EXCLUDED.tipo,
    potencia_kwp = EXCLUDED.potencia_kwp, sitio = EXCLUDED.sitio;
