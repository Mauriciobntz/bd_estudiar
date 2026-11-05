-- =============================================================
-- ETAPA V - Tema 1: Funciones y procedimientos almacenados
-- Objetos que cree:
--   tipo_items_pedido         tipo tabla para pasar los productos de una venta
--   fn_descuento_vigente      mayor descuento de promocion vigente de un producto (RN.24)
--   fn_precio_final           precio con IVA y descuento, el que se congela en el detalle (RN.19, RN.24, RN.28)
--   fn_total_pedido           total de un pedido, calculado desde el detalle (RN.10)
--   sp_registrar_venta_completa  registra pedido + detalle + baja de stock en una sola operacion
-- =============================================================

-- =============================================================
-- GUIA DE ESTUDIO PARA LA DEFENSA (rama estudio-defensa, no se sube)
-- Las lineas "-- >" son notas de estudio.
-- > FUNCION vs PROCEDIMIENTO:
-- >   Funcion: devuelve un valor (escalar) o una tabla, se usa DENTRO de una
-- >     consulta (SELECT dbo.fn_x(...)) y NO puede modificar datos (ni INSERT,
-- >     ni UPDATE, ni transacciones). Siempre se llama con el esquema: dbo.fn_x.
-- >   Procedimiento: se ejecuta con EXEC, puede modificar datos, manejar
-- >     transacciones y errores, y devolver valores con parametros OUTPUT.
-- > Para que sirven: la regla de negocio queda en UN lugar (por ejemplo, como se
-- >   calcula el precio final) y la aplicacion no necesita permisos sobre las
-- >   tablas, solo sobre el procedimiento (ver el tema de seguridad).
-- > CREATE OR ALTER: crea el objeto o lo reemplaza si ya existe, asi el script
-- >   se puede ejecutar varias veces. CREATE FUNCTION/PROCEDURE tiene que ser la
-- >   primera sentencia del lote: por eso hay un GO antes de cada uno.
-- =============================================================
USE smarthome_store;
GO

-- -------------------------------------------------------------
-- Tipo tabla: lista de productos y cantidades de una venta
-- -------------------------------------------------------------
-- > TIPO TABLA: define la "forma" de una tabla para usarla como parametro. Asi
-- >   una venta recibe todos sus productos en una sola llamada, en vez de llamar
-- >   una vez por producto.
-- >   PRIMARY KEY (cod_producto): un producto no se repite dentro de la venta.
-- >   CHECK (cantidad > 0): no se puede vender 0 ni una cantidad negativa.
-- > IF TYPE_ID(...) IS NULL: lo crea solo si no existe. No hay CREATE OR ALTER
-- >   TYPE, y un tipo que ya usa un procedimiento no se puede borrar.
IF TYPE_ID('dbo.tipo_items_pedido') IS NULL
    CREATE TYPE dbo.tipo_items_pedido AS TABLE
    (
        cod_producto INT NOT NULL PRIMARY KEY,
        cantidad     INT NOT NULL CHECK (cantidad > 0)
    );
GO

-- -------------------------------------------------------------
-- Funcion 1: descuento vigente de un producto en una fecha
-- Si el producto tiene mas de una promocion vigente, se aplica
-- la de mayor descuento (RN.24). Las promociones que solo
-- ofrecen cuotas (porcentaje 0) no cuentan como descuento.
-- Devuelve 0 si no hay promocion con descuento.
-- -------------------------------------------------------------
-- > fn_descuento_vigente(producto, fecha) -> DECIMAL(5,2), por ejemplo 35.00
-- >   1. Junta las promociones del producto (promocion_producto) cuyo periodo
-- >      incluye la fecha (BETWEEN incluye los dos extremos).
-- >   2. MAX(porcentaje_descuento): si hay varias vigentes, la de MAYOR descuento
-- >      (RN.24). Una promocion que solo da cuotas tiene 0 y no gana.
-- >   3. ISNULL(x, 0): si no hay ninguna promocion, MAX devuelve NULL y la
-- >      funcion devuelve 0. Asi el precio final no queda NULL.
-- > Es una funcion ESCALAR: devuelve un solo valor.
-- > Ejemplo: Funda Notebook (producto 4) el 20/09/2026 -> 35.00.
CREATE OR ALTER FUNCTION dbo.fn_descuento_vigente
(
    @cod_producto INT,
    @fecha        DATETIME
)
RETURNS DECIMAL(5,2)
AS
BEGIN
    RETURN ISNULL(
        (SELECT MAX(pr.porcentaje_descuento)
         FROM dbo.promocion pr
         INNER JOIN dbo.promocion_producto pp ON pp.cod_promocion = pr.cod_promocion
         WHERE pp.cod_producto = @cod_producto
           AND @fecha BETWEEN pr.fecha_inicio AND pr.fecha_fin),
        0);
END;
GO

-- -------------------------------------------------------------
-- Funcion 2: precio final de un producto en una fecha
-- precio_lista es neto (RN.19): se le suma el IVA del producto
-- y despues se aplica el descuento vigente.
-- Devuelve NULL si el producto no existe.
-- -------------------------------------------------------------
-- > fn_precio_final(producto, fecha) -> DECIMAL(10,2): el precio que paga el cliente.
-- >   precio_lista (neto, RN.19) * (1 + IVA / 100) * (1 - descuento / 100)
-- >   Primero se suma el IVA y despues se aplica el descuento. ROUND(..., 2) deja
-- >   2 decimales, como un importe.
-- >   Llama a otra funcion (fn_descuento_vigente): las funciones se pueden anidar.
-- >   SELECT @precio = ...: asigna el resultado de la consulta a la variable. Si el
-- >   producto no existe, no hay fila, la variable queda NULL y devuelve NULL.
-- > Ejemplo: Funda Notebook el 20/09/2026: 6611.57 * 1,21 * 0,65 = 5200.00.
-- >   Sin promocion seria 6611.57 * 1,21 = 8000.00.
CREATE OR ALTER FUNCTION dbo.fn_precio_final
(
    @cod_producto INT,
    @fecha        DATETIME
)
RETURNS DECIMAL(10,2)
AS
BEGIN
    DECLARE @precio DECIMAL(10,2);

    SELECT @precio = ROUND(
               p.precio_lista
               * (1 + a.porcentaje / 100)
               * (1 - dbo.fn_descuento_vigente(p.cod_producto, @fecha) / 100),
               2)
    FROM dbo.producto p
    INNER JOIN dbo.alicuota_iva a ON a.cod_alicuota = p.cod_alicuota
    WHERE p.cod_producto = @cod_producto;

    RETURN @precio;
END;
GO

-- -------------------------------------------------------------
-- Funcion 3: total de un pedido (con IVA)
-- El total no se guarda, se calcula desde el detalle (RN.10).
-- Devuelve 0 si el pedido no existe o no tiene renglones.
-- -------------------------------------------------------------
-- > fn_total_pedido(pedido) -> DECIMAL(12,2): el total de un pedido (RN.10).
-- >   SUM(cantidad * precio_unitario_venta) de sus renglones. Usa el precio
-- >   CONGELADO del detalle, no el precio actual del producto: el total de una
-- >   venta vieja no cambia aunque cambie el catalogo.
-- >   ISNULL(..., 0): un pedido inexistente o sin renglones da 0 y no NULL.
-- > Ejemplo: pedido 1 -> 245000.00.
CREATE OR ALTER FUNCTION dbo.fn_total_pedido
(
    @cod_pedido INT
)
RETURNS DECIMAL(12,2)
AS
BEGIN
    RETURN ISNULL(
        (SELECT SUM(cantidad * precio_unitario_venta)
         FROM dbo.detalle_pedido
         WHERE cod_pedido = @cod_pedido),
        0);
