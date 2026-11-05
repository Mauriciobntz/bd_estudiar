--Consultas de negocio avanzadas

-- Se considera VENTA: pedido 'confirmado' con pago 'aprobado'.
-- Se considera COMPRA valida: compra en estado 'recibida'.

-- =============================================================
-- GUIA DE ESTUDIO PARA LA DEFENSA (rama estudio-defensa, no se sube)
-- Las lineas que empiezan con "-- >" son las notas de estudio. Para cada
-- consulta: que pregunta de negocio responde, como la resuelve paso a
-- paso, que hace cada funcion u operador y que resultado se espera con
-- los datos de sql/dml/cargar_datos.sql.
--
-- > Orden en que SQL Server EVALUA un SELECT (no es el orden en que se escribe):
-- >   1 FROM y JOIN, 2 WHERE, 3 GROUP BY, 4 HAVING, 5 SELECT, 6 ORDER BY.
-- >   Por eso un alias definido en el SELECT no se puede usar en WHERE ni en
-- >   HAVING (hay que repetir la expresion), pero si en ORDER BY.
-- > WHERE filtra FILAS antes de agrupar; HAVING filtra GRUPOS despues de agrupar.
-- > Toda columna del SELECT que no este dentro de una funcion de agregado
-- >   (SUM, COUNT, AVG, MAX, MIN) tiene que estar en el GROUP BY.
-- > Las consultas sobre ventas filtran estado = 'confirmado' AND
-- >   estado_pago = 'aprobado': esa es la definicion de VENTA. Un pedido
-- >   pendiente o cancelado no cuenta.
-- > El importe se calcula como SUM(cantidad * precio_unitario_venta): el total
-- >   del pedido no se guarda (RN.10), y precio_unitario_venta ya incluye IVA y
-- >   descuento, congelado al momento de vender (RN.03).
-- > Subconsulta ESCALAR: devuelve un solo valor (una fila, una columna).
-- > Subconsulta CORRELACIONADA: usa una columna de la consulta de afuera, asi
-- >   que conceptualmente se evalua una vez por cada fila de afuera. Una NO
-- >   correlacionada se puede ejecutar sola y se calcula una vez.
-- > Tabla derivada: un SELECT entre parentesis en el FROM, con un alias (AS t).
-- =============================================================
USE smarthome_store;
GO

--   1  Clientes de alto valor: clientes cuyo total comprado supera
--      el promedio de compra por cliente.
--      Tablas: cliente, direccion, localidad, provincia, pedido, detalle_pedido
--      Tecnica: GROUP BY + HAVING con subconsulta escalar (que a su
--      vez usa una tabla derivada) para calcular el promedio.
--      Esperado: 4 clientes; el primero es Tomas Benitez, con 858000.00.
-- ---------------------------------------------------------------
-- > Pregunta: que clientes compraron mas que el cliente promedio?
-- > Paso a paso:
-- >   1. FROM cliente + LEFT JOIN direccion, localidad y provincia: trae la
-- >      ciudad de la direccion PRINCIPAL. Es LEFT para no perder a un cliente
-- >      sin direccion (RN.29 lo permite): saldria con ciudad NULL.
-- >      "dir.principal = 1" va en el ON y no en el WHERE: en el WHERE
-- >      descartaria las filas con NULL y el LEFT JOIN funcionaria como INNER.
-- >   2. INNER JOIN pedido y detalle_pedido: solo quedan clientes con pedidos, y
-- >      cada fila es un renglon vendido.
-- >   3. WHERE: solo ventas (confirmado y aprobado).
-- >   4. GROUP BY: una fila por cliente. Tambien se agrupa por nombre, apellido,
-- >      ciudad y provincia porque aparecen en el SELECT sin agregado.
-- >   5. HAVING: se queda con los clientes cuyo total supera el promedio.
-- > Funciones y operadores:
-- >   c.nombre + ' ' + c.apellido : concatena texto (si una parte es NULL, da NULL).
-- >   COUNT(DISTINCT p.cod_pedido): cuenta pedidos SIN repetir. Hace falta
-- >      DISTINCT porque el JOIN con el detalle repite el pedido en cada renglon.
-- >   SUM(cantidad * precio)      : importe total de todos sus renglones.
-- >   ticket_promedio             : total dividido la cantidad de pedidos.
-- >   MAX(p.fecha_pedido)         : la fecha mas reciente, o sea, el ultimo pedido.
-- >   Subconsulta del HAVING: la de adentro (tabla derivada "t") calcula el total
-- >      de cada cliente y la de afuera saca el AVG de esos totales. Es escalar y
-- >      no correlacionada. Hace falta asi porque SQL Server no permite anidar
-- >      agregados: AVG(SUM(...)) da error.
-- > Esperado: 4 clientes, de mayor a menor: Tomas Benitez (858000.00),
-- >   Camila Ortiz (630000.00), Valentina Diaz (500000.00) y Sofia Acosta (479999.99).
SELECT
    c.cod_cliente, c.nombre + ' ' + c.apellido AS cliente,
    loc.nombre AS ciudad, prov.nombre AS provincia,  COUNT(DISTINCT p.cod_pedido) AS cant_pedidos,
    SUM(dp.cantidad * dp.precio_unitario_venta)          AS total_comprado,
    SUM(dp.cantidad * dp.precio_unitario_venta)
        / COUNT(DISTINCT p.cod_pedido)                   AS ticket_promedio,
    MAX(p.fecha_pedido)                                  AS ultimo_pedido
