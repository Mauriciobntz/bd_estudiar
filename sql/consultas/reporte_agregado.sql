-- Reporte agregado de ventas por categoria
-- Total vendido por categoria de producto en un rango de fechas.
-- Se considera VENTA: pedido 'confirmado' con pago 'aprobado'.
-- Cambiar @fecha_desde y @fecha_hasta por el rango a consultar (ambas fechas incluidas).

-- =============================================================
-- GUIA DE ESTUDIO PARA LA DEFENSA (rama estudio-defensa, no se sube)
-- Las lineas "-- >" son notas de estudio.
-- > Para que sirve: cuanto se vendio de cada categoria en un periodo. Es un
-- >   reporte AGREGADO: muchas filas de detalle se resumen en una por categoria.
-- > Las dos consultas son iguales salvo el nivel: la 1 agrupa por la categoria
-- >   directa del producto (Audio) y la 2 por la categoria principal (Electronica).
-- =============================================================
USE smarthome_store;
GO

-- > Variables de fecha: el periodo es del 01/07/2026 al 30/09/2026, ambos incluidos.
DECLARE @fecha_desde DATE = '2026-07-01';
DECLARE @fecha_hasta DATE = '2026-09-30';

-- ---------------------------------------------------------------
--   1  Ventas por categoria
--      Cantidad de ventas, unidades e importes vendidos en cada categoria
--      (la categoria a la que pertenece directamente el producto).
--      Tablas: pedido, detalle_pedido, producto, categoria
--      Tecnica: INNER JOIN + GROUP BY + COUNT(DISTINCT) y SUM.
--      Esperado (01/07/2026 al 30/09/2026): 8 categorias; la primera es
--      Linea blanca, con 1109999.99.
-- ---------------------------------------------------------------
-- > Paso a paso:
-- >   1. FROM pedido + detalle_pedido + producto + categoria: cada fila es un
-- >      renglon vendido, con la categoria de su producto.
-- >   2. WHERE: solo ventas (confirmado y aprobado) dentro del periodo.
-- >      "fecha_pedido < DATEADD(DAY, 1, @fecha_hasta)": fecha_pedido es DATETIME
-- >      (tiene hora). Con "<= '2026-09-30'" se perderia un pedido del 30/09 a
-- >      las 15:00, porque '2026-09-30' significa las 00:00. Sumando un dia y
-- >      usando "<" entra todo el 30/09.
-- >      DATEADD(DAY, 1, fecha): suma 1 dia a la fecha.
-- >   3. GROUP BY categoria: una fila por categoria.
-- > Columnas:
-- >   COUNT(DISTINCT p.cod_pedido): cantidad de ventas sin repetir; un pedido con
-- >      dos productos de la misma categoria cuenta una vez.
-- >   SUM(dp.cantidad)            : unidades vendidas.
-- >   total_vendido               : SUM(cantidad * precio), con IVA.
-- >   total_neto                  : lo mismo menos el IVA (iva_monto).
-- > ORDER BY total_vendido DESC: de la categoria que mas vendio a la que menos.
-- > Esperado: 8 categorias. Linea blanca 1109999.99 (2 ventas), Notebooks
-- >   850000.00, Celulares 500000.00, Televisores 350000.00, Informatica 225000.00,
-- >   Pequenos electrodomesticos 170000.00, Audio 105000.01 (3 ventas) y
-- >   Accesorios 23600.00 (3 ventas, 4 unidades).
SELECT
    cat.cod_categoria,
    cat.nombre                                                AS categoria,
    COUNT(DISTINCT p.cod_pedido)                              AS cant_ventas,
    SUM(dp.cantidad)                                          AS unidades_vendidas,
    SUM(dp.cantidad * dp.precio_unitario_venta)               AS total_vendido,
    SUM(dp.cantidad * dp.precio_unitario_venta - dp.iva_monto) AS total_neto
FROM pedido p
INNER JOIN detalle_pedido dp  ON dp.cod_pedido    = p.cod_pedido
INNER JOIN producto       pr  ON pr.cod_producto  = dp.cod_producto
INNER JOIN categoria      cat ON cat.cod_categoria = pr.cod_categoria
WHERE p.estado = 'confirmado'
  AND p.estado_pago = 'aprobado'
  AND p.fecha_pedido >= @fecha_desde
  AND p.fecha_pedido <  DATEADD(DAY, 1, @fecha_hasta)   -- incluye todo el dia @fecha_hasta
GROUP BY cat.cod_categoria, cat.nombre
ORDER BY total_vendido DESC;

-- ---------------------------------------------------------------
--   2  Ventas por categoria principal
--      Mismo reporte, pero sumando cada subcategoria dentro de su categoria padre
--      (ej. Audio y Televisores dentro de Electronica).
--      Tablas: pedido, detalle_pedido, producto, categoria (dos veces: hija y padre)
--      Tecnica: LEFT JOIN de categoria consigo misma + COALESCE + GROUP BY.
--      Esperado: 5 categorias principales; la primera es Electrodomesticos,
--      con 1279999.99.
-- ---------------------------------------------------------------
-- > Paso a paso: igual que la consulta 1, mas un segundo JOIN con categoria.
-- >   LEFT JOIN categoria padre ON padre.cod_categoria = cat.cod_categoria_padre:
-- >     la tabla categoria se une CONSIGO MISMA (autorrelacion) para encontrar la
-- >     categoria padre. Se usan dos alias (cat y padre) para distinguirlas.
-- >     Es LEFT porque una categoria principal no tiene padre (NULL); con INNER
-- >     se perderian sus ventas.
-- >   COALESCE(padre.nombre, cat.nombre): devuelve el primer valor no NULL. Si
-- >     tiene padre, toma el padre (Audio -> Electronica); si no, la propia
-- >     categoria (Celulares -> Celulares).
-- >   GROUP BY repite las expresiones COALESCE: no se puede agrupar por el alias.
-- > Esperado: 5 categorias principales. Electrodomesticos 1279999.99 (Linea blanca
-- >   + Pequenos electrodomesticos), Informatica 1075000.00 (Informatica + Notebooks),
-- >   Celulares 500000.00, Electronica 455000.01 (Televisores + Audio) y
-- >   Accesorios 23600.00. La suma da lo mismo que la consulta 1: solo cambia el
-- >   nivel de agrupacion.
SELECT
    COALESCE(padre.cod_categoria, cat.cod_categoria)          AS cod_categoria,
    COALESCE(padre.nombre, cat.nombre)                        AS categoria_principal,
    COUNT(DISTINCT p.cod_pedido)                              AS cant_ventas,
    SUM(dp.cantidad)                                          AS unidades_vendidas,
    SUM(dp.cantidad * dp.precio_unitario_venta)               AS total_vendido,
    SUM(dp.cantidad * dp.precio_unitario_venta - dp.iva_monto) AS total_neto
FROM pedido p
INNER JOIN detalle_pedido dp    ON dp.cod_pedido      = p.cod_pedido
INNER JOIN producto       pr    ON pr.cod_producto    = dp.cod_producto
INNER JOIN categoria      cat   ON cat.cod_categoria  = pr.cod_categoria
LEFT  JOIN categoria      padre ON padre.cod_categoria = cat.cod_categoria_padre
WHERE p.estado = 'confirmado'
  AND p.estado_pago = 'aprobado'
  AND p.fecha_pedido >= @fecha_desde
  AND p.fecha_pedido <  DATEADD(DAY, 1, @fecha_hasta)
GROUP BY COALESCE(padre.cod_categoria, cat.cod_categoria), COALESCE(padre.nombre, cat.nombre)
ORDER BY total_vendido DESC;
GO