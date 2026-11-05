-- =============================================================
-- ETAPA V - Tema 3: Triggers y auditoria
-- La parte 1 crea los triggers y la parte 2 los prueba (A0 a A7).
-- Los triggers de auditoria guardan en la tabla auditoria la operacion, el
-- codigo del registro, el valor anterior y el nuevo, y el empleado que
-- informo la aplicacion (SESSION_CONTEXT 'cod_usuario'; si no lo informo,
-- el usuario 1). usuario_bd se completa solo con el login de la sesion.
-- Requiere crear_bd.sql, cargar_datos.sql y el script de procedimientos
-- (docs/etapa-05/procedimientos_funciones/scripts.sql), que usa A3.
-- =============================================================

-- =============================================================
-- GUIA DE ESTUDIO PARA LA DEFENSA (rama estudio-defensa, no se sube)
-- Las lineas "-- >" son notas de estudio.
-- > TRIGGER: codigo que SQL Server ejecuta solo cuando ocurre un INSERT, UPDATE o
-- >   DELETE sobre una tabla. Nadie lo llama: se dispara.
-- > AFTER: se ejecuta despues de la sentencia, dentro de su MISMA transaccion. Si
-- >   el trigger falla, se revierte tambien el cambio (A4). Si la transaccion se
-- >   revierte, tambien se revierte la auditoria (A3).
-- > INSTEAD OF: se ejecuta EN LUGAR de la sentencia; la operacion original no ocurre.
-- > Tablas virtuales, que solo existen dentro del trigger:
-- >   inserted: las filas nuevas (INSERT, y el "despues" de un UPDATE).
-- >   deleted : las filas viejas (DELETE, y el "antes" de un UPDATE).
-- >   INSERT -> solo inserted; DELETE -> solo deleted; UPDATE -> las dos.
-- > Se dispara UNA vez por SENTENCIA, no por fila: un UPDATE de 10 productos
-- >   llega con 10 filas en inserted. Por eso se escribe por conjuntos, con
-- >   INSERT ... SELECT, y no con variables de una fila (A5 lo prueba).
-- > Por que en la base y no en la aplicacion: cualquier cambio queda registrado,
-- >   tambien un UPDATE hecho a mano en SSMS (RN.14).
-- =============================================================
USE smarthome_store;
GO

SET NOCOUNT ON;
GO
-- -------------------------------------------------------------
-- Trigger 1: producto (precio_lista y stock)
-- Guarda: 'precio_lista=...; stock=...' antes y despues del cambio.
-- Un trigger se ejecuta una vez por sentencia: inserted y deleted
-- pueden tener muchas filas. El FULL OUTER JOIN cubre los tres
-- casos (INSERT, UPDATE y DELETE).
-- -------------------------------------------------------------
-- > Trigger 1 linea por linea:
-- >   TRIGGER_NESTLEVEL() > 1 -> RETURN: si este trigger se disparo desde otro
-- >     trigger, no hace nada; evita auditar dos veces o entrar en un ciclo.
-- >   SESSION_CONTEXT(N'cod_usuario'): lee un valor que la aplicacion guardo en la
-- >     sesion con sp_set_session_context. Asi el trigger sabe que EMPLEADO hizo
-- >     el cambio, aunque todos se conecten con el mismo login.
-- >   TRY_CAST(... AS INT): convierte a INT y, si no puede, devuelve NULL en vez de
-- >     dar error.
-- >   ISNULL(..., 1): si la aplicacion no informo el empleado, usa el usuario 1.
-- >   FULL OUTER JOIN inserted con deleted por la clave: une el antes y el despues.
-- >     Solo en deleted  -> DELETE (i.cod_producto IS NULL).
-- >     Solo en inserted -> INSERT (d.cod_producto IS NULL).
-- >     En las dos       -> UPDATE.
-- >   CASE WHEN ... THEN ... ELSE ... END: el "si / entonces" de SQL.
-- >   COALESCE(i.cod, d.cod): el codigo, venga del lado que venga.
-- >   CONCAT('precio_lista=', ...): arma el texto del valor anterior y del nuevo.
-- >   WHERE: en un UPDATE solo registra si cambio el precio o el stock. Un UPDATE
-- >     de la descripcion no genera fila.
-- >   usuario_bd y fecha no se indican: los completan sus DEFAULT
-- >     (SUSER_SNAME() y GETDATE()).
CREATE OR ALTER TRIGGER dbo.trg_producto_auditoria
ON dbo.producto
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    -- Si el trigger se dispara desde otro trigger, no se repite.
    IF TRIGGER_NESTLEVEL() > 1 RETURN;

    DECLARE @cod_usuario INT = ISNULL(TRY_CAST(SESSION_CONTEXT(N'cod_usuario') AS INT), 1);

    INSERT INTO dbo.auditoria
        (entidad, operacion, registro_id, valor_anterior, valor_nuevo, cod_usuario)
    SELECT
        'producto',
        CASE WHEN d.cod_producto IS NULL THEN 'INSERT'
             WHEN i.cod_producto IS NULL THEN 'DELETE'
             ELSE 'UPDATE' END,
        COALESCE(i.cod_producto, d.cod_producto),
        CASE WHEN d.cod_producto IS NULL THEN NULL
             ELSE CONCAT('precio_lista=', d.precio_lista, '; stock=', d.stock) END,
        CASE WHEN i.cod_producto IS NULL THEN NULL
             ELSE CONCAT('precio_lista=', i.precio_lista, '; stock=', i.stock) END,
        @cod_usuario
    FROM inserted i
    FULL OUTER JOIN deleted d ON d.cod_producto = i.cod_producto
    WHERE i.cod_producto IS NULL
       OR d.cod_producto IS NULL
       OR i.precio_lista <> d.precio_lista
       OR i.stock        <> d.stock;
END;
GO

-- -------------------------------------------------------------
-- Trigger 2: pedido (estado, estado_pago y estado_envio)
-- Guarda: 'estado=...; pago=...; envio=...' antes y despues del cambio.
-- Solo audita si alguno de esos campos cambia: un UPDATE de la
-- direccion de envio no genera fila.
-- -------------------------------------------------------------
-- > Trigger 2: misma estructura. En un UPDATE audita si cambio el estado, el pago
-- >   o el envio. ISNULL(estado_envio, '-'): estado_envio puede ser NULL, y
-- >   "NULL <> 'pendiente'" no da verdadero (da UNKNOWN). Reemplazando NULL por
-- >   '-' la comparacion funciona.
CREATE OR ALTER TRIGGER dbo.trg_pedido_auditoria
ON dbo.pedido
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    IF TRIGGER_NESTLEVEL() > 1 RETURN;

    DECLARE @cod_usuario INT = ISNULL(TRY_CAST(SESSION_CONTEXT(N'cod_usuario') AS INT), 1);

    INSERT INTO dbo.auditoria
        (entidad, operacion, registro_id, valor_anterior, valor_nuevo, cod_usuario)
    SELECT
        'pedido',
        CASE WHEN d.cod_pedido IS NULL THEN 'INSERT'
             WHEN i.cod_pedido IS NULL THEN 'DELETE'
             ELSE 'UPDATE' END,
        COALESCE(i.cod_pedido, d.cod_pedido),
        CASE WHEN d.cod_pedido IS NULL THEN NULL
             ELSE CONCAT('estado=', d.estado, '; pago=', d.estado_pago,
                         '; envio=', ISNULL(d.estado_envio, '-')) END,
        CASE WHEN i.cod_pedido IS NULL THEN NULL
             ELSE CONCAT('estado=', i.estado, '; pago=', i.estado_pago,
                         '; envio=', ISNULL(i.estado_envio, '-')) END,
        @cod_usuario
    FROM inserted i
    FULL OUTER JOIN deleted d ON d.cod_pedido = i.cod_pedido
    WHERE i.cod_pedido IS NULL
       OR d.cod_pedido IS NULL
       OR i.estado       <> d.estado
       OR i.estado_pago  <> d.estado_pago
       OR ISNULL(i.estado_envio, '-') <> ISNULL(d.estado_envio, '-');