FROM cliente c
LEFT JOIN direccion dir ON dir.cod_cliente = c.cod_cliente AND dir.principal = 1
LEFT JOIN localidad loc ON loc.cod_localidad = dir.cod_localidad
LEFT JOIN provincia prov ON prov.cod_provincia = loc.cod_provincia
INNER JOIN pedido         p  ON p.cod_cliente = c.cod_cliente   --Solo clientes con pedido
INNER JOIN detalle_pedido dp ON dp.cod_pedido = p.cod_pedido
WHERE p.estado = 'confirmado'
  AND p.estado_pago = 'aprobado'
GROUP BY c.cod_cliente, c.nombre, c.apellido, loc.nombre, prov.nombre
HAVING SUM(dp.cantidad * dp.precio_unitario_venta) >
       (SELECT AVG(t.total_cliente) --Monto promedio
        FROM (SELECT SUM(dp2.cantidad * dp2.precio_unitario_venta) AS total_cliente --Monto comprado por cada cliente
              FROM pedido p2
              INNER JOIN detalle_pedido dp2 ON dp2.cod_pedido = p2.cod_pedido
              WHERE p2.estado = 'confirmado'
                AND p2.estado_pago = 'aprobado'
              GROUP BY p2.cod_cliente) AS t)
ORDER BY total_comprado DESC;


-- 2  Productos con margen bajo: compara la venta NETA (sin IVA)
--      contra el costo promedio ponderado de las compras recibidas
--      y lista los productos con margen menor al minimo indicado.
--      Tablas: detalle_pedido, pedido, producto, categoria y
--              (CTE) detalle_compra + compra
--      Tecnica: CTE + GROUP BY + HAVING con parametro.
--      Supuesto: costo_unitario de compra esta expresado sin IVA.
--      Esperado (margen minimo 25 %): 4 productos; el de menor margen es
--      Funda Notebook, con 13,86 %.
-- ---------------------------------------------------------------
-- > Pregunta: que productos se venden con poca ganancia?
-- > Paso a paso:
-- >   1. DECLARE @margen_minimo: variable con el umbral (25 %). Se cambia el
-- >      valor y se reutiliza la consulta sin tocar el codigo.
-- >   2. WITH costo_prod AS (...): una CTE (expresion de tabla comun), una
-- >      "tabla con nombre" que existe solo durante esta consulta. El ";" que
-- >      cierra el DECLARE es obligatorio antes de un WITH.
-- >      Calcula el costo promedio PONDERADO de cada producto:
-- >      SUM(cantidad * costo) / SUM(cantidad). Ponderado quiere decir que pesa
-- >      mas la compra con mas unidades; AVG(costo_unitario) trataria igual a una
-- >      compra de 1 unidad que a una de 100.
-- >      Solo cuenta compras 'recibida': una pendiente o cancelada no es un costo real.
-- >   3. Consulta principal: renglones vendidos + producto + categoria + la CTE.
-- >      Es INNER JOIN con la CTE: un producto sin compras recibidas no aparece.
-- >   4. venta_neta = SUM(cantidad * precio - iva_monto): se resta el IVA porque
-- >      el costo esta sin IVA; si no, se compararian valores distintos.
-- >   5. margen en % = 100 * (venta neta - costo) / venta neta.
-- >      Se escribe 100.0 y no 100 para que la division sea decimal: entre
-- >      enteros SQL Server trunca (7 / 2 = 3).
-- >   6. El HAVING repite la formula del margen: no puede usar el alias
-- >      margen_producto, porque se evalua antes que el SELECT.
-- >   7. cp.costo_promedio esta en el GROUP BY porque se usa fuera de un SUM.
-- > Funciones:
-- >   ROUND(x, 2): redondea a 2 decimales.
-- >   ORDER BY margen_producto: aca SI se puede usar el alias, porque ORDER BY va ultimo.
-- > Esperado (umbral 25 %): 4 productos, del menor margen al mayor:
-- >   Funda Notebook 13,86 %, Smart TV 50" 14,59 %, Parlante BT portatil 23,59 %
-- >   y Auriculares BT 23,68 %.
DECLARE @margen_minimo DECIMAL(5,2) = 25.00;   -- porcentaje

