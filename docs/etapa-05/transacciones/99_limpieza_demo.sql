-- Transacciones: limpieza de emergencia de los datos de demostracion
-- SmartHome Store (equipo 37) - SQL Server
--
-- Las pruebas T7 y T10 de scripts.sql ya eliminan sus propios datos. Este
-- script es una red de seguridad: sirve si una prueba se interrumpio a mitad
-- de camino y quedaron pedidos de prueba.
--
-- CUIDADO: elimina TODOS los pedidos con codigo >= @desde que no tengan
-- factura. Los pedidos originales de la carga inicial son 1 a 12, asi que
-- @desde = 13 solo alcanza a los creados despues. Ajustar si hace falta.
-- Devuelve al stock las unidades de los pedidos CONFIRMADOS que se borran
-- (un pedido pendiente no desconto stock y uno cancelado ya lo repuso).

USE smarthome_store;
GO
SET NOCOUNT ON;

-- > @desde = 13: los pedidos 1 a 12 son de la carga inicial y nunca se tocan.
DECLARE @desde INT = 13;

-- > Todo va en una transacción: o se devuelve el stock Y se borran los pedidos, o no pasa
-- >   nada (si fallara a mitad, el CATCH hace ROLLBACK y muestra el error).
BEGIN TRY
    BEGIN TRANSACTION;

        -- Se devuelve el stock de los renglones que van a borrarse. Se suma
        -- por producto: un UPDATE ... FROM aplica una sola fila por producto,
        -- asi que si varios pedidos llevan el mismo producto hay que agruparlos.
        -- > El orden importa: primero el stock y después el DELETE. Si se borraran antes los
        -- >   pedidos, ya no habría detalle para saber cuántas unidades devolver.
        -- > Solo los pedidos CONFIRMADOS descontaron stock; un pendiente no lo tocó y un cancelado
        -- >   ya lo repuso (sp_cancelar_pedido). Los facturados no se tocan (comprobante fiscal).
        UPDATE p
        SET p.stock = p.stock + x.cantidad
        FROM dbo.producto p
        INNER JOIN (SELECT d.cod_producto, SUM(d.cantidad) AS cantidad
                    FROM dbo.detalle_pedido d
                    INNER JOIN dbo.pedido pe ON pe.cod_pedido = d.cod_pedido
                    WHERE pe.cod_pedido >= @desde
                      AND pe.estado = 'confirmado'
                      AND NOT EXISTS (SELECT 1 FROM dbo.factura f WHERE f.cod_pedido = pe.cod_pedido)
                    GROUP BY d.cod_producto) x ON x.cod_producto = p.cod_producto;

        -- El detalle se elimina en cascada con el pedido
        -- > detalle_pedido tiene ON DELETE CASCADE hacia pedido: al borrar el pedido se borran
        -- >   sus renglones. factura tiene ON DELETE NO ACTION: por eso se excluyen los facturados.
        DELETE FROM dbo.pedido
        WHERE cod_pedido >= @desde
          AND NOT EXISTS (SELECT 1 FROM dbo.factura f WHERE f.cod_pedido = pedido.cod_pedido);

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    SELECT ERROR_NUMBER() AS error, ERROR_MESSAGE() AS mensaje;
END CATCH;

-- Esperado con la carga inicial: 12 pedidos y 18 detalles
-- > Si quedó algún pedido de prueba, después de este script el stock del producto 2 vuelve a 40.
SELECT (SELECT COUNT(*) FROM dbo.pedido) AS pedidos,
       (SELECT COUNT(*) FROM dbo.detalle_pedido) AS lineas;
GO