END;
GO

-- -------------------------------------------------------------
-- Procedimiento: registrar una venta completa
-- Pasos:
--   1. Validar cliente, direccion, metodo de pago, referencia de pago y productos.
--   2. Verificar stock de todos los productos (RN.11).
--   3. Insertar el pedido confirmado/aprobado, con la direccion principal
--      del cliente o la indicada en @cod_direccion (RN.04) y fecha actual (RN.16).
--   4. Insertar el detalle congelando precio, alicuota e IVA (RN.03, RN.19, RN.28).
--   5. Descontar el stock (RN.09).
-- Si algo falla se deshace todo y se re-lanza el error.
--
-- Codigos de error propios:
--   50001 cliente inexistente o inactivo
--   50002 metodo de pago inexistente
--   50003 la venta no tiene productos
--   50004 producto inexistente o inactivo
--   50005 stock insuficiente
--   50006 falta la referencia de la transaccion de pago
--   50007 la direccion no existe o no es del cliente
-- -------------------------------------------------------------
-- > sp_registrar_venta_completa: registra una venta entera como UNA operacion.
-- > Parametros:
-- >   @items dbo.tipo_items_pedido READONLY: la lista de productos. Los
-- >     parametros de tipo tabla tienen que ser READONLY.
-- >   @cod_pedido INT OUTPUT: parametro de SALIDA; el procedimiento devuelve ahi
-- >     el codigo del pedido creado.
-- >   @cod_direccion INT = NULL: parametro OPCIONAL; si no se pasa, vale NULL y se
-- >     usa la direccion principal.
-- > Por que una transaccion: pedido, detalle y stock se cambian juntos o no se
-- >   cambia nada. Si fallara entre el pedido y el detalle, quedaria un pedido sin
-- >   renglones; si fallara despues del detalle, se venderia sin bajar el stock.
CREATE OR ALTER PROCEDURE dbo.sp_registrar_venta_completa
    @cod_cliente     INT,
    @cod_metodo_pago INT,
    @ref_transaccion VARCHAR(50),
    @items           dbo.tipo_items_pedido READONLY,
    @cod_pedido      INT OUTPUT,
    @cod_direccion   INT = NULL
AS
BEGIN
-- > SET NOCOUNT ON: no envia los mensajes "(n rows affected)".
-- > SET XACT_ABORT ON: ante CUALQUIER error, SQL Server aborta y revierte toda la
-- >   transaccion. Sin esto, algunos errores (por ejemplo, una FK violada) solo
-- >   cancelan la sentencia y la transaccion sigue abierta con cambios a medias.
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- Si quien llama ya abrio una transaccion, no abrimos otra.
-- > @@TRANCOUNT: cantidad de transacciones abiertas en la sesion.
-- >   Si es 0, el procedimiento abre y cierra la suya (@tran_propia = 1).
-- >   Si ya hay una abierta (otro procedimiento lo llamo dentro de su
-- >   transaccion), trabaja dentro de esa y deja que quien lo llamo decida el
-- >   COMMIT o el ROLLBACK.
-- > GETDATE() se guarda una sola vez en @ahora: todos los precios se calculan con
-- >   el mismo instante.
    DECLARE @tran_propia BIT = CASE WHEN @@TRANCOUNT = 0 THEN 1 ELSE 0 END;
    DECLARE @ahora DATETIME = GETDATE();

-- > BEGIN TRY ... END TRY / BEGIN CATCH ... END CATCH: si una sentencia del TRY
-- >   falla (o se lanza un THROW), la ejecucion salta al CATCH.
-- > THROW numero, 'mensaje', estado: lanza un error propio. Los numeros de usuario
-- >   tienen que ser 50000 o mayores; por eso los codigos van de 50001 a 50007.
    BEGIN TRY
        IF @tran_propia = 1 BEGIN TRANSACTION;

        -- 1. Validaciones
        IF NOT EXISTS (SELECT 1 FROM dbo.cliente WHERE cod_cliente = @cod_cliente AND activo = 1)
            THROW 50001, 'Cliente inexistente o inactivo.', 1;

        -- Si no se indica una direccion, se usa la principal (RN.04)
-- > SELECT @variable = columna ... WHERE ...: asigna a la variable el valor de la
-- >   fila encontrada. Si no hay fila, la variable conserva su valor (NULL), y la
-- >   validacion siguiente lanza el 50007.
        IF @cod_direccion IS NULL
            SELECT @cod_direccion = cod_direccion
            FROM dbo.direccion
            WHERE cod_cliente = @cod_cliente AND principal = 1;

        IF NOT EXISTS (SELECT 1 FROM dbo.direccion
                       WHERE cod_direccion = @cod_direccion AND cod_cliente = @cod_cliente)
            THROW 50007, 'La direccion no existe o no es del cliente.', 1;

        IF NOT EXISTS (SELECT 1 FROM dbo.metodo_pago WHERE cod_metodo_pago = @cod_metodo_pago)
            THROW 50002, 'Metodo de pago inexistente.', 1;

        IF @ref_transaccion IS NULL
            THROW 50006, 'Falta la referencia de la transaccion de pago.', 1;

        IF NOT EXISTS (SELECT 1 FROM @items)
            THROW 50003, 'La venta no tiene productos.', 1;

-- > Producto inexistente: LEFT JOIN de la lista contra producto. Si el producto
-- >   no existe, las columnas de p quedan NULL (p.cod_producto IS NULL).
        IF EXISTS (SELECT 1
                   FROM @items i
                   LEFT JOIN dbo.producto p ON p.cod_producto = i.cod_producto
                   WHERE p.cod_producto IS NULL OR p.activo = 0)
            THROW 50004, 'Producto inexistente o inactivo.', 1;

        -- 2. Stock: nadie mas modifica esas filas hasta terminar
-- > WITH (UPDLOCK, HOLDLOCK): "pistas de bloqueo" sobre las filas leidas.
-- >   UPDLOCK: toma un bloqueo de actualizacion, asi otra transaccion no puede
-- >     tomar el mismo bloqueo para modificar esas filas.
-- >   HOLDLOCK: mantiene el bloqueo hasta el final de la transaccion, no solo
-- >     durante la lectura.
-- >   Resultado: si dos clientes compran la ultima unidad al mismo tiempo, el
-- >   segundo espera a que termine el primero, y despues ve el stock ya
-- >   descontado. Sin esto, los dos podrian pasar el control y el stock quedaria
-- >   negativo (en este caso lo frenaria el CHECK stock >= 0, pero con un error).
-- >   Es el aislamiento de ACID. No se probo con dos sesiones simultaneas.
        IF EXISTS (SELECT 1
                   FROM @items i
                   INNER JOIN dbo.producto p WITH (UPDLOCK, HOLDLOCK)
                           ON p.cod_producto = i.cod_producto
                   WHERE p.stock < i.cantidad)
            THROW 50005, 'Stock insuficiente para al menos un producto de la venta.', 1;

        -- 3. Encabezado del pedido