WITH costo_prod AS (
    SELECT dc.cod_producto,             --Costo promedio de cada producto
           SUM(dc.cantidad * dc.costo_unitario) / SUM(dc.cantidad) AS costo_promedio
    FROM detalle_compra dc
    INNER JOIN compra co ON co.cod_compra = dc.cod_compra
    WHERE co.estado = 'recibida'
    GROUP BY dc.cod_producto
)
SELECT
    pr.cod_producto, pr.nombre AS producto, cat.nombre AS categoria, SUM(dp.cantidad) AS unidades_vendidas,
    SUM(dp.cantidad * dp.precio_unitario_venta - dp.iva_monto) AS venta_neta,
    ROUND(SUM(dp.cantidad) * cp.costo_promedio, 2) AS costo_total,
    ROUND(SUM(dp.cantidad * dp.precio_unitario_venta - dp.iva_monto) - SUM(dp.cantidad) * cp.costo_promedio, 2) AS margen,
    ROUND(100.0 * (SUM(dp.cantidad * dp.precio_unitario_venta - dp.iva_monto)
                   - SUM(dp.cantidad) * cp.costo_promedio)
          / SUM(dp.cantidad * dp.precio_unitario_venta - dp.iva_monto), 2) AS margen_producto
FROM detalle_pedido dp
INNER JOIN pedido     p   ON p.cod_pedido      = dp.cod_pedido
INNER JOIN producto   pr  ON pr.cod_producto   = dp.cod_producto
INNER JOIN categoria  cat ON cat.cod_categoria = pr.cod_categoria
INNER JOIN costo_prod cp  ON cp.cod_producto   = pr.cod_producto
WHERE p.estado = 'confirmado'
  AND p.estado_pago = 'aprobado'
GROUP BY pr.cod_producto, pr.nombre, cat.nombre, cp.costo_promedio
HAVING 100.0 * (SUM(dp.cantidad * dp.precio_unitario_venta - dp.iva_monto)
                - SUM(dp.cantidad) * cp.costo_promedio)
       / SUM(dp.cantidad * dp.precio_unitario_venta - dp.iva_monto) < @margen_minimo
ORDER BY margen_producto;

-- 3  Proveedores principales: proveedores cuyo monto comprado
--      (compras recibidas) supera el promedio por proveedor.
--      Tablas: proveedor, direccion, localidad, provincia, compra, detalle_compra
--      Tecnica: GROUP BY + HAVING con subconsulta escalar.
--      Esperado: 3 proveedores; el primero es Informatica Central S.A., con 7160000.00.
-- ---------------------------------------------------------------
-- > Pregunta: a que proveedores les compramos mas que al proveedor promedio?
-- > Tiene la misma estructura que la consulta 1, del lado de las compras:
-- >   LEFT JOIN a la direccion principal del proveedor (puede no tener),
-- >   INNER JOIN compra y detalle_compra, WHERE estado = 'recibida', GROUP BY
-- >   proveedor y HAVING contra el promedio (tabla derivada con el monto de cada
-- >   proveedor y AVG sobre ella).
-- > Columnas:
-- >   COUNT(DISTINCT co.cod_compra)   : compras sin repetir (el JOIN con el
-- >                                     detalle repite la compra en cada renglon).
-- >   COUNT(DISTINCT dc.cod_producto) : cuantos productos distintos le compramos.
-- >   SUM(dc.cantidad)                : unidades totales.
-- >   SUM(cantidad * costo_unitario)  : monto comprado.
-- > Esperado: 3 proveedores: Informatica Central S.A. (7160000.00),
-- >   ElectroMayorista S.A. (6600000.00) y Linea Blanca Argentina S.A. (4560000.00).
SELECT
    pv.cod_proveedor, pv.razon_social, prov.nombre AS provincia,
    COUNT(DISTINCT co.cod_compra)   AS compras_recibidas,
    COUNT(DISTINCT dc.cod_producto) AS productos_distintos,
    SUM(dc.cantidad)                AS unidades,
    SUM(dc.cantidad * dc.costo_unitario)  AS monto_comprado
FROM proveedor pv             --Proveedores con compra
LEFT JOIN direccion dir ON dir.cod_proveedor = pv.cod_proveedor AND dir.principal = 1
LEFT JOIN localidad loc ON loc.cod_localidad = dir.cod_localidad
LEFT JOIN provincia prov ON prov.cod_provincia = loc.cod_provincia
INNER JOIN compra         co ON co.cod_proveedor = pv.cod_proveedor
INNER JOIN detalle_compra dc ON dc.cod_compra    = co.cod_compra
WHERE co.estado = 'recibida'
GROUP BY pv.cod_proveedor, pv.razon_social, prov.nombre
HAVING SUM(dc.cantidad * dc.costo_unitario) >
       (SELECT AVG(t.monto)  --Promedio de monto comprado a cada proveedor
        FROM (SELECT SUM(dc2.cantidad * dc2.costo_unitario) AS monto  --Monto comprado por cada proveedor
              FROM compra co2
              INNER JOIN detalle_compra dc2 ON dc2.cod_compra = co2.cod_compra
              WHERE co2.estado = 'recibida'
              GROUP BY co2.cod_proveedor) AS t)
