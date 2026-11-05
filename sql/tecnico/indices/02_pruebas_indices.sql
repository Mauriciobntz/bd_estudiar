-- =============================================================
-- ETAPA V - Índices: comparación de la búsqueda por período
-- Repite la misma consulta sin índice, con un índice agrupado y con
-- un índice no agrupado que incluye las columnas seleccionadas.
-- Requiere 01_carga_masiva.sql.
--
-- Para ver el plan en SSMS: Ctrl+M antes de ejecutar. Los tiempos y
-- las lecturas salen en la pestaña Mensajes. Cada consulta corre dos
-- veces: en frío (sin datos en memoria) y en caliente.
-- DBCC DROPCLEANBUFFERS vacía la memoria de datos de todo el servidor:
-- usar solo en un equipo de pruebas.
-- =============================================================

-- =============================================================
-- GUIA DE ESTUDIO PARA LA DEFENSA (rama estudio-defensa, no se sube)
-- Las lineas "-- >" son notas de estudio.
-- > INDICE: una estructura ordenada (un arbol B) que permite llegar a las filas
-- >   sin leer toda la tabla, como el indice de un libro.
-- > AGRUPADO (CLUSTERED): ordena la TABLA MISMA por esa columna; sus hojas son
-- >   las filas completas. Hay uno solo por tabla. La PK lo crea por defecto.
-- > NO AGRUPADO (NONCLUSTERED): una estructura aparte, con la columna ordenada y
-- >   un puntero a la fila. Puede haber muchos.
-- > INCLUDE (columnas): guarda esas columnas en las hojas del indice no agrupado.
-- >   Si el indice tiene todas las columnas que pide la consulta, es CUBRIENTE: la
-- >   responde sin ir a la tabla.
-- > Costo de los indices: ocupan espacio, y cada INSERT, UPDATE o DELETE tiene que
-- >   actualizarlos. Se crean para las consultas frecuentes, no para todas.
-- > Que se compara: LECTURAS LOGICAS (paginas de 8 KB leidas). Es mas confiable
-- >   que el tiempo, que depende del equipo y de lo que haya en memoria.
-- > Plan de ejecucion (Ctrl+M en SSMS): muestra COMO resolvio la consulta.
-- >   Table Scan          = recorre toda la tabla (heap).
-- >   Clustered Index Seek= baja por el indice agrupado directo al rango.
-- >   Index Seek          = lo mismo en un indice no agrupado.
-- >   Seek = busqueda dirigida; Scan = recorrido completo.
-- =============================================================
USE smarthome_store;
GO
SET NOCOUNT ON;
-- > SET STATISTICS IO ON: muestra las lecturas logicas en la pestana Mensajes.
-- > SET STATISTICS TIME ON: muestra el tiempo de CPU y el tiempo total.
SET STATISTICS IO, TIME ON;
GO

-- === ESCENARIO 1: sin índice
-- Esperado: Table Scan, 14.158 filas y 25.642 lecturas lógicas en las dos corridas.
-- Se quitan los índices de una ejecución anterior, para que el script se pueda repetir.
DROP INDEX IF EXISTS IX_venta_historica_fecha_cubre ON dbo.venta_historica;
DROP INDEX IF EXISTS IX_venta_historica_fecha ON dbo.venta_historica;
GO
-- > Prueba en FRIO: CHECKPOINT escribe a disco las paginas modificadas y
-- >   DBCC DROPCLEANBUFFERS vacia la memoria de datos, asi la primera consulta
-- >   tiene que leer del disco. La segunda corre en CALIENTE (ya en memoria).
CHECKPOINT;
DBCC DROPCLEANBUFFERS WITH NO_INFOMSGS;
GO
-- > La consulta: ventas de enero de 2025. Se usa ">= '2025-01-01' AND
-- >   < '2025-02-01'" (rango semiabierto) para incluir todo el 31 de enero sin
-- >   importar la hora. Escribir YEAR(fecha) = 2025 impediria usar el indice,
-- >   porque aplica una funcion a la columna.
-- > Sin indice: Table Scan de 1000000 filas para devolver 14158 (25642 lecturas).
SELECT cod_venta, fecha_venta, importe FROM dbo.venta_historica WHERE fecha_venta >= '2025-01-01' AND fecha_venta < '2025-02-01';
GO
SELECT cod_venta, fecha_venta, importe FROM dbo.venta_historica WHERE fecha_venta >= '2025-01-01' AND fecha_venta < '2025-02-01';
GO