-- > INSERT ... SELECT: inserta el resultado de una consulta (no VALUES). La
-- >   direccion se COPIA como texto en el pedido (RN.04 y RN.29): calle, numero,
-- >   ciudad (nombre de la localidad) y provincia. fecha_pedido no se indica:
-- >   toma el DEFAULT GETDATE() (RN.16).
        INSERT INTO dbo.pedido
            (estado, estado_pago, ref_transaccion,
             calle, numero, ciudad, provincia, cod_postal,
             cod_cliente, cod_metodo_pago)
        SELECT 'confirmado', 'aprobado', @ref_transaccion,
               dir.calle, dir.numero, loc.nombre, prov.nombre, dir.cod_postal,
               c.cod_cliente, @cod_metodo_pago
        FROM dbo.cliente c
        INNER JOIN dbo.direccion dir ON dir.cod_cliente = c.cod_cliente AND dir.cod_direccion = @cod_direccion
        INNER JOIN dbo.localidad loc ON loc.cod_localidad = dir.cod_localidad
        INNER JOIN dbo.provincia prov ON prov.cod_provincia = loc.cod_provincia
        WHERE c.cod_cliente = @cod_cliente;

-- > SCOPE_IDENTITY(): el ultimo valor IDENTITY generado en ESTE alcance, o sea,
-- >   el codigo del pedido recien insertado.
-- >   Por que no @@IDENTITY: @@IDENTITY devuelve el ultimo de la sesion, incluido
-- >   el que genere un trigger. El trigger de auditoria de pedido inserta una fila
-- >   en auditoria, asi que @@IDENTITY devolveria el codigo de la AUDITORIA y no
-- >   el del pedido.
        SET @cod_pedido = SCOPE_IDENTITY();

        -- 4. Detalle con precio, alicuota e IVA congelados
        INSERT INTO dbo.detalle_pedido
            (cod_pedido, cod_producto, item, cantidad,
             precio_unitario_venta, alicuota_iva, iva_monto)
-- > Detalle de la venta, un renglon por producto de @items:
-- >   ROW_NUMBER() OVER (ORDER BY i.cod_producto): numera los renglones 1, 2, 3...
-- >     Es una funcion de ventana.
-- >   pf.precio: el precio final de hoy (con IVA y descuento), que queda CONGELADO
-- >     (RN.03): si manana cambia el precio de lista, este renglon no cambia.
-- >   a.porcentaje: la alicuota, tambien copiada (RN.28).
-- >   iva_monto = total - total / (1 + alicuota / 100): el IVA CONTENIDO en un
-- >     precio que ya lo incluye. Ejemplo: 850000 - 850000 / 1,105 = 80769.23.
        SELECT @cod_pedido,
               i.cod_producto,
               ROW_NUMBER() OVER (ORDER BY i.cod_producto),
               i.cantidad,
               pf.precio,
               a.porcentaje,
               ROUND(i.cantidad * pf.precio
                     - (i.cantidad * pf.precio) / (1 + a.porcentaje / 100), 2)
        FROM @items i
        INNER JOIN dbo.producto    p ON p.cod_producto = i.cod_producto
        INNER JOIN dbo.alicuota_iva a ON a.cod_alicuota = p.cod_alicuota
-- > CROSS APPLY (SELECT funcion(...) AS precio) pf: ejecuta la funcion una vez por
-- >   fila y le pone nombre al resultado (pf.precio), para usarlo en dos columnas
-- >   sin llamar dos veces a la funcion.
        CROSS APPLY (SELECT dbo.fn_precio_final(p.cod_producto, @ahora) AS precio) pf;

        -- 5. Salida de stock
-- > UPDATE con FROM y JOIN: baja el stock de todos los productos de la venta en
-- >   una sola sentencia (por conjuntos, no con un bucle).
        UPDATE p
        SET p.stock = p.stock - i.cantidad
        FROM dbo.producto p
        INNER JOIN @items i ON i.cod_producto = p.cod_producto;

        IF @tran_propia = 1 COMMIT TRANSACTION;
    END TRY
-- > CATCH: si la transaccion es propia y sigue abierta, la revierte.
-- > THROW; (sin argumentos): vuelve a lanzar el MISMO error al que llamo, con su
-- >   numero y mensaje originales. Asi el error no se "traga" en silencio.
    BEGIN CATCH
        IF @tran_propia = 1 AND @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

-- #############################################################
-- PARTE 2: DEMOSTRACION (ejecutar cada bloque por separado)
-- #############################################################
-- =============================================================
-- ETAPA V - Tema 1: DEMOSTRACION de funciones y procedimiento
-- =============================================================

USE smarthome_store;
GO

-- =============================================================
-- A. FUNCIONES
-- =============================================================

-- A1. Descuento y precio final de todos los productos al 20/09/2026
--     (ese dia estaba vigente la promo 4 "Liquidacion Accesorios", 35 %,
--      y la promo 3, que solo ofrece cuotas y no cuenta como descuento).
-- Esperado: producto 4 (Funda Notebook) -> descuento 35.00 y precio_final 5200.00.
--           Resto -> descuento 0.00 y precio_final = precio_lista + IVA
--           (por ejemplo producto 1 -> 350000.00; producto 5 -> 850000.00 con IVA 10,5 %).
-- > Como se usa una funcion escalar: dbo.fn_x(...) en el SELECT, una vez por fila.
-- >   Si se le pasa una columna (cod_producto), se calcula para cada producto.
SELECT
    cod_producto,
    nombre,
    precio_lista,
    dbo.fn_descuento_vigente(cod_producto, '2026-09-20') AS descuento_pct,
    dbo.fn_precio_final(cod_producto, '2026-09-20')      AS precio_final
FROM producto
ORDER BY cod_producto;
GO

-- A2. Total de pedidos ya cargados
-- Esperado: pedido 1 -> 245000.00 ; pedido 2 -> 89250.00 ; pedido 9 -> 405000.01
SELECT cod_pedido, dbo.fn_total_pedido(cod_pedido) AS total
FROM pedido
WHERE cod_pedido IN (1, 2, 9);
GO

-- A3. Control: la funcion reproduce el precio congelado en los pedidos existentes.
--     Lista solo los renglones donde el precio guardado NO coincide con la funcion.
-- Esperado: 0 filas.
-- > A3 es un CONTROL: si la funcion calcula igual que como se cargaron los datos,
-- >   no deberia haber diferencias. "<>" significa distinto.
SELECT
    dp.cod_pedido,
    dp.cod_producto,
    dp.precio_unitario_venta                              AS precio_guardado,
    dbo.fn_precio_final(dp.cod_producto, p.fecha_pedido)  AS precio_funcion
FROM detalle_pedido dp
INNER JOIN pedido p ON p.cod_pedido = dp.cod_pedido
WHERE dp.precio_unitario_venta <> dbo.fn_precio_final(dp.cod_producto, p.fecha_pedido);
GO

-- =============================================================
-- B. PROCEDIMIENTO sp_registrar_venta_completa
-- =============================================================

-- B1. Venta correcta (2 auriculares + 1 funda).
--     Va dentro de una transaccion que se deshace al final (ROLLBACK),
--     para no ensuciar los datos de prueba de las etapas anteriores.
-- Esperado (si se ejecuta desde el 28/10/2026 en adelante, sin promo vigente
--           sobre los productos 2 y 4):
--   - stock ANTES:   producto 2 = 40, producto 4 = 30
--   - se crea un pedido nuevo (confirmado / aprobado) con 2 renglones
--   - precios: producto 2 = 25000.00 ; producto 4 = 8000.00
--   - total = 58000.00
--   - stock DESPUES: producto 2 = 38, producto 4 = 29
--   - stock tras el ROLLBACK: vuelve a 40 y 30
-- > Como se llama al procedimiento:
-- >   DECLARE @items dbo.tipo_items_pedido: una variable del tipo tabla.
-- >   INSERT INTO @items ... VALUES (2, 2), (4, 1): se carga como una tabla comun.
-- >   EXEC ... @cod_pedido = @nuevo OUTPUT: hay que repetir OUTPUT al llamar para
-- >     recibir el valor.
-- >   Todo va entre BEGIN TRANSACTION y ROLLBACK: el procedimiento ve que hay una
-- >   transaccion abierta (@@TRANCOUNT = 1) y no abre otra; el ROLLBACK de afuera
-- >   deshace la venta de prueba.
BEGIN TRANSACTION;

