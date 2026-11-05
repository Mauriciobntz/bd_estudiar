-- =============================================================
-- ETAPA V - Índices: carga masiva
-- Crea venta_historica, una tabla auxiliar sin índices, y le carga
-- un millón de ventas con fechas de 2021 a 2026. No forma parte del
-- modelo: se elimina con 03_limpieza.sql.
-- No se usa pedido porque ya tiene un índice agrupado en su clave
-- primaria y su trigger generaría un millón de filas de auditoría.
-- =============================================================

-- =============================================================
-- GUIA DE ESTUDIO PARA LA DEFENSA (rama estudio-defensa, no se sube)
-- Las lineas "-- >" son notas de estudio.
-- > Para medir un indice hacen falta muchas filas: con las 12 ventas reales,
-- >   cualquier consulta es instantanea y no se ve diferencia. Por eso se carga
-- >   un millon de filas en una tabla aparte.
-- > HEAP: una tabla sin indice agrupado. Las filas no tienen un orden, asi que
-- >   para buscar por fecha SQL Server tiene que leer la tabla entera.
-- =============================================================
USE smarthome_store;
GO
SET NOCOUNT ON;
GO

-- > OBJECT_ID('dbo.x') IS NOT NULL: si la tabla ya existe (de una corrida
-- >   anterior), se borra y se crea de nuevo.
IF OBJECT_ID('dbo.venta_historica') IS NOT NULL
    DROP TABLE dbo.venta_historica;
GO

CREATE TABLE dbo.venta_historica
(
    cod_venta    INT           NOT NULL,
    fecha_venta  DATETIME      NOT NULL,
    cod_cliente  INT           NOT NULL,
    cod_producto INT           NOT NULL,
    cantidad     INT           NOT NULL,
    importe      DECIMAL(10,2) NOT NULL,
    observacion  VARCHAR(200)  NOT NULL
);
GO

-- Los valores se calculan a partir del número de fila, así la carga da
-- siempre los mismos datos. 189216000 segundos son 6 años.
-- > Generador de un millon de numeros: ROW_NUMBER() sobre un CROSS JOIN de
-- >   sys.all_objects consigo misma (miles x miles de filas), quedandose con
-- >   TOP (1000000). CAST(... AS BIGINT) evita el desborde al multiplicar.
-- > WITH numeros AS (...): una CTE con esos numeros.
-- > Las columnas salen del numero de fila con el resto de la division (%):
-- >   1 + i % 10 da valores de 1 a 10. Asi la carga es "aleatoria" pero da siempre
-- >   los mismos datos, y las mediciones se pueden repetir.
-- > DATEADD(SECOND, n, '2021-01-01'): suma n segundos; 189216000 segundos son
-- >   6 anios, asi que las fechas quedan entre 2021 y 2026.
-- > REPLICATE('-', 100): repite el caracter 100 veces. Agranda cada fila para que
-- >   la tabla ocupe mas paginas, como una tabla real.
-- > WITH (TABLOCK): bloquea la tabla entera durante la carga; con un heap permite
-- >   una carga masiva mucho mas rapida.
WITH numeros AS
(
    SELECT TOP (1000000) CAST(ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS BIGINT) AS i
    FROM sys.all_objects a
    CROSS JOIN sys.all_objects b
)
INSERT INTO dbo.venta_historica WITH (TABLOCK)
    (cod_venta, fecha_venta, cod_cliente, cod_producto, cantidad, importe, observacion)
SELECT i,
       DATEADD(SECOND, CAST((i * 2654435761) % 189216000 AS INT), '2021-01-01'),
       1 + i % 10,
       1 + (i * 7) % 10,
       1 + i % 5,
       1000 + (i * 13) % 100000,
       'Venta histórica de prueba para la comparación de índices ' + REPLICATE('-', 100)
FROM numeros;
GO

-- > Control: 1000000 filas, primera fecha en 2021 y ultima en 2026.
-- > sys.indexes con type > 0: los indices de la tabla (type 0 es el heap mismo).
SELECT COUNT(*) AS filas, MIN(fecha_venta) AS primera, MAX(fecha_venta) AS ultima
FROM dbo.venta_historica;

-- Esperado: 0 índices (la tabla es un heap).
SELECT COUNT(*) AS indices
FROM sys.indexes
WHERE object_id = OBJECT_ID('dbo.venta_historica') AND type > 0;
GO
