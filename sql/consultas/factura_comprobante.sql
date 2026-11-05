--Factura / Comprobante de venta

-- Consolida el encabezado y el detalle de la factura de un pedido.
-- Cambiar @cod_pedido por el pedido a consultar (ej. 1, 3, 8).
-- precio_unitario_venta incluye IVA; iva_monto es el IVA total del renglon.

-- =============================================================
-- GUIA DE ESTUDIO PARA LA DEFENSA (rama estudio-defensa, no se sube)
-- Las lineas "-- >" son notas de estudio.
-- > Para que sirve: arma la factura de un pedido como se imprimiria, en dos
-- >   consultas: el encabezado (una fila) y el detalle (un renglon por producto).
-- > Como se relacionan los montos: precio_unitario_venta YA incluye el IVA
-- >   (y el descuento), congelado al vender (RN.03 y RN.19). iva_monto es el IVA
-- >   contenido en el renglon, asi que neto = cantidad * precio - iva_monto.
-- >   Ejemplo del pedido 4, Notebook al 10,5 %: 850000.00 con IVA incluido =
-- >   769230.77 neto (850000 / 1,105) + 80769.23 de IVA.
-- > En la factura: subtotal (neto) + iva_total = total.
-- >   Pedido 4: 775842.34 + 82157.66 = 858000.00.
-- =============================================================
USE smarthome_store;
GO

-- > DECLARE @cod_pedido INT = 4: variable con el pedido a facturar. El ";" la
-- >   separa de la consulta. Vale hasta el proximo GO: por eso las dos consultas
-- >   estan en el mismo lote.
DECLARE @cod_pedido INT = 4;

--   1  Encabezado del comprobante
--      Datos fiscales de la factura, datos del cliente y del pedido, y totales.
--      Tablas: factura, pedido, cliente, metodo_pago, usuario
--      Tecnica: INNER JOIN de 5 tablas + subconsulta escalar que recalcula el total
--      desde el detalle para controlar que coincida con el total registrado.
--      Esperado para el pedido 4: factura B 0001-00000004 de Tomas Benitez,
--      total 858000.00, igual a total_calculado.
-- ---------------------------------------------------------------
-- > Paso a paso:
-- >   1. FROM factura + INNER JOIN pedido, cliente, metodo_pago y usuario: cada
-- >      JOIN va por la clave foranea (f.cod_pedido, p.cod_cliente, ...). Son
-- >      INNER porque todas esas FK son NOT NULL: siempre hay fila del otro lado.
-- >   2. WHERE f.cod_pedido = @cod_pedido: una sola factura, porque hay una por
-- >      pedido (UQ_factura_pedido, RN.17).
-- > Funciones y operadores:
-- >   CAST(f.punto_venta AS VARCHAR(4)): convierte el numero en texto.
-- >   RIGHT('0000' + texto, 4): agrega ceros adelante y se queda con los ultimos
-- >      4 caracteres: 1 -> '0001'. Lo mismo con 8 digitos para el numero.
-- >      Resultado: '0001-00000004', el formato de un comprobante argentino.
-- >   c.nombre + ' ' + c.apellido: concatena el nombre completo.
-- >   domicilio_entrega: concatena la direccion COPIADA en el pedido, no la del
-- >      cliente hoy (RN.04): si el cliente se muda, la factura no cambia.
-- >   u.nombre_usuario AS emitida_por: el empleado que emitio la factura (RN.21).
-- >   total_calculado: subconsulta escalar correlacionada que vuelve a sumar los
-- >      renglones del pedido. Es un CONTROL: debe coincidir con f.total.
-- > Esperado para el pedido 4: factura B 0001-00000004 del 20/07/2026 de Tomas
-- >   Benitez, Consumidor Final, DNI 40221334, pagada con MODO y emitida por
-- >   mgonzalez; subtotal 775842.34, IVA 82157.66, total 858000.00 y
-- >   total_calculado 858000.00.
SELECT
    f.tipo_comprobante,
    RIGHT('0000'     + CAST(f.punto_venta AS VARCHAR(4)), 4) + '-' +
    RIGHT('00000000' + CAST(f.numero      AS VARCHAR(8)), 8)  AS nro_comprobante,
    f.fecha_emision, f.cae, f.fecha_vto_cae,
    c.nombre + ' ' + c.apellido                               AS cliente,
    f.razon_social, f.cond_iva_cliente, f.tipo_documento_cliente, f.nro_documento_cliente,
    p.calle + ' ' + p.numero + ', ' + p.ciudad + ', ' + p.provincia
        + ' (' + p.cod_postal + ')'                           AS domicilio_entrega,
    p.cod_pedido, p.fecha_pedido, mp.nombre                   AS metodo_pago,
    u.nombre_usuario                                          AS emitida_por,
    f.subtotal, f.iva_total, f.total,
    (SELECT SUM(dp.cantidad * dp.precio_unitario_venta)
     FROM detalle_pedido dp
     WHERE dp.cod_pedido = p.cod_pedido)                      AS total_calculado