DECLARE @items dbo.tipo_items_pedido;
DECLARE @nuevo INT;

INSERT INTO @items (cod_producto, cantidad) VALUES (2, 2), (4, 1);

SELECT 'ANTES' AS momento, cod_producto, nombre, stock
FROM producto WHERE cod_producto IN (2, 4);

EXEC dbo.sp_registrar_venta_completa
     @cod_cliente     = 1,
     @cod_metodo_pago = 1,
     @ref_transaccion = 'DEMO-0001',
     @items           = @items,
     @cod_pedido      = @nuevo OUTPUT;

SELECT cod_pedido, fecha_pedido, estado, estado_pago, ref_transaccion, cod_cliente, calle, numero, ciudad
FROM pedido WHERE cod_pedido = @nuevo;

SELECT cod_pedido, item, cod_producto, cantidad, precio_unitario_venta, alicuota_iva, iva_monto
FROM detalle_pedido WHERE cod_pedido = @nuevo;

SELECT dbo.fn_total_pedido(@nuevo) AS total_pedido;

SELECT 'DESPUES' AS momento, cod_producto, nombre, stock
FROM producto WHERE cod_producto IN (2, 4);

ROLLBACK TRANSACTION;

SELECT 'TRAS ROLLBACK' AS momento, cod_producto, nombre, stock
FROM producto WHERE cod_producto IN (2, 4);
GO

-- B2. Venta con stock insuficiente (6 lavarropas, hay 5).
-- Esperado: error 50005 "Stock insuficiente..."; la cantidad de pedidos no cambia y el stock del producto 8 sigue en 5 (no queda ningun registro parcial).
DECLARE @items dbo.tipo_items_pedido;
DECLARE @nuevo INT;
DECLARE @pedidos_antes INT = (SELECT COUNT(*) FROM pedido);

INSERT INTO @items (cod_producto, cantidad) VALUES (8, 6);

BEGIN TRY
    EXEC dbo.sp_registrar_venta_completa
         @cod_cliente     = 1,
         @cod_metodo_pago = 1,
         @ref_transaccion = 'DEMO-0002',
         @items           = @items,
         @cod_pedido      = @nuevo OUTPUT;
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS error, ERROR_MESSAGE() AS mensaje;
END CATCH;

SELECT @pedidos_antes AS pedidos_antes, COUNT(*) AS pedidos_despues FROM pedido;
SELECT cod_producto, nombre, stock FROM producto WHERE cod_producto = 8;
GO

-- B3. Cliente inexistente.
-- Esperado: error 50001 "Cliente inexistente o inactivo."
DECLARE @items dbo.tipo_items_pedido;
DECLARE @nuevo INT;

INSERT INTO @items (cod_producto, cantidad) VALUES (2, 1);

BEGIN TRY
    EXEC dbo.sp_registrar_venta_completa
         @cod_cliente     = 999,
         @cod_metodo_pago = 1,
         @ref_transaccion = 'DEMO-0003',
         @items           = @items,
         @cod_pedido      = @nuevo OUTPUT;
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS error, ERROR_MESSAGE() AS mensaje;
END CATCH;
GO
-- #############################################################
-- PARTE 3: COMPLEMENTO - FUNCIONES Y PROCEDIMIENTOS ADICIONALES
-- (se agregan a los de las partes 1 y 2; no los reemplazan)
-- #############################################################
-- Objetos:
--   fn_stock_disponible       stock de un producto activo (RN.09, RN.11)
--   fn_pedidos_cliente        pedidos de un cliente con su monto, funcion de
--                             tabla en linea (RN.10)
--   usp_producto_insertar     alta de producto con validaciones (RN.06, RN.28)
--   usp_producto_modificar    modificacion de producto (RN.03, RN.19, RN.14)
--   usp_producto_eliminar     baja fisica o logica segun el producto tenga
--                             historial
--
-- Codigos de error propios: 50101-50104 (insertar), 50111-50114 (modificar)
-- y 50121 (eliminar). No se superponen con los 50001-50006 de
-- sp_registrar_venta_completa.
-- Orden de ejecucion: partes 1 y 2, y luego 3, 4 y 5.

USE smarthome_store;
GO

-- Unidades disponibles; 0 si el producto no existe o esta inactivo
-- > fn_stock_disponible(producto) -> INT: el stock, solo si el producto esta
-- >   activo. ISNULL(..., 0): inexistente o inactivo da 0 (no se puede vender).
CREATE OR ALTER FUNCTION dbo.fn_stock_disponible (@cod_producto INT)
RETURNS INT
AS
BEGIN
    RETURN ISNULL((SELECT stock
                   FROM dbo.producto
                   WHERE cod_producto = @cod_producto AND activo = 1), 0);
END;
GO

-- Pedidos de un cliente con su monto (funcion de tabla en linea)
-- > fn_pedidos_cliente(cliente) -> TABLE: funcion de TABLA EN LINEA.
-- >   RETURNS TABLE + RETURN (un solo SELECT): devuelve un conjunto de filas y se
-- >   usa en el FROM como si fuera una tabla: SELECT * FROM dbo.fn_pedidos_cliente(2).
-- >   Es como una vista con parametro. El optimizador la "expande" dentro de la
-- >   consulta que la usa, por eso suele rendir mejor que una funcion escalar.
-- >   LEFT JOIN con el detalle + ISNULL(SUM(...), 0): un pedido sin renglones
-- >   aparece igual, con monto 0.
CREATE OR ALTER FUNCTION dbo.fn_pedidos_cliente (@cod_cliente INT)
RETURNS TABLE
AS
RETURN
(
    SELECT p.cod_pedido,
           p.fecha_pedido,
           p.estado,
           p.estado_pago,
           ISNULL(SUM(d.cantidad * d.precio_unitario_venta), 0) AS monto
    FROM dbo.pedido p
    LEFT JOIN dbo.detalle_pedido d ON d.cod_pedido = p.cod_pedido
    WHERE p.cod_cliente = @cod_cliente
    GROUP BY p.cod_pedido, p.fecha_pedido, p.estado, p.estado_pago
);--Con LEFT JOIN, un pedido inconsistente aparece con monto 0.
GO

-- Procedimientos almacenados: INSERTAR producto

-- Reglas de negocio vinculadas
--   RN.06  Cada producto pertenece a una unica categoria ya definida.
--   RN.28  Cada producto tiene asignada una alicuota del catalogo.

-- La descripcion es obligatoria (producto.descripcion es NOT NULL).
-- El procedimiento valida los datos ANTES de insertar y devuelve el
-- codigo generado en un parametro de salida. Los errores se informan con
-- THROW (numeros 50101-50104). Las restricciones CHECK de la tabla
-- (precio > 0, stock >= 0) siguen actuando como ultima barrera.