END;
GO

-- -------------------------------------------------------------
-- Trigger 3: compra (estado)
-- Guarda: 'estado=...' antes y despues del cambio.
-- -------------------------------------------------------------
CREATE OR ALTER TRIGGER dbo.trg_compra_auditoria
ON dbo.compra
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    IF TRIGGER_NESTLEVEL() > 1 RETURN;

    DECLARE @cod_usuario INT = ISNULL(TRY_CAST(SESSION_CONTEXT(N'cod_usuario') AS INT), 1);

    INSERT INTO dbo.auditoria
        (entidad, operacion, registro_id, valor_anterior, valor_nuevo, cod_usuario)
    SELECT
        'compra',
        CASE WHEN d.cod_compra IS NULL THEN 'INSERT'
             WHEN i.cod_compra IS NULL THEN 'DELETE'
             ELSE 'UPDATE' END,
        COALESCE(i.cod_compra, d.cod_compra),
        CASE WHEN d.cod_compra IS NULL THEN NULL
             ELSE CONCAT('estado=', d.estado) END,
        CASE WHEN i.cod_compra IS NULL THEN NULL
             ELSE CONCAT('estado=', i.estado) END,
        @cod_usuario
    FROM inserted i
    FULL OUTER JOIN deleted d ON d.cod_compra = i.cod_compra
    WHERE i.cod_compra IS NULL
       OR d.cod_compra IS NULL
       OR i.estado <> d.estado;
END;
GO

-- -------------------------------------------------------------
-- Trigger 4: factura (emision y total)
-- Guarda: 'tipo=...; numero=...; total=...' antes y despues del cambio.
-- Una factura no deberia modificarse; si se modifica, se audita
-- igual, sin filtrar por columna.
-- -------------------------------------------------------------
-- > Trigger 4: sin WHERE, registra cualquier cambio en una factura.
-- >   Un DELETE nunca llega a este trigger: lo frena antes trg_factura_no_borrar.
CREATE OR ALTER TRIGGER dbo.trg_factura_auditoria
ON dbo.factura
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    IF TRIGGER_NESTLEVEL() > 1 RETURN;

    DECLARE @cod_usuario INT = ISNULL(TRY_CAST(SESSION_CONTEXT(N'cod_usuario') AS INT), 1);

    INSERT INTO dbo.auditoria
        (entidad, operacion, registro_id, valor_anterior, valor_nuevo, cod_usuario)
    SELECT
        'factura',
        CASE WHEN d.cod_factura IS NULL THEN 'INSERT'
             WHEN i.cod_factura IS NULL THEN 'DELETE'
             ELSE 'UPDATE' END,
        COALESCE(i.cod_factura, d.cod_factura),
        CASE WHEN d.cod_factura IS NULL THEN NULL
             ELSE CONCAT('tipo=', d.tipo_comprobante, '; numero=', d.numero,
                         '; total=', d.total) END,
        CASE WHEN i.cod_factura IS NULL THEN NULL
             ELSE CONCAT('tipo=', i.tipo_comprobante, '; numero=', i.numero,
                         '; total=', i.total) END,
        @cod_usuario
    FROM inserted i
    FULL OUTER JOIN deleted d ON d.cod_factura = i.cod_factura;
END;
GO