-- === ESCENARIO 2: índice agrupado sobre fecha_venta
-- Esperado: Clustered Index Seek, 14.158 filas y 367 lecturas lógicas.
-- > Escenario 2: el indice agrupado reordena la tabla por fecha. Las ventas de
-- >   enero quedan juntas, y el Seek lee solo esas paginas: 367 lecturas (98,6 %
-- >   menos). Pero cada pagina tiene filas completas, con la observacion larga.
CREATE CLUSTERED INDEX IX_venta_historica_fecha ON dbo.venta_historica (fecha_venta);
GO
CHECKPOINT;
DBCC DROPCLEANBUFFERS WITH NO_INFOMSGS;
GO
SELECT cod_venta, fecha_venta, importe FROM dbo.venta_historica WHERE fecha_venta >= '2025-01-01' AND fecha_venta < '2025-02-01';
GO
SELECT cod_venta, fecha_venta, importe FROM dbo.venta_historica WHERE fecha_venta >= '2025-01-01' AND fecha_venta < '2025-02-01';
GO

-- === ESCENARIO 3: índice no agrupado que incluye las columnas seleccionadas
-- SQL Server no admite INCLUDE en un índice agrupado, porque ese índice
-- ya contiene todas las columnas de la tabla.
-- Esperado: Index Seek, 14.158 filas y 67 lecturas lógicas.
-- > Escenario 3: se borra el agrupado (vuelve a ser heap) y se crea un no agrupado
-- >   por fecha con INCLUDE (cod_venta, importe). Es CUBRIENTE: tiene las 3 columnas
-- >   de la consulta. Sus hojas son mucho mas angostas que la fila completa, asi
-- >   que entran mas filas por pagina: 67 lecturas (99,7 % menos).
-- > Desventaja: solo cubre esta consulta; si se pide otra columna, tiene que ir a
-- >   la tabla por cada fila (Key Lookup o RID Lookup) y la ventaja se pierde.
-- > La consigna pedia un indice agrupado con INCLUDE, pero SQL Server no lo
-- >   permite: el agrupado ya contiene todas las columnas.
DROP INDEX IX_venta_historica_fecha ON dbo.venta_historica;
GO
CREATE NONCLUSTERED INDEX IX_venta_historica_fecha_cubre ON dbo.venta_historica (fecha_venta) INCLUDE (cod_venta, importe);
GO
CHECKPOINT;
DBCC DROPCLEANBUFFERS WITH NO_INFOMSGS;
GO
SELECT cod_venta, fecha_venta, importe FROM dbo.venta_historica WHERE fecha_venta >= '2025-01-01' AND fecha_venta < '2025-02-01';
GO
SELECT cod_venta, fecha_venta, importe FROM dbo.venta_historica WHERE fecha_venta >= '2025-01-01' AND fecha_venta < '2025-02-01';
GO

SET STATISTICS IO, TIME OFF;
GO

-- Los tiempos varían entre equipos y corridas; las lecturas lógicas no.
-- Tamaño de la tabla y del índice que queda
-- > sys.dm_db_partition_stats: paginas usadas por la tabla y por cada indice.
-- >   paginas * 8 / 1024 = MB (cada pagina ocupa 8 KB).
-- >   HEAP = la tabla; NONCLUSTERED = el indice cubriente, que ocupa espacio extra.
SELECT i.name AS indice, i.type_desc AS tipo, SUM(s.used_page_count) AS paginas,
       SUM(s.used_page_count) * 8 / 1024 AS mb
FROM sys.dm_db_partition_stats s
JOIN sys.indexes i ON i.object_id = s.object_id AND i.index_id = s.index_id
WHERE s.object_id = OBJECT_ID('dbo.venta_historica')
GROUP BY i.name, i.type_desc;
GO