ORDER BY monto_comprado DESC;

--   4  Clientes sin compras concretadas
--      Clientes registrados que nunca tuvieron una venta (pedido confirmado y pagado).
--      Tablas: cliente, direccion, localidad, provincia, pedido
--      Tecnica: NOT EXISTS (subconsulta correlacionada) + subconsulta escalar en el SELECT.
--      Esperado: 1 cliente, Federico Molina, cuyo unico pedido esta pendiente.
-- ---------------------------------------------------------------
-- > Pregunta: que clientes se registraron pero nunca concretaron una compra?
-- > Paso a paso:
-- >   1. Recorre TODOS los clientes, con la ciudad de su direccion principal.
-- >   2. NOT EXISTS (...): se queda con el cliente si la subconsulta NO devuelve
-- >      ninguna fila, es decir, si no tiene ninguna venta. Es correlacionada:
-- >      usa c.cod_cliente de la consulta de afuera.
-- >      "SELECT 1": EXISTS solo mira si hay filas, no que columnas devuelven.
-- >   3. La subconsulta del SELECT cuenta TODOS sus pedidos, de cualquier estado,
-- >      para mostrar que el cliente hizo pedidos aunque no se concretaran.
-- > Con LEFT JOIN + IS NULL se obtendria lo mismo; NOT EXISTS expresa
-- >   directamente "no existe una venta" y no tiene el problema de NOT IN con NULL.
-- > Esperado: 1 cliente, Federico Molina (Mendoza), con 1 pedido registrado:
-- >   el 10, que sigue pendiente.
SELECT c.cod_cliente, c.nombre + ' ' + c.apellido AS cliente, loc.nombre AS ciudad, prov.nombre AS provincia, c.fecha_registro,
    (SELECT COUNT(*) FROM pedido p2
     WHERE p2.cod_cliente = c.cod_cliente) AS pedidos_registrados
FROM cliente c
LEFT JOIN direccion dir ON dir.cod_cliente = c.cod_cliente AND dir.principal = 1
LEFT JOIN localidad loc ON loc.cod_localidad = dir.cod_localidad
LEFT JOIN provincia prov ON prov.cod_provincia = loc.cod_provincia
WHERE NOT EXISTS (SELECT 1
                  FROM pedido p
                  WHERE p.cod_cliente = c.cod_cliente
                    AND p.estado = 'confirmado'
                    AND p.estado_pago = 'aprobado')
ORDER BY c.fecha_registro;

--   5  Actividad de cada usuario interno
--      Cuantas operaciones registro cada usuario en pedidos, compras, facturas y auditoria.
--      Tablas: usuario, pedido, compra, factura, auditoria
--      Tecnica: cuatro subconsultas escalares correlacionadas en el SELECT dentro de una
--      tabla derivada, que permite ordenar por el total sumado.
--      Esperado: los 10 usuarios; los 3 de soporte tienen 0 operaciones.
-- ---------------------------------------------------------------
-- > Pregunta: cuanto trabajo registro cada empleado en el sistema?
-- > Paso a paso:
-- >   1. Tabla derivada "t": una fila por usuario, con cuatro subconsultas
-- >      escalares correlacionadas que cuentan sus pedidos despachados, compras,
-- >      facturas emitidas y cambios auditados.
-- >   2. La consulta de afuera suma las cuatro columnas en total_operaciones.
-- >      Hace falta la tabla derivada porque en el mismo SELECT no se puede usar
-- >      un alias recien definido (pedidos_gestionados + ...).
-- >   3. t.* : todas las columnas de la tabla derivada.
-- > Por que subconsultas y no JOIN + COUNT: unir las cuatro tablas a la vez
-- >   combinaria cada pedido con cada compra del mismo usuario, y los conteos
-- >   saldrian multiplicados.
-- > COUNT(*) devuelve 0 cuando no hay filas (no NULL), por eso la suma funciona
-- >   tambien para los usuarios sin actividad.
-- > Esperado: los 10 usuarios. Primero lramirez y afernandez, con 8 operaciones
-- >   cada uno, y despues mgonzalez, con 7. Los 3 de soporte quedan al final con 0.
SELECT t.*, t.pedidos_gestionados + t.compras_registradas
         + t.facturas_emitidas + t.cambios_auditados     AS total_operaciones