-- -------------------------------------------------------------
-- Trigger 5: factura (impide el borrado)
-- Una factura es un comprobante fiscal: no se puede eliminar.
-- INSTEAD OF reemplaza al DELETE, así que la fila nunca se borra.
-- Codigo de error propio: 50012.
-- -------------------------------------------------------------
-- > Trigger 5, INSTEAD OF DELETE: cuando alguien ejecuta DELETE FROM factura, SQL
-- >   Server ejecuta ESTE codigo en lugar del borrado. El codigo no borra nada y
-- >   lanza el error 50012, asi que la factura sigue ahi y no se audita nada (A7).
-- >   IF EXISTS (SELECT 1 FROM deleted): solo da error si el DELETE alcanzaba
-- >   alguna fila; un DELETE que no encuentra facturas no falla.
-- >   Diferencia con un permiso DENY DELETE: DENY no alcanza a dbo ni a sysadmin;
-- >   el trigger frena a todos (salvo que alguien lo deshabilite).
CREATE OR ALTER TRIGGER dbo.trg_factura_no_borrar
ON dbo.factura
INSTEAD OF DELETE
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (SELECT 1 FROM deleted)
        THROW 50012, 'Una factura no se puede eliminar: es un comprobante fiscal.', 1;
END;
GO

-- #############################################################
-- PARTE 2: DEMOSTRACION (ejecutar cada bloque por separado)
-- #############################################################

-- =============================================================
-- 0. Verificacion: los cuatro triggers de auditoria quedaron creados
-- Esperado: 4 filas, todas AFTER y habilitadas.
-- =============================================================
-- > sys.triggers: vista del catalogo con los triggers de la base.
-- >   parent_id es la tabla del trigger: OBJECT_NAME(parent_id) da su nombre.
-- >   is_instead_of_trigger = 1 -> INSTEAD OF; 0 -> AFTER. is_disabled = 0 -> activo.
SELECT OBJECT_NAME(parent_id) AS tabla,
       name                   AS trigger_name,
       CASE WHEN is_instead_of_trigger = 1 THEN 'INSTEAD OF' ELSE 'AFTER' END AS momento,
       is_disabled
FROM sys.triggers
WHERE parent_id IN (OBJECT_ID('dbo.producto'), OBJECT_ID('dbo.pedido'),
                    OBJECT_ID('dbo.compra'),   OBJECT_ID('dbo.factura'))
  AND name LIKE '%auditoria'
ORDER BY tabla;
GO

-- =============================================================
-- A1. UPDATE de stock con COMMIT
-- Usuario: 3 (lramirez, DEPOSITO).
-- Esperado: stock 40 -> 39 y una fila nueva en auditoria:
--   valor_anterior = 'precio_lista=20661.16; stock=40'
--   valor_nuevo    = 'precio_lista=20661.16; stock=39'
-- Despues se repone el stock y se borran las dos filas de la
-- prueba, para dejar la tabla como estaba.
-- =============================================================
-- > Patron de cada prueba: se guarda el ultimo cod_auditoria ANTES de la prueba
-- >   (MAX), y despues se miran solo las filas con un codigo mayor. Al final se
-- >   borran, para dejar la auditoria como estaba (10 filas).
-- > EXEC sys.sp_set_session_context @key = N'cod_usuario', @value = 3: simula lo
-- >   que haria la aplicacion al loguearse el empleado 3 (lramirez). Al final se
-- >   vuelve a NULL.
DECLARE @antes1 INT = (SELECT ISNULL(MAX(cod_auditoria), 0) FROM auditoria);

EXEC sys.sp_set_session_context @key = N'cod_usuario', @value = 3;

UPDATE producto SET stock = stock - 1 WHERE cod_producto = 2;

SELECT 'STOCK MODIFICADO' AS momento, cod_producto, stock
FROM producto WHERE cod_producto = 2;

SELECT cod_auditoria, entidad, operacion, registro_id,
       valor_anterior, valor_nuevo, cod_usuario, fecha
FROM auditoria
WHERE cod_auditoria > @antes1;

-- Limpieza
UPDATE producto SET stock = stock + 1 WHERE cod_producto = 2;
DELETE FROM auditoria WHERE cod_auditoria > @antes1;
EXEC sys.sp_set_session_context @key = N'cod_usuario', @value = NULL;

SELECT 'TRAS LA LIMPIEZA' AS momento, cod_producto, stock
FROM producto WHERE cod_producto = 2;