FROM factura f
INNER JOIN pedido      p  ON p.cod_pedido       = f.cod_pedido
INNER JOIN cliente     c  ON c.cod_cliente      = p.cod_cliente
INNER JOIN metodo_pago mp ON mp.cod_metodo_pago = p.cod_metodo_pago
INNER JOIN usuario     u  ON u.cod_usuario      = f.cod_usuario
WHERE f.cod_pedido = @cod_pedido;

--   2  Detalle del comprobante
--      Un renglon por producto con subtotal, neto e IVA, y el total acumulado
--      renglon a renglon hasta llegar al total de la factura.
--      Tablas: factura, detalle_pedido, producto
--      Tecnica: INNER JOIN + columnas calculadas + SUM() OVER (ORDER BY item)
--      para el total acumulado.
--      Esperado para el pedido 4: 2 renglones (Notebook 15.6" Core i5 y Funda
--      Notebook); el total acumulado termina en 858000.00, el total de la factura.
-- ---------------------------------------------------------------
-- > Paso a paso:
-- >   1. FROM factura + detalle_pedido + producto: un renglon por producto del pedido.
-- >   2. Columnas calculadas por renglon:
-- >      subtotal_renglon = cantidad * precio (con IVA),
-- >      neto_renglon     = subtotal - iva_monto,
-- >      iva_renglon      = iva_monto.
-- >   3. total_acumulado: SUM(...) OVER (ORDER BY dp.item ROWS UNBOUNDED PRECEDING).
-- >      Es una FUNCION DE VENTANA: suma sin agrupar, asi que cada renglon sigue
-- >      siendo una fila. "ROWS UNBOUNDED PRECEDING" significa desde el primer
-- >      renglon hasta el actual: es un total corrido que, en el ultimo renglon,
-- >      da el total de la factura.
-- >      Diferencia con GROUP BY: GROUP BY junta las filas en una sola; OVER
-- >      conserva todas las filas y le agrega el calculo a cada una.
-- >   4. ORDER BY dp.item: los renglones en el orden en que se cargaron.
-- > Esperado para el pedido 4: 2 renglones:
-- >   1 Notebook 15.6" Core i5, 1 x 850000.00 al 10,5 %: neto 769230.77,
-- >     IVA 80769.23, acumulado 850000.00;
-- >   2 Funda Notebook, 1 x 8000.00 al 21 %: neto 6611.57, IVA 1388.43,
-- >     acumulado 858000.00 (igual al total de la factura).
SELECT
    dp.item,
    pr.cod_producto,
    pr.nombre                                                 AS producto,
    dp.cantidad,
    dp.precio_unitario_venta,
    dp.alicuota_iva,
    dp.cantidad * dp.precio_unitario_venta                    AS subtotal_renglon,
    dp.cantidad * dp.precio_unitario_venta - dp.iva_monto     AS neto_renglon,
    dp.iva_monto                                              AS iva_renglon,
    SUM(dp.cantidad * dp.precio_unitario_venta)
        OVER (ORDER BY dp.item ROWS UNBOUNDED PRECEDING)      AS total_acumulado
FROM factura f
INNER JOIN detalle_pedido dp ON dp.cod_pedido   = f.cod_pedido
INNER JOIN producto       pr ON pr.cod_producto = dp.cod_producto
WHERE f.cod_pedido = @cod_pedido
ORDER BY dp.item;
GO