-- > usp_producto_insertar: alta de un producto con validaciones previas.
-- >   Valida primero y lanza un error claro (50101 a 50104) antes de que lo
-- >   rechace la base con un mensaje generico de FK o CHECK.
-- >   LTRIM(RTRIM(x)): quita los espacios de la izquierda y de la derecha, asi
-- >   "   " cuenta como vacio.
-- >   activo no se indica: toma el DEFAULT 1.
-- >   @cod_producto OUTPUT + SCOPE_IDENTITY(): devuelve el codigo generado.
-- >   El precio negativo no lo valida el procedimiento: lo frena el CHECK de la
-- >   tabla (CK_producto_precio_lista), que es la ultima barrera (prueba D6).
CREATE OR ALTER PROCEDURE dbo.usp_producto_insertar
    @nombre        VARCHAR(50),
    @descripcion   VARCHAR(1000),
    @precio_lista  DECIMAL(10, 2),
    @cod_alicuota  INT,
    @stock         INT,
    @cod_categoria INT,
    @cod_producto  INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        IF @nombre IS NULL OR LTRIM(RTRIM(@nombre)) = ''
            THROW 50101, 'El nombre del producto es obligatorio.', 1;

        IF NOT EXISTS (SELECT 1 FROM dbo.categoria
                       WHERE cod_categoria = @cod_categoria AND activo = 1)
            THROW 50102, 'La categoria indicada no existe o esta inactiva.', 1;

        IF NOT EXISTS (SELECT 1 FROM dbo.alicuota_iva WHERE cod_alicuota = @cod_alicuota)
            THROW 50103, 'La alicuota de IVA indicada no existe.', 1;

        IF @descripcion IS NULL OR LTRIM(RTRIM(@descripcion)) = ''
            THROW 50104, 'La descripcion del producto es obligatoria.', 1;

        INSERT INTO dbo.producto (nombre, descripcion, precio_lista, cod_alicuota, stock, cod_categoria)
        VALUES (LTRIM(RTRIM(@nombre)), LTRIM(RTRIM(@descripcion)), @precio_lista, @cod_alicuota, @stock, @cod_categoria);

        SET @cod_producto = SCOPE_IDENTITY();
    END TRY
    BEGIN CATCH
        THROW;   -- se vuelve a lanzar el error original al llamador
    END CATCH;
END;
GO

-- Procedimientos almacenados: MODIFICAR producto

-- Reglas de negocio vinculadas

--   RN.03/RN.19  El cambio de precio de lista NO altera los pedidos ya
--                registrados (el precio queda congelado en detalle_pedido).
--   RN.14        Los cambios de precio y stock quedan auditados (trigger de
--                la carpeta docs/etapa-05/triggers_auditoria).


-- > usp_producto_modificar: reemplaza todos los datos del producto.
-- >   Cambiar el precio de lista NO cambia las ventas ya hechas, porque el precio
-- >   quedo copiado en detalle_pedido (RN.03).
-- >   El cambio de precio o de stock lo registra el trigger de auditoria (RN.14),
-- >   sin que el procedimiento haga nada.
-- >   @activo BIT = 1: parametro opcional; si no se pasa, el producto queda activo.
CREATE OR ALTER PROCEDURE dbo.usp_producto_modificar
    @cod_producto  INT,
    @nombre        VARCHAR(50),
    @descripcion   VARCHAR(1000),
    @precio_lista  DECIMAL(10, 2),
    @cod_alicuota  INT,
    @stock         INT,
    @cod_categoria INT,
    @activo        BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM dbo.producto WHERE cod_producto = @cod_producto)
            THROW 50111, 'El producto indicado no existe.', 1;

        IF NOT EXISTS (SELECT 1 FROM dbo.categoria WHERE cod_categoria = @cod_categoria)
            THROW 50112, 'La categoria indicada no existe.', 1;

        IF NOT EXISTS (SELECT 1 FROM dbo.alicuota_iva WHERE cod_alicuota = @cod_alicuota)
            THROW 50113, 'La alicuota de IVA indicada no existe.', 1;

        IF @descripcion IS NULL OR LTRIM(RTRIM(@descripcion)) = ''
            THROW 50114, 'La descripcion del producto es obligatoria.', 1;

        UPDATE dbo.producto
        SET nombre        = LTRIM(RTRIM(@nombre)),
            descripcion   = LTRIM(RTRIM(@descripcion)),
            precio_lista  = @precio_lista,
            cod_alicuota  = @cod_alicuota,
            stock         = @stock,
            cod_categoria = @cod_categoria,
            activo        = @activo
        WHERE cod_producto = @cod_producto;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH;
END;
GO

-- Procedimientos almacenados: ELIMINAR producto

-- Decision de diseno: un producto con historial (vendido o comprado) NO
-- puede borrarse fisicamente sin perder trazabilidad, y la base ya lo
-- impide con claves foraneas. El procedimiento decide solo:
--   * sin historial  -> DELETE fisico            (@resultado = 'ELIMINADO')
--   * con historial  -> baja logica (activo = 0) (@resultado = 'BAJA_LOGICA')



-- > usp_producto_eliminar: decide entre borrar o dar de baja.
-- >   Sin historial (nunca vendido ni comprado): DELETE fisico -> 'ELIMINADO'.
-- >   Con historial: UPDATE activo = 0 (baja LOGICA) -> 'BAJA_LOGICA'. El producto
-- >     sigue existiendo para que las ventas y compras viejas no pierdan su dato;
-- >     ademas, la FK de detalle_pedido impediria el DELETE.
-- >   @resultado VARCHAR(12) OUTPUT: le dice a quien llamo que se hizo.
CREATE OR ALTER PROCEDURE dbo.usp_producto_eliminar
    @cod_producto INT,
    @resultado    VARCHAR(12) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM dbo.producto WHERE cod_producto = @cod_producto)
            THROW 50121, 'El producto indicado no existe.', 1;

        IF NOT EXISTS (SELECT 1 FROM dbo.detalle_pedido WHERE cod_producto = @cod_producto)
           AND NOT EXISTS (SELECT 1 FROM dbo.detalle_compra WHERE cod_producto = @cod_producto)
        BEGIN
            DELETE FROM dbo.producto WHERE cod_producto = @cod_producto;
            SET @resultado = 'ELIMINADO';
        END
        ELSE
        BEGIN
            UPDATE dbo.producto SET activo = 0 WHERE cod_producto = @cod_producto;
            SET @resultado = 'BAJA_LOGICA';
        END;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH;
END;
GO


-- #############################################################
-- PARTE 4: COMPLEMENTO - DEMOSTRACION (ejecutar cada bloque por separado)
-- C = funciones complementarias | D = procedimientos del catalogo
-- #############################################################
-- Los bloques D1 a D6 se ejecutan en orden. D1 y D2 crean los productos de
-- los lotes "LOTE-A" y "LOTE-P": ejecutarlos una sola vez.
-- Si la parte 2 se ejecuta despues, la lista de productos de A1 incluye
-- tambien los productos LOTE-*; el resultado esperado de A1 no cambia.

-- =============================================================
-- C. FUNCIONES COMPLEMENTARIAS
-- =============================================================

USE smarthome_store;
GO

-- C1. Stock disponible de todo el catalogo
-- Esperado: coincide con la columna stock de cada producto activo
--           (con la carga inicial: producto 1 -> 12, producto 2 -> 40,
--           producto 3 -> 6). Un producto inactivo o inexistente da 0.
SELECT p.cod_producto,
       p.nombre,
       p.stock,
       p.activo,
       dbo.fn_stock_disponible(p.cod_producto) AS stock_disponible
FROM dbo.producto p
ORDER BY p.cod_producto;
GO

-- C2. Pedidos de un cliente (funcion de tabla en linea)
-- Esperado (cliente 2): pedido 2 -> 89250.00 y pedido 12 -> 30200.00
SELECT * FROM dbo.fn_pedidos_cliente(2) ORDER BY cod_pedido;
GO