SELECT COUNT(*) AS auditoria_total FROM auditoria;
GO

-- =============================================================
-- A2. INSERT y DELETE de un producto
-- Usuario: 9 (vlopez, ADMINISTRADOR).
-- Esperado: dos filas. En el INSERT valor_anterior es NULL; en el
-- DELETE valor_nuevo es NULL. Las dos guardan precio y stock.
-- =============================================================
DECLARE @antes2 INT = (SELECT ISNULL(MAX(cod_auditoria), 0) FROM auditoria);

EXEC sys.sp_set_session_context @key = N'cod_usuario', @value = 9;

INSERT INTO producto (nombre, descripcion, precio_lista, cod_alicuota, stock, cod_categoria)
VALUES ('Producto de prueba', 'Alta y baja para la demo de auditoria', 1000.00, 5, 3, 3);

DECLARE @id2 INT = SCOPE_IDENTITY();

DELETE FROM producto WHERE cod_producto = @id2;

SELECT cod_auditoria, entidad, operacion, registro_id,
       valor_anterior, valor_nuevo, cod_usuario
FROM auditoria
WHERE cod_auditoria > @antes2
ORDER BY cod_auditoria;

-- Limpieza
DELETE FROM auditoria WHERE cod_auditoria > @antes2;
EXEC sys.sp_set_session_context @key = N'cod_usuario', @value = NULL;

SELECT COUNT(*) AS auditoria_total FROM auditoria;
GO

-- =============================================================
-- A3. Venta completa con el procedimiento del Tema 1
-- Usuario: 4 (afernandez, DEPOSITO).
-- No se toca el procedimiento: el trigger audita solo el alta del
-- pedido y la baja de stock. Todo va en una transaccion que se
-- revierte, asi que no queda ningun cambio (ni auditoria): eso
-- muestra que la auditoria es transaccional.
-- Esperado dentro de la transaccion: 2 filas (pedido INSERT y
-- producto UPDATE, stock 40 -> 39). Tras el ROLLBACK: 10 filas y
-- stock 40.
-- =============================================================
-- > A3 demuestra que la auditoria es TRANSACCIONAL: dentro de la transaccion se
-- >   ven las 2 filas nuevas (pedido INSERT y producto UPDATE). Despues del
-- >   ROLLBACK desaparecen junto con la venta: no queda auditado algo que no paso.
DECLARE @antes3 INT = (SELECT ISNULL(MAX(cod_auditoria), 0) FROM auditoria);

EXEC sys.sp_set_session_context @key = N'cod_usuario', @value = 4;

BEGIN TRANSACTION;

    DECLARE @items3 dbo.tipo_items_pedido;
    DECLARE @nuevo3 INT;

    INSERT INTO @items3 (cod_producto, cantidad) VALUES (2, 1);

    EXEC dbo.sp_registrar_venta_completa
         @cod_cliente     = 1,
         @cod_metodo_pago = 1,
         @ref_transaccion = 'TX-A3-AUDITORIA',
         @items           = @items3,
         @cod_pedido      = @nuevo3 OUTPUT;

    SELECT cod_auditoria, entidad, operacion, registro_id,
           valor_anterior, valor_nuevo, cod_usuario
    FROM auditoria
    WHERE cod_auditoria > @antes3
    ORDER BY cod_auditoria;

ROLLBACK TRANSACTION;

EXEC sys.sp_set_session_context @key = N'cod_usuario', @value = NULL;

SELECT COUNT(*) AS auditoria_tras_rollback FROM auditoria;
SELECT cod_producto, stock FROM producto WHERE cod_producto = 2;
GO

-- =============================================================
-- A4. Si la auditoria falla, el cambio no se aplica
-- Se fija un usuario inexistente (999). El trigger no puede
-- insertar en auditoria (FK 547) y el UPDATE de stock se revierte.
-- Esperado: error 547; stock 40; auditoria 10.
-- =============================================================
-- > A4: el empleado 999 no existe. Al insertar en auditoria falla la FK hacia
-- >   usuario (error 547). Como el trigger corre dentro de la transaccion del
-- >   UPDATE, el UPDATE tambien se revierte: no hay cambio sin auditoria.
DECLARE @antes4 INT = (SELECT COUNT(*) FROM auditoria);