FROM (SELECT
          u.cod_usuario,
          u.nombre_usuario,
          u.rol,
          (SELECT COUNT(*) FROM pedido   p  WHERE p.cod_usuario  = u.cod_usuario) AS pedidos_gestionados,
          (SELECT COUNT(*) FROM compra   co WHERE co.cod_usuario = u.cod_usuario) AS compras_registradas,
          (SELECT COUNT(*) FROM factura  f  WHERE f.cod_usuario  = u.cod_usuario) AS facturas_emitidas,
          (SELECT COUNT(*) FROM auditoria a WHERE a.cod_usuario  = u.cod_usuario) AS cambios_auditados
      FROM usuario u) AS t
ORDER BY total_operaciones DESC, t.cod_usuario;

--   6  Clientes que compraron productos de una categoria
--      Cambiar @categoria por el nombre de otra categoria (ej. 'Celulares').
--      Tablas: cliente, direccion, localidad, provincia, pedido, detalle_pedido, producto, categoria
--      Tecnica: IN con subconsultas anidadas en 4 niveles. IN no duplica clientes aunque
--      hayan comprado el producto en varios pedidos.
--      Esperado con 'Audio': 3 clientes, Martin Romero, Joaquin Fernandez y Agustina Rios.
-- ---------------------------------------------------------------
-- > Pregunta: que clientes compraron algo de una categoria dada (por ejemplo, Audio)?
-- > Se lee de ADENTRO hacia AFUERA:
-- >   nivel 4: el codigo de la categoria con ese nombre;
-- >   nivel 3: los productos de esa categoria;
-- >   nivel 2: los pedidos que tienen alguno de esos productos;
-- >   nivel 1: los clientes de esos pedidos, solo si son ventas.
-- > IN (subconsulta): verdadero si el valor esta en el resultado de la subconsulta.
-- >   Ninguna es correlacionada: cada una se podria ejecutar sola.
-- > Ventaja frente a un JOIN: un cliente que compro Audio en dos pedidos aparece
-- >   una sola vez; con JOIN habria que agregar DISTINCT.
-- > Busca la categoria por nombre exacto y solo la categoria directa del
-- >   producto: con 'Electronica' no traeria lo de Audio, que es su subcategoria.
-- > Esperado con 'Audio': 3 clientes: Martin Romero, Joaquin Fernandez y Agustina Rios.
DECLARE @categoria VARCHAR(50) = 'Audio';

SELECT
    c.cod_cliente,    c.nombre + ' ' + c.apellido AS cliente, loc.nombre AS ciudad, prov.nombre AS provincia
FROM cliente c
LEFT JOIN direccion dir ON dir.cod_cliente = c.cod_cliente AND dir.principal = 1
LEFT JOIN localidad loc ON loc.cod_localidad = dir.cod_localidad
LEFT JOIN provincia prov ON prov.cod_provincia = loc.cod_provincia
WHERE c.cod_cliente IN
      (SELECT p.cod_cliente
       FROM pedido p
       WHERE p.estado = 'confirmado'
         AND p.estado_pago = 'aprobado'
         AND p.cod_pedido IN
             (SELECT dp.cod_pedido
              FROM detalle_pedido dp
              WHERE dp.cod_producto IN
                    (SELECT pr.cod_producto
                     FROM producto pr
                     WHERE pr.cod_categoria IN
                           (SELECT cat.cod_categoria
                            FROM categoria cat
                            WHERE cat.nombre = @categoria))))
ORDER BY c.cod_cliente;


--   7  Productos en promocion vigente
--      Productos alcanzados por alguna promocion vigente en @fecha, con el mayor
--      descuento y la mayor cantidad de cuotas disponibles. Para hoy: GETDATE().
--      Tablas: producto, promocion, promocion_producto
--      Tecnica: EXISTS + subconsultas escalares en el SELECT.
--      Esperado al 10/10/2026: 4 productos (Heladera 300L, Funda Notebook,
--      Lavarropas automatico 8kg y Microondas 25L).
-- ---------------------------------------------------------------
-- > Pregunta: que productos tienen una promocion vigente en una fecha, y cual es
-- >   el mejor beneficio de cada uno?
-- > Paso a paso:
-- >   1. WHERE EXISTS: deja solo los productos con al menos una promocion cuyo
-- >      periodo incluye @fecha.
-- >   2. Dos subconsultas escalares correlacionadas en el SELECT: el MAYOR
-- >      descuento y la MAYOR cantidad de cuotas entre sus promociones vigentes.
-- >      Pueden salir de promociones distintas. Se toma el mayor descuento por RN.24.
-- > Funciones y operadores:
-- >   @fecha BETWEEN inicio AND fin: igual a @fecha >= inicio AND @fecha <= fin
-- >      (incluye los dos extremos).
-- >   JOIN a secas es lo mismo que INNER JOIN.
-- >   MAX(): el valor mas alto. Un descuento de .00 indica que esa promocion solo
-- >      da cuotas sin interes.
-- > Esperado al 10/10/2026: 4 productos: Heladera 300L (0 % y 12 cuotas),
-- >   Funda Notebook (35 % y 1 cuota), Lavarropas automatico 8kg (0 % y 12 cuotas)
-- >   y Microondas 25L (15 % y 12 cuotas).
DECLARE @fecha DATETIME = '2026-10-10';