-- C3. La funcion de tabla se usa como una tabla mas con CROSS APPLY:
--     pedidos confirmados y con pago aprobado de todos los clientes.
-- Esperado: un renglon por pedido confirmado/aprobado; los pedidos 10
--           (pendiente) y 11 (cancelado) no aparecen.
-- > CROSS APPLY con una funcion de tabla: para CADA cliente ejecuta la funcion
-- >   con su codigo y une las filas que devuelve. Un JOIN comun no puede pasarle
-- >   una columna de la otra tabla como parametro; APPLY si.
-- >   CROSS APPLY descarta a los clientes sin filas; OUTER APPLY los mantendria
-- >   con NULL (como un LEFT JOIN).
SELECT c.cod_cliente, c.nombre + ' ' + c.apellido AS cliente, t.cod_pedido, t.monto
FROM dbo.cliente c
CROSS APPLY dbo.fn_pedidos_cliente(c.cod_cliente) AS t
WHERE t.estado = 'confirmado' AND t.estado_pago = 'aprobado'
ORDER BY c.cod_cliente, t.cod_pedido;
GO

-- C4. Casos limite: producto, pedido o cliente inexistente
-- Esperado: precio NULL ; stock 0 ; total 0.00 ; 0 pedidos
SELECT dbo.fn_precio_final(999999, GETDATE())                AS precio_producto_inexistente,
       dbo.fn_stock_disponible(999999)                        AS stock_producto_inexistente,
       dbo.fn_total_pedido(999999)                            AS total_pedido_inexistente,
       (SELECT COUNT(*) FROM dbo.fn_pedidos_cliente(999999))  AS pedidos_cliente_inexistente;
GO

-- =============================================================
-- D. PROCEDIMIENTOS DEL CATALOGO
-- =============================================================

-- D1. Lote de 5 productos con INSERT directo (prefijo "LOTE-A").
-- Esperado: 5 filas nuevas.
USE smarthome_store;
GO
SET NOCOUNT ON;

DECLARE @alic_general    INT = (SELECT cod_alicuota FROM dbo.alicuota_iva WHERE porcentaje = 21.00);
DECLARE @alic_reducida   INT = (SELECT cod_alicuota FROM dbo.alicuota_iva WHERE porcentaje = 10.50);
DECLARE @cat_accesorios  INT = (SELECT cod_categoria FROM dbo.categoria WHERE nombre = N'Accesorios');
DECLARE @cat_audio       INT = (SELECT cod_categoria FROM dbo.categoria WHERE nombre = N'Audio');
DECLARE @cat_informatica INT = (SELECT cod_categoria FROM dbo.categoria WHERE nombre LIKE N'Inform_tica');
DECLARE @cat_notebooks   INT = (SELECT cod_categoria FROM dbo.categoria WHERE nombre = N'Notebooks');

-- columnas: nombre, descripcion, precio_lista (neto), cod_alicuota, stock, cod_categoria
INSERT INTO dbo.producto (nombre, descripcion, precio_lista, cod_alicuota, stock, cod_categoria)
VALUES
    ('LOTE-A Teclado mecanico',  'Teclado mecanico retroiluminado',   33057.85, @alic_general,  25, @cat_informatica),
    ('LOTE-A Mouse inalambrico', 'Mouse optico inalambrico 1600 dpi',  8264.46, @alic_general,  40, @cat_accesorios),
    ('LOTE-A Auriculares gamer', 'Auriculares con microfono USB',     24793.39, @alic_general,  18, @cat_audio),
    ('LOTE-A Notebook gamer',    'Notebook 16GB RAM, SSD 512GB',     950000.00, @alic_reducida,  6, @cat_notebooks),
    ('LOTE-A Soporte monitor',   'Soporte articulado para monitor',   12396.69, @alic_general,  30, @cat_accesorios);

SELECT cod_producto, nombre, precio_lista, stock
FROM dbo.producto
WHERE nombre LIKE 'LOTE-A %'
ORDER BY cod_producto;
GO

-- D2. Los MISMOS 5 productos del lote A cargados con usp_producto_insertar
--     (prefijo "LOTE-P"; mismos precios, stock, alicuotas y categorias).
-- Esperado: 5 filas nuevas (el script imprime "Producto creado: <codigo>"
--           por cada alta).
USE smarthome_store;
GO
SET NOCOUNT ON;

DECLARE @alic_general    INT = (SELECT cod_alicuota FROM dbo.alicuota_iva WHERE porcentaje = 21.00);
DECLARE @alic_reducida   INT = (SELECT cod_alicuota FROM dbo.alicuota_iva WHERE porcentaje = 10.50);
DECLARE @cat_accesorios  INT = (SELECT cod_categoria FROM dbo.categoria WHERE nombre = N'Accesorios');
DECLARE @cat_audio       INT = (SELECT cod_categoria FROM dbo.categoria WHERE nombre = N'Audio');
DECLARE @cat_informatica INT = (SELECT cod_categoria FROM dbo.categoria WHERE nombre LIKE N'Inform_tica');
DECLARE @cat_notebooks   INT = (SELECT cod_categoria FROM dbo.categoria WHERE nombre = N'Notebooks');
DECLARE @id INT;

EXEC dbo.usp_producto_insertar
     @nombre = 'LOTE-P Teclado mecanico', @descripcion = 'Teclado mecanico retroiluminado',
     @precio_lista = 33057.85, @cod_alicuota = @alic_general, @stock = 25,
     @cod_categoria = @cat_informatica, @cod_producto = @id OUTPUT;
PRINT 'Producto creado: ' + CAST(@id AS VARCHAR(10));

EXEC dbo.usp_producto_insertar
     @nombre = 'LOTE-P Mouse inalambrico', @descripcion = 'Mouse optico inalambrico 1600 dpi',
     @precio_lista = 8264.46, @cod_alicuota = @alic_general, @stock = 40,
     @cod_categoria = @cat_accesorios, @cod_producto = @id OUTPUT;
PRINT 'Producto creado: ' + CAST(@id AS VARCHAR(10));

EXEC dbo.usp_producto_insertar
     @nombre = 'LOTE-P Auriculares gamer', @descripcion = 'Auriculares con microfono USB',
     @precio_lista = 24793.39, @cod_alicuota = @alic_general, @stock = 18,
     @cod_categoria = @cat_audio, @cod_producto = @id OUTPUT;
PRINT 'Producto creado: ' + CAST(@id AS VARCHAR(10));

EXEC dbo.usp_producto_insertar
     @nombre = 'LOTE-P Notebook gamer', @descripcion = 'Notebook 16GB RAM, SSD 512GB',
     @precio_lista = 950000.00, @cod_alicuota = @alic_reducida, @stock = 6,
     @cod_categoria = @cat_notebooks, @cod_producto = @id OUTPUT;
PRINT 'Producto creado: ' + CAST(@id AS VARCHAR(10));

EXEC dbo.usp_producto_insertar
     @nombre = 'LOTE-P Soporte monitor', @descripcion = 'Soporte articulado para monitor',
     @precio_lista = 12396.69, @cod_alicuota = @alic_general, @stock = 30,
     @cod_categoria = @cat_accesorios, @cod_producto = @id OUTPUT;
PRINT 'Producto creado: ' + CAST(@id AS VARCHAR(10));

SELECT cod_producto, nombre, precio_lista, stock
FROM dbo.producto
WHERE nombre LIKE 'LOTE-P %'
ORDER BY cod_producto;
GO