EXEC sys.sp_set_session_context @key = N'cod_usuario', @value = 999;

BEGIN TRY
    UPDATE producto SET stock = stock - 1 WHERE cod_producto = 2;
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS error, ERROR_MESSAGE() AS mensaje;
END CATCH;

EXEC sys.sp_set_session_context @key = N'cod_usuario', @value = NULL;

SELECT cod_producto, stock FROM producto WHERE cod_producto = 2;
SELECT @antes4 AS auditoria_antes, COUNT(*) AS auditoria_despues FROM auditoria;
GO

-- =============================================================
-- A5. Un solo UPDATE sobre los 10 productos
-- Usuario: 9. El trigger procesa todas las filas de inserted de
-- una vez: 10 filas de auditoria en una sola sentencia. Es la
-- prueba de que es set-based y no fila por fila.
-- Esperado: filas_auditadas = 10; despues de la limpieza, el stock
-- vuelve a su valor y auditoria_total es 10.
-- =============================================================
DECLARE @antes5 INT = (SELECT ISNULL(MAX(cod_auditoria), 0) FROM auditoria);

EXEC sys.sp_set_session_context @key = N'cod_usuario', @value = 9;

UPDATE producto SET stock = stock + 1;

SELECT COUNT(*) AS filas_auditadas FROM auditoria WHERE cod_auditoria > @antes5;

SELECT TOP 3 cod_auditoria, operacion, registro_id, valor_anterior, valor_nuevo
FROM auditoria
WHERE cod_auditoria > @antes5
ORDER BY cod_auditoria;

-- Limpieza
UPDATE producto SET stock = stock - 1;
DELETE FROM auditoria WHERE cod_auditoria > @antes5;
EXEC sys.sp_set_session_context @key = N'cod_usuario', @value = NULL;

SELECT COUNT(*) AS auditoria_total FROM auditoria;
GO

-- =============================================================
-- A6. Usuario de la base de datos en la auditoria
-- usuario_bd se completa solo con SUSER_SNAME(), sin que los
-- triggers lo indiquen. Esperado: una fila cuyo usuario_bd es igual
-- al login de la sesion; despues se limpia.
-- =============================================================
DECLARE @antes6 INT = (SELECT ISNULL(MAX(cod_auditoria), 0) FROM auditoria);

UPDATE producto SET stock = stock - 1 WHERE cod_producto = 2;

SELECT cod_auditoria, entidad, operacion, usuario_bd, SUSER_SNAME() AS login_sesion,
       CASE WHEN usuario_bd = SUSER_SNAME() THEN 'coincide' ELSE 'NO COINCIDE' END AS control
FROM auditoria
WHERE cod_auditoria > @antes6;

-- Limpieza
UPDATE producto SET stock = stock + 1 WHERE cod_producto = 2;
DELETE FROM auditoria WHERE cod_auditoria > @antes6;

SELECT COUNT(*) AS auditoria_total FROM auditoria;
GO

-- =============================================================
-- A7. Intentar borrar una factura
-- Esperado: error 50012, la factura sigue y la auditoria no cambia.
-- =============================================================
DECLARE @facturas7 INT = (SELECT COUNT(*) FROM factura);
DECLARE @auditoria7 INT = (SELECT COUNT(*) FROM auditoria);

BEGIN TRY
    DELETE FROM factura WHERE cod_factura = 1;
    SELECT 'NO FALLO' AS resultado;
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS error, ERROR_MESSAGE() AS mensaje;
END CATCH;

SELECT @facturas7 AS facturas_antes, COUNT(*) AS facturas_despues FROM factura;
SELECT @auditoria7 AS auditoria_antes, COUNT(*) AS auditoria_despues FROM auditoria;
GO