SELECT
    p.cod_producto, p.nombre AS producto, p.precio_lista,
    (SELECT MAX(pm.porcentaje_descuento)
     FROM promocion pm
     INNER JOIN promocion_producto pp ON pp.cod_promocion = pm.cod_promocion
     WHERE pp.cod_producto = p.cod_producto
       AND @fecha BETWEEN pm.fecha_inicio AND pm.fecha_fin) AS mayor_descuento_pct,
    (SELECT MAX(pm.nro_cuotas)
     FROM promocion pm
     JOIN promocion_producto pp ON pp.cod_promocion = pm.cod_promocion
     WHERE pp.cod_producto = p.cod_producto
       AND @fecha BETWEEN pm.fecha_inicio AND pm.fecha_fin) AS max_cuotas
FROM producto p
WHERE EXISTS (SELECT 1
              FROM promocion pm
              INNER JOIN promocion_producto pp ON pp.cod_promocion = pm.cod_promocion
              WHERE pp.cod_producto = p.cod_producto
                AND @fecha BETWEEN pm.fecha_inicio AND pm.fecha_fin)
ORDER BY p.cod_producto;

--   8  Proveedores sin compras recibidas
--      Proveedores dados de alta que todavia no concretaron ninguna compra.
--      Tablas: proveedor, direccion, localidad, provincia, compra
--      Tecnica: NOT EXISTS + subconsulta escalar. Se prefiere a NOT IN porque NOT IN
--      devuelve un resultado vacio si la subconsulta contiene algun NULL.
--      Esperado: 3 proveedores (1, 2 y 10): el 1 solo tiene la compra pendiente,
--      el 10 la cancelada y el 2 ninguna.
-- ---------------------------------------------------------------
-- > Pregunta: que proveedores dados de alta todavia no nos entregaron nada?
-- > Es la misma idea que la consulta 4: NOT EXISTS de una compra 'recibida'.
-- >   La subconsulta del SELECT cuenta todas sus compras, de cualquier estado.
-- > Por que NOT EXISTS y no NOT IN: si la subconsulta de un NOT IN devuelve un
-- >   NULL, "x NOT IN (1, NULL)" da UNKNOWN para todas las filas y la consulta
-- >   queda vacia. NOT EXISTS no tiene ese problema.
-- > Esperado: 3 proveedores: el 1 (1 compra, la 9, pendiente), el 2 (ninguna) y
-- >   el 10 (1 compra, la 10, cancelada).
SELECT
    pv.cod_proveedor, pv.razon_social, prov.nombre AS provincia,
    (SELECT COUNT(*) FROM compra co2
     WHERE co2.cod_proveedor = pv.cod_proveedor) AS compras_registradas
FROM proveedor pv
LEFT JOIN direccion dir ON dir.cod_proveedor = pv.cod_proveedor AND dir.principal = 1
LEFT JOIN localidad loc ON loc.cod_localidad = dir.cod_localidad
LEFT JOIN provincia prov ON prov.cod_provincia = loc.cod_provincia
WHERE NOT EXISTS (SELECT 1
                  FROM compra co
                  WHERE co.cod_proveedor = pv.cod_proveedor
                    AND co.estado = 'recibida')
ORDER BY pv.cod_proveedor;

--   9  Pedido de mayor importe
--      Pedido(s) de venta cuyo importe es el maximo (importe = suma de sus lineas).
--      Tablas: pedido, cliente, detalle_pedido
--      Tecnica: tablas derivadas + subconsulta escalar con MAX en el WHERE.
--      Esperado: el pedido 4, de Tomas Benitez, con 858000.00.
-- ---------------------------------------------------------------
-- > Pregunta: cual fue la venta de mayor importe?
-- > Paso a paso:
-- >   1. Tabla derivada "t": el importe de cada pedido (SUM de sus renglones con
-- >      GROUP BY pedido). Se une al pedido y al cliente.
-- >   2. WHERE: solo ventas, y solo el pedido cuyo importe es igual al MAXIMO.
-- >   3. El maximo sale de otra tabla derivada, "t2" (el importe de cada venta),
-- >      con MAX() sobre ella. No se puede escribir MAX(SUM(...)).
-- > Por que no TOP 1 ... ORDER BY importe DESC: si dos pedidos empataran en el
-- >   maximo, TOP 1 mostraria uno solo; con "= MAX" aparecen todos.
-- > Esperado: el pedido 4, de Tomas Benitez, del 20/07/2026, con 858000.00.
SELECT
    p.cod_pedido, cl.nombre + ' ' + cl.apellido AS cliente, p.fecha_pedido, t.importe