-- ---------------------------------------------------------------------
-- Verificacion opcional de equivalencia (requiere haber ejecutado antes
-- el bloque D1). Compara cada producto LOTE-A con su par
-- LOTE-P; 'iguales' = 1 si precio, stock, alicuota y categoria coinciden.
-- ---------------------------------------------------------------------
SELECT a.nombre AS lote_a,
       p.nombre AS lote_p,
       a.precio_lista, a.stock, a.cod_alicuota, a.cod_categoria,
       CASE WHEN a.precio_lista = p.precio_lista
             AND a.stock        = p.stock
             AND a.cod_alicuota = p.cod_alicuota
             AND a.cod_categoria = p.cod_categoria
            THEN 1 ELSE 0 END AS iguales
FROM dbo.producto a
INNER JOIN dbo.producto p
        ON SUBSTRING(a.nombre, 8, 100) = SUBSTRING(p.nombre, 8, 100)
WHERE a.nombre LIKE 'LOTE-A %'
  AND p.nombre LIKE 'LOTE-P %'
ORDER BY a.cod_producto;
GO

-- D3 a D6. UPDATE y DELETE invocando a los procedimientos. Operan sobre los
-- productos del lote "LOTE-P". Incluyen casos de error y un caso de baja
-- logica (dentro de una transaccion que se revierte para no alterar los
-- datos originales).
-- Esperado: D3 precio +10 % y stock -3 | D4 resultado ELIMINADO |
--           D5 BAJA_LOGICA y, tras el ROLLBACK, activo = 1 |
--           D6 errores 50121, 50102 y 547 (CHECK del precio).
USE smarthome_store;
GO
SET NOCOUNT ON;

-- D3) MODIFICAR: subir 10 % el precio de lista y bajar el stock de un producto
-- ---------------------------------------------------------------------
DECLARE @id_mod INT = (SELECT TOP (1) cod_producto FROM dbo.producto
                       WHERE nombre LIKE 'LOTE-P %' ORDER BY cod_producto);
DECLARE @nombre VARCHAR(50), @descripcion VARCHAR(1000), @precio DECIMAL(10, 2),
        @alic INT, @stock INT, @cat INT, @activo BIT, @precio_nuevo DECIMAL(10, 2);

SELECT @nombre = nombre, @descripcion = descripcion, @precio = precio_lista,
       @alic = cod_alicuota, @stock = stock, @cat = cod_categoria, @activo = activo
FROM dbo.producto WHERE cod_producto = @id_mod;

SET @precio_nuevo = ROUND(@precio * 1.10, 2);
SET @stock = @stock - 3;

EXEC dbo.usp_producto_modificar
     @cod_producto = @id_mod, @nombre = @nombre, @descripcion = @descripcion,
     @precio_lista = @precio_nuevo, @cod_alicuota = @alic, @stock = @stock,
     @cod_categoria = @cat, @activo = @activo;

SELECT cod_producto, nombre, precio_lista, stock, 'Despues del UPDATE' AS momento
FROM dbo.producto WHERE cod_producto = @id_mod;


-- D4) ELIMINAR un producto sin historial -> DELETE fisico
-- ---------------------------------------------------------------------
DECLARE @id_del INT = (SELECT TOP (1) cod_producto FROM dbo.producto
                       WHERE nombre LIKE 'LOTE-P %' ORDER BY cod_producto DESC);
DECLARE @res VARCHAR(12);

EXEC dbo.usp_producto_eliminar @cod_producto = @id_del, @resultado = @res OUTPUT;
SELECT @id_del AS cod_producto, @res AS resultado,
       (SELECT COUNT(*) FROM dbo.producto WHERE cod_producto = @id_del) AS filas_restantes;
GO


-- D5) ELIMINAR un producto CON historial -> baja logica
--    (se hace dentro de una transaccion y se revierte, para no dejar
--     inactivo un producto del catalogo original)
-- ---------------------------------------------------------------------
DECLARE @res2 VARCHAR(12);
DECLARE @id_vendido INT = (SELECT TOP (1) cod_producto FROM dbo.detalle_pedido ORDER BY cod_producto);

BEGIN TRANSACTION;
    EXEC dbo.usp_producto_eliminar @cod_producto = @id_vendido, @resultado = @res2 OUTPUT;
    SELECT cod_producto, nombre, activo, @res2 AS resultado
    FROM dbo.producto WHERE cod_producto = @id_vendido;
ROLLBACK TRANSACTION;

SELECT cod_producto, nombre, activo, 'Despues del ROLLBACK' AS momento
FROM dbo.producto WHERE cod_producto = @id_vendido;
GO


-- D6) CASOS DE ERROR (se capturan y se muestran los mensajes)
-- ---------------------------------------------------------------------
DECLARE @id INT;

BEGIN TRY   -- producto inexistente
    DECLARE @r VARCHAR(12);
    EXEC dbo.usp_producto_eliminar @cod_producto = 999999, @resultado = @r OUTPUT;
END TRY
BEGIN CATCH
    SELECT 'Eliminar inexistente' AS caso, ERROR_NUMBER() AS nro_error, ERROR_MESSAGE() AS mensaje;
END CATCH;

BEGIN TRY   -- categoria inexistente
    EXEC dbo.usp_producto_insertar @nombre = 'LOTE-P error', @descripcion = 'Prueba de error', @precio_lista = 100,
         @cod_alicuota = 5, @stock = 1, @cod_categoria = 999999, @cod_producto = @id OUTPUT;
END TRY
BEGIN CATCH
    SELECT 'Insertar con categoria inexistente' AS caso, ERROR_NUMBER() AS nro_error, ERROR_MESSAGE() AS mensaje;
END CATCH;

BEGIN TRY   -- precio negativo: lo frena la restriccion CHECK de la tabla
    EXEC dbo.usp_producto_insertar @nombre = 'LOTE-P error', @descripcion = 'Prueba de error', @precio_lista = -50,
         @cod_alicuota = 5, @stock = 1, @cod_categoria = 1, @cod_producto = @id OUTPUT;
END TRY
BEGIN CATCH
    SELECT 'Insertar con precio negativo' AS caso, ERROR_NUMBER() AS nro_error, ERROR_MESSAGE() AS mensaje;
END CATCH;
GO


-- #############################################################
-- PARTE 5: COMPLEMENTO - COMPARACION DE EFICIENCIA
-- (operaciones directas vs. procedimientos y funciones)
-- #############################################################
-- =====================================================================
-- Etapa V - Comparacion de eficiencia: operaciones directas vs.
-- procedimientos y funciones almacenadas.
--
-- Todo el banco de pruebas corre dentro de una transaccion que se
-- revierte, asi que no deja datos. Los tiempos se guardan en una variable
-- de tabla (el ROLLBACK no la afecta). Requiere haber creado
-- usp_producto_insertar (parte 3) y dbo.fn_total_pedido (parte 1).
--
-- Recomendacion: ejecutar el script DOS veces y registrar la segunda
-- (la primera incluye el costo de compilar los planes).
-- =====================================================================
USE smarthome_store;
GO
SET NOCOUNT ON;

