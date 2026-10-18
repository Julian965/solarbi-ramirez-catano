-- Gobernanza (G4/G5): Power BI y Grafana leen con un usuario de SOLO LECTURA,
-- distinto del usuario del ETL. Ejecutar como administrador (postgres) en la base solarbi,
-- DESPUÉS de la primera ejecución del ETL (cuando ya existen las tablas).
--
-- Cambie 'CAMBIE_ESTA_CLAVE' solo en su equipo y NO haga commit con la clave real.

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'solarbi_lector') THEN
        CREATE ROLE solarbi_lector LOGIN PASSWORD 'CAMBIE_ESTA_CLAVE';
    END IF;
END $$;

GRANT CONNECT ON DATABASE solarbi TO solarbi_lector;
GRANT USAGE ON SCHEMA silver, dwh TO solarbi_lector;
GRANT SELECT ON ALL TABLES IN SCHEMA silver, dwh TO solarbi_lector;
-- Si más adelante se crean tablas nuevas en silver o dwh, vuelva a ejecutar este script.