FROM pedido p
INNER JOIN cliente cl ON cl.cod_cliente = p.cod_cliente
INNER JOIN (SELECT dp.cod_pedido,
             SUM(dp.cantidad * dp.precio_unitario_venta) AS importe
             FROM detalle_pedido dp
             GROUP BY dp.cod_pedido) AS t ON t.cod_pedido = p.cod_pedido
WHERE p.estado = 'confirmado'
  AND p.estado_pago = 'aprobado'
  AND t.importe = (SELECT MAX(t2.importe)
                   FROM (SELECT dp2.cod_pedido,
                                SUM(dp2.cantidad * dp2.precio_unitario_venta) AS importe
                         FROM detalle_pedido dp2
                         INNER JOIN pedido p2 ON p2.cod_pedido = dp2.cod_pedido
                         WHERE p2.estado = 'confirmado'
                           AND p2.estado_pago = 'aprobado'
                         GROUP BY dp2.cod_pedido) AS t2);

--  10  Productos a reponer
--      Productos con stock inferior al promedio que ademas tuvieron ventas.
--      Tablas: producto, categoria, detalle_pedido, pedido
--      Tecnica: subconsulta escalar (AVG) y EXISTS en el WHERE + subconsultas en el SELECT.
--      Esperado: 6 productos; el de menor stock es Lavarropas automatico 8kg (5).
-- ---------------------------------------------------------------
-- > Pregunta: que productos conviene reponer? (poco stock y con ventas)
-- > Paso a paso:
-- >   1. WHERE stock < promedio: subconsulta escalar NO correlacionada con el AVG
-- >      del stock de todos los productos; se calcula una sola vez.
-- >      CAST(stock AS DECIMAL(10,2)): stock es INT, y el AVG de enteros devuelve
-- >      un entero truncado. Con el CAST el promedio conserva los decimales.
-- >   2. AND EXISTS: ademas, el producto tuvo al menos una venta.
-- >   3. En el SELECT, dos subconsultas correlacionadas: las unidades vendidas y
-- >      la fecha de la ultima venta.
-- > ORDER BY stock, nombre: primero el de menos stock; si empatan, por nombre.
-- > Esperado: 6 productos, desde Lavarropas automatico 8kg (stock 5) hasta
-- >   Microondas 25L (stock 15).
SELECT
    pr.cod_producto, pr.nombre AS producto, cat.nombre AS categoria, pr.stock,
    (SELECT SUM(dp.cantidad)
     FROM detalle_pedido dp
     INNER JOIN pedido p ON p.cod_pedido = dp.cod_pedido
     WHERE dp.cod_producto = pr.cod_producto
       AND p.estado = 'confirmado'
       AND p.estado_pago = 'aprobado') AS unidades_vendidas,
    (SELECT MAX(p.fecha_pedido)
     FROM detalle_pedido dp
     INNER JOIN pedido p ON p.cod_pedido = dp.cod_pedido
     WHERE dp.cod_producto = pr.cod_producto
       AND p.estado = 'confirmado'
       AND p.estado_pago = 'aprobado') AS ultima_venta
FROM producto pr
INNER JOIN categoria cat ON cat.cod_categoria = pr.cod_categoria
WHERE pr.stock < (SELECT AVG(CAST(p2.stock AS DECIMAL(10,2))) FROM producto p2)
  AND EXISTS (SELECT 1
              FROM detalle_pedido dp2
              INNER JOIN pedido p3 ON p3.cod_pedido = dp2.cod_pedido
              WHERE dp2.cod_producto = pr.cod_producto
                AND p3.estado = 'confirmado'
                AND p3.estado_pago = 'aprobado')
ORDER BY pr.stock, pr.nombre;

--  11  Productos mas caros que todos los de una categoria
--      Productos cuyo precio de lista supera al de CADA producto de @categoria_ref.
--      Tablas: producto, categoria
--      Tecnica: operador > ALL. Atencion: si @categoria_ref no existe, la subconsulta queda
--      vacia y > ALL resulta verdadero para todos los productos.
--      Esperado con 'Linea blanca': 1 producto, Notebook 15.6" Core i5.
-- ---------------------------------------------------------------
-- > Pregunta: que productos son mas caros que TODOS los de una categoria?
-- > "> ALL (subconsulta)": verdadero si el valor supera a CADA valor de la lista,
-- >   o sea, al maximo. Equivale a "> (SELECT MAX(...))".
-- >   "> ANY" seria "mayor que alguno", o sea, mayor que el minimo.
-- > Trampa: si la categoria no existe, la lista queda vacia, y "> ALL" sobre una
-- >   lista vacia es verdadero: devolveria todos los productos. Con MAX no pasa:
-- >   el MAX de nada es NULL y la comparacion no devuelve filas.
-- > N'...': la N indica texto Unicode (NVARCHAR), necesario por la tilde.
-- > Esperado con 'Linea blanca': 1 producto, Notebook 15.6" Core i5 (769230.77),
-- >   mas caro que el lavarropas (520661.16) y la heladera (396694.21).
DECLARE @categoria_ref NVARCHAR(50) = N'Línea blanca';

