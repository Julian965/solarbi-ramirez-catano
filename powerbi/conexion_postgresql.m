// Power Query (M) de referencia. Equivale a: Obtener datos > PostgreSQL > servidor localhost, base solarbi.
// Si prefiere pegarlo: Inicio > Obtener datos > Consulta en blanco > Editor avanzado, una consulta por tabla.
// Las tres consultas se pliegan (query folding) hacia PostgreSQL: clic derecho en el último paso >
// "Ver consulta nativa" debe mostrar el SELECT (respuesta E4 de la Parte A).

// ---------- Consulta: fact_energia_dia
let
    Origen = PostgreSQL.Database("localhost", "solarbi"),
    Fact = Origen{[Schema = "dwh", Item = "fact_energia_dia"]}[Data],
    Columnas = Table.SelectColumns(Fact,
        {"fecha_key", "dispositivo_key", "energia_kwh", "lecturas_validas", "pct_datos_validos", "yield_kwh_kwp"}),
    Tipos = Table.TransformColumnTypes(Columnas, {
        {"fecha_key", Int64.Type}, {"dispositivo_key", Int64.Type},
        {"energia_kwh", type number}, {"lecturas_validas", Int64.Type},
        {"pct_datos_validos", type number}, {"yield_kwh_kwp", type number}})
in
    Tipos

// ---------- Consulta: dim_fecha
let
    Origen = PostgreSQL.Database("localhost", "solarbi"),
    DimFecha = Origen{[Schema = "dwh", Item = "dim_fecha"]}[Data],
    Tipos = Table.TransformColumnTypes(DimFecha, {{"fecha_key", Int64.Type}, {"fecha", type date}})
in
    Tipos

// ---------- Consulta: dim_dispositivo
let
    Origen = PostgreSQL.Database("localhost", "solarbi"),
    DimDisp = Origen{[Schema = "dwh", Item = "dim_dispositivo"]}[Data]
in
    DimDisp