-- > Como se mide:
-- >   SYSDATETIME(): fecha y hora con mas precision que GETDATE().
-- >   DATEDIFF(MILLISECOND, inicio, fin): milisegundos transcurridos.
-- >   DECLARE @res TABLE (...): VARIABLE DE TABLA. Clave: el ROLLBACK no la afecta,
-- >     por eso los tiempos sobreviven aunque se revierta todo lo insertado.
-- >   Todo va en una transaccion que termina en ROLLBACK: no deja productos de prueba.
DECLARE @n INT = 2000, @i INT, @t0 DATETIME2(3), @nom VARCHAR(50), @id INT;
DECLARE @alic INT = (SELECT cod_alicuota FROM dbo.alicuota_iva WHERE porcentaje = 21.00);
DECLARE @cat  INT = (SELECT cod_categoria FROM dbo.categoria WHERE nombre = N'Accesorios');
DECLARE @res  TABLE (prueba VARCHAR(70), repeticiones INT, ms INT);

BEGIN TRANSACTION;

-- A) 2.000 INSERT directos, uno por uno ---------------------------------
-- > A) WHILE: bucle de T-SQL. 2000 INSERT, uno por vuelta. CONCAT une textos y
-- >   numeros sin convertirlos (y trata NULL como texto vacio).
-- >   SET @i += 1: suma 1 a la variable.
SET @i = 1;
SET @t0 = SYSDATETIME();
WHILE @i <= @n
BEGIN
    SET @nom = CONCAT('BENCH-A ', @i);
    INSERT INTO dbo.producto (nombre, descripcion, precio_lista, cod_alicuota, stock, cod_categoria)
    VALUES (@nom, 'Producto de prueba', 100.00, @alic, 1, @cat);
    SET @i += 1;
END;
INSERT INTO @res VALUES ('A) INSERT directo en bucle', @n, DATEDIFF(MILLISECOND, @t0, SYSDATETIME()));

-- B) 2.000 llamadas al procedimiento (con sus validaciones) -------------
-- > B) Lo mismo, pero llamando al procedimiento: suma el costo de la llamada y de
-- >   las validaciones (cuatro consultas por alta).
SET @i = 1;
SET @t0 = SYSDATETIME();
WHILE @i <= @n
BEGIN
    SET @nom = CONCAT('BENCH-B ', @i);
    EXEC dbo.usp_producto_insertar @nombre = @nom, @descripcion = 'Producto de prueba', @precio_lista = 100.00,
         @cod_alicuota = @alic, @stock = 1, @cod_categoria = @cat, @cod_producto = @id OUTPUT;
    SET @i += 1;
END;
INSERT INTO @res VALUES ('B) EXEC usp_producto_insertar en bucle', @n, DATEDIFF(MILLISECOND, @t0, SYSDATETIME()));

-- C) un unico INSERT ... SELECT (operacion por conjuntos) ---------------
-- > C) Un solo INSERT ... SELECT: inserta las 2000 filas en una sola sentencia
-- >   (operacion por CONJUNTOS, como trabaja mejor SQL Server).
-- >   Generador de numeros: ROW_NUMBER() sobre un CROSS JOIN de sys.all_objects
-- >   consigo misma (tiene miles de filas, el producto da millones) y TOP (@n) se
-- >   queda con las primeras 2000. ORDER BY (SELECT NULL) = "sin un orden en
-- >   particular", porque ROW_NUMBER exige un ORDER BY.
SET @t0 = SYSDATETIME();
INSERT INTO dbo.producto (nombre, descripcion, precio_lista, cod_alicuota, stock, cod_categoria)
SELECT CONCAT('BENCH-C ', x.i), 'Producto de prueba', 100.00, @alic, 1, @cat
FROM (SELECT TOP (@n) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS i
      FROM sys.all_objects a CROSS JOIN sys.all_objects b) AS x;
INSERT INTO @res VALUES ('C) INSERT ... SELECT (un solo comando)', @n, DATEDIFF(MILLISECOND, @t0, SYSDATETIME()));

ROLLBACK TRANSACTION;

-- > El ROLLBACK no devuelve los valores IDENTITY ya usados: el proximo producto
-- >   saldria con un codigo salteado.
-- >   DBCC CHECKIDENT (tabla, RESEED, n): reinicia el contador en n, y el proximo
-- >   sera n + 1. Aca se arma como SQL dinamico (EXEC (@sql)); al final del
-- >   script se hace lo mismo pasandole la variable directamente.
-- Los identity avanzaron aunque se hizo ROLLBACK: se restablece el contador
DECLARE @max INT = (SELECT ISNULL(MAX(cod_producto), 0) FROM dbo.producto);
DECLARE @sql NVARCHAR(200) = N'DBCC CHECKIDENT (''dbo.producto'', RESEED, ' + CAST(@max AS NVARCHAR(12)) + N')';
EXEC (@sql);

-- D y E) funcion escalar vs. consulta directa --------------------------------
--    12 pedidos x 20.000 repeticiones = 240.000 calculos del monto
-- > SELECT ... INTO #nums: crea una TABLA TEMPORAL (empieza con #) con 20000
-- >   numeros. Vive en tempdb y solo la ve esta sesion; se borra con DROP TABLE.
SELECT TOP (20000) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS i
INTO #nums
FROM sys.all_objects a CROSS JOIN sys.all_objects b;

DECLARE @acum DECIMAL(18, 2);

SET @t0 = SYSDATETIME();
-- > D) Funcion escalar: SUM(dbo.fn_total_pedido(...)) sobre 12 pedidos x 20000
-- >   = 240000 llamadas.
-- > E) Lo mismo con la subconsulta escrita directamente (CROSS APPLY).
-- > Lo esperable por teoria es que la funcion escalar sea mas lenta, porque se
-- >   ejecuta fila por fila. En la medicion del equipo fue mas rapida. Una
-- >   explicacion posible es que SQL Server 2019 y posteriores pueden "inlinear"
-- >   funciones escalares simples como esta (convertirlas en parte de la consulta),
-- >   pero no se verifico en el plan de ejecucion.
SELECT @acum = SUM(dbo.fn_total_pedido(p.cod_pedido))
FROM dbo.pedido p CROSS JOIN #nums;
INSERT INTO @res VALUES ('D) monto con funcion escalar fn_total_pedido', 240000, DATEDIFF(MILLISECOND, @t0, SYSDATETIME()));

SET @t0 = SYSDATETIME();
SELECT @acum = SUM(t.monto)
FROM dbo.pedido p
CROSS JOIN #nums
CROSS APPLY (SELECT SUM(d.cantidad * d.precio_unitario_venta) AS monto
             FROM dbo.detalle_pedido d
             WHERE d.cod_pedido = p.cod_pedido) AS t;
INSERT INTO @res VALUES ('E) monto con subconsulta directa (CROSS APPLY)', 240000, DATEDIFF(MILLISECOND, @t0, SYSDATETIME()));

DROP TABLE #nums;

SELECT prueba, repeticiones, ms FROM @res;
GO

-- =============================================================
-- Limpieza de los productos de los lotes (D1 y D2)
-- Deja el catalogo como en la carga inicial, para que los demas temas
-- den los resultados documentados.
-- =============================================================
-- > Limpieza: borra los productos de las pruebas D1 y D2 (LIKE 'LOTE-A %':
-- >   empiezan con ese texto; % es "cualquier cosa") y reinicia el IDENTITY.
-- >   WITH NO_INFOMSGS: no muestra los mensajes informativos de DBCC.
-- > Esperado: productos = 10, como en la carga inicial.
DELETE FROM dbo.producto WHERE nombre LIKE 'LOTE-A %' OR nombre LIKE 'LOTE-P %';

DECLARE @max_producto INT = (SELECT ISNULL(MAX(cod_producto), 0) FROM dbo.producto);
DBCC CHECKIDENT ('dbo.producto', RESEED, @max_producto) WITH NO_INFOMSGS;

SELECT COUNT(*) AS productos FROM dbo.producto;
GO