SELECT
    pr.cod_producto,
    pr.nombre                                            AS producto,
    cat.nombre                                           AS categoria,
    pr.precio_lista
FROM producto pr
INNER JOIN categoria cat ON cat.cod_categoria = pr.cod_categoria
WHERE pr.precio_lista > ALL (SELECT p2.precio_lista
                             FROM producto p2
                             INNER JOIN categoria c2 ON c2.cod_categoria = p2.cod_categoria
                             WHERE c2.nombre = @categoria_ref)
ORDER BY pr.precio_lista DESC;

--  12  Ultimo pedido de cada cliente
--      Estado del ultimo pedido (cualquiera sea su estado) de cada cliente.
--      Tablas: pedido, cliente
--      Tecnica: subconsulta escalar correlacionada con MAX en el WHERE.
--      Esperado: 10 filas, una por cliente; la primera es el pedido 12.
-- ---------------------------------------------------------------
-- > Pregunta: en que estado esta el ultimo pedido de cada cliente?
-- > Subconsulta correlacionada en el WHERE: para cada pedido p busca la fecha
-- >   maxima de los pedidos del MISMO cliente (p2.cod_cliente = p.cod_cliente), y
-- >   se queda con el pedido si su fecha es esa.
-- > No filtra por estado: muestra el ultimo pedido, sea venta, pendiente o cancelado.
-- > Solo aparecen los clientes con pedidos, porque se parte de la tabla pedido.
-- > Si un cliente tuviera dos pedidos con la misma fecha y hora, saldrian los dos.
-- > Esperado: 10 filas, de la mas reciente a la mas vieja. La primera es el
-- >   pedido 12, de Martin Romero; Lucia Gomez aparece con el 11, cancelado.
SELECT
    cl.cod_cliente, cl.nombre + ' ' + cl.apellido AS cliente, p.cod_pedido, p.fecha_pedido,
    p.estado, p.estado_pago
FROM pedido p
INNER JOIN cliente cl ON cl.cod_cliente = p.cod_cliente
WHERE p.fecha_pedido = (SELECT MAX(p2.fecha_pedido)
                        FROM pedido p2
                        WHERE p2.cod_cliente = p.cod_cliente)
ORDER BY p.fecha_pedido DESC;


--  13  Facturas por encima del promedio de su tipo
--      Facturas cuyo total supera el promedio de las facturas del mismo tipo (A, B o C).
--      Tablas: factura
--      Tecnica: subconsulta escalar correlacionada con AVG en el WHERE y en el SELECT.
--      Esperado: 5 facturas, la 3 (tipo A) y las 4, 5, 7 y 9 (tipo B).
-- ---------------------------------------------------------------
-- > Pregunta: que facturas superan el promedio de las de su mismo tipo (A, B o C)?
-- > Subconsulta correlacionada en el WHERE: para cada factura f calcula el
-- >   AVG(total) de las facturas del mismo tipo_comprobante. Es correlacionada
-- >   porque el promedio depende del tipo de la fila de afuera.
-- > La misma subconsulta, en el SELECT, muestra ese promedio para comparar.
-- > Numero de comprobante con el formato 0001-00000004:
-- >   CAST(numero AS VARCHAR(8)) : convierte el numero en texto.
-- >   '00000000' + texto          : le agrega ceros adelante.
-- >   RIGHT(texto, 8)             : se queda con los ultimos 8 caracteres.
-- > Esperado: 5 facturas: la 3 (tipo A, 479999.99 contra un promedio de 365000.00)
-- >   y la 4, la 7, la 5 y la 9 (tipo B, contra 367231.25), de mayor a menor.
SELECT
    f.cod_factura,
    f.tipo_comprobante,
    RIGHT('0000'     + CAST(f.punto_venta AS VARCHAR(4)), 4) + '-' +
    RIGHT('00000000' + CAST(f.numero      AS VARCHAR(8)), 8)  AS nro_comprobante,
    f.total,
    ROUND((SELECT AVG(f3.total)
           FROM factura f3
           WHERE f3.tipo_comprobante = f.tipo_comprobante), 2) AS promedio_del_tipo
FROM factura f
WHERE f.total > (SELECT AVG(f2.total)
                 FROM factura f2
                 WHERE f2.tipo_comprobante = f.tipo_comprobante)
ORDER BY f.tipo_comprobante, f.total DESC;
GO
