-- =============================================================
-- ETAPA V - Seguridad: permisos sobre el estado del pedido
-- La aplicación solo puede cambiar el estado de un pedido a través
-- de los procedimientos, para que el stock cambie junto con el estado.
-- Requiere los scripts de procedimientos_funciones y transacciones.
--
-- Limitación: dbo y sysadmin no quedan alcanzados por DENY.
-- =============================================================

-- =============================================================
-- GUIA DE ESTUDIO PARA LA DEFENSA (rama estudio-defensa, no se sube)
-- Las lineas "-- >" son notas de estudio.
-- > Problema que resuelve: si la aplicacion pudiera hacer
-- >   UPDATE pedido SET estado = 'cancelado', el pedido quedaria cancelado sin
-- >   devolver el stock. Se le prohibe cambiar el estado directamente y se la
-- >   obliga a usar sp_cancelar_pedido, que repone el stock en la misma transaccion.
-- > Conceptos:
-- >   ROL : grupo de permisos. Se dan los permisos al rol y se agregan usuarios.
-- >   GRANT: da un permiso.  DENY: lo prohibe, y GANA sobre cualquier GRANT.
-- >   REVOKE: quita un GRANT o un DENY dado antes (aca no se usa).
-- >   Los permisos se pueden dar por COLUMNA: UPDATE ON pedido (estado_envio, ...).
-- > Encadenamiento de propiedad: si el procedimiento y las tablas tienen el mismo
-- >   dueno (dbo), SQL Server solo controla el permiso EXECUTE sobre el
-- >   procedimiento, no los permisos sobre las tablas que usa. Por eso la
-- >   aplicacion puede vender sin tener permiso sobre producto.
-- =============================================================
USE smarthome_store;
GO

-- > IF DATABASE_PRINCIPAL_ID('x') IS NULL: crea el rol o el usuario solo si no
-- >   existe, para que el script se pueda repetir.
-- > CREATE USER ... WITHOUT LOGIN: un usuario de la base que no tiene inicio de
-- >   sesion en el servidor. Sirve para probar permisos con EXECUTE AS USER.
-- > ALTER ROLE rol ADD MEMBER usuario: agrega el usuario al rol.
IF DATABASE_PRINCIPAL_ID('rol_aplicacion') IS NULL
    CREATE ROLE rol_aplicacion;
GO

IF DATABASE_PRINCIPAL_ID('usuario_aplicacion') IS NULL
    CREATE USER usuario_aplicacion WITHOUT LOGIN;
GO

ALTER ROLE rol_aplicacion ADD MEMBER usuario_aplicacion;
GO

-- > Permisos del rol de la aplicacion:
-- >   SELECT sobre pedido: puede leer los pedidos.
-- >   UPDATE solo sobre las columnas del envio: puede despachar (RN.22).
-- >   DENY UPDATE (estado): no puede cambiar el estado directamente.
-- >   EXECUTE sobre los dos procedimientos: vende y cancela solo con ellos.
-- >   EXECUTE ON TYPE::: el procedimiento recibe el tipo tabla, y para declarar una
-- >     variable de ese tipo tambien hace falta permiso sobre el tipo.
GRANT SELECT ON dbo.pedido TO rol_aplicacion;
GRANT UPDATE ON dbo.pedido (estado_envio, fecha_envio, transportista, fecha_entrega, nro_seguimiento, cod_usuario) TO rol_aplicacion;
DENY UPDATE ON dbo.pedido (estado) TO rol_aplicacion;
GRANT EXECUTE ON dbo.sp_registrar_venta_completa TO rol_aplicacion;
GRANT EXECUTE ON dbo.sp_cancelar_pedido TO rol_aplicacion;
GRANT EXECUTE ON TYPE::dbo.tipo_items_pedido TO rol_aplicacion;
GO

-- S1. UPDATE directo del estado. Esperado: error 230 y estado sin cambios.
-- > EXECUTE AS USER = 'usuario_aplicacion': a partir de aca la sesion actua como
-- >   ese usuario, con SUS permisos. REVERT vuelve al usuario original.
-- > Error 230: permiso denegado sobre una COLUMNA (estado).
EXECUTE AS USER = 'usuario_aplicacion';

BEGIN TRY
    UPDATE dbo.pedido SET estado = 'cancelado' WHERE cod_pedido = 10;
END TRY
BEGIN CATCH
    SELECT 'S1' AS prueba, ERROR_NUMBER() AS error, ERROR_MESSAGE() AS mensaje;
END CATCH;

REVERT;

SELECT 'S1' AS prueba, cod_pedido, estado FROM dbo.pedido WHERE cod_pedido = 10;
GO

-- S2. Datos de envío, permitidos. Esperado: 1 fila; se revierte.
BEGIN TRANSACTION;

EXECUTE AS USER = 'usuario_aplicacion';
UPDATE dbo.pedido SET transportista = 'Prueba' WHERE cod_pedido = 10;
SELECT 'S2' AS prueba, @@ROWCOUNT AS filas;
REVERT;

ROLLBACK TRANSACTION;
GO

-- S3. Venta y cancelación con los procedimientos, sin permisos sobre producto.
-- Esperado: pedido cancelado y stock 40; se revierte.
-- > S3: el mismo usuario que no puede cambiar el estado, ni tocar producto, vende y
-- >   cancela a traves de los procedimientos (encadenamiento de propiedad). El
-- >   stock vuelve a 40 porque sp_cancelar_pedido lo repone.
BEGIN TRANSACTION;

EXECUTE AS USER = 'usuario_aplicacion';

DECLARE @items dbo.tipo_items_pedido;
DECLARE @nuevo INT;

INSERT INTO @items (cod_producto, cantidad) VALUES (2, 1);

EXEC dbo.sp_registrar_venta_completa
     @cod_cliente     = 1,
     @cod_metodo_pago = 1,
     @ref_transaccion = 'TX-S3',
     @items           = @items,
     @cod_pedido      = @nuevo OUTPUT;

EXEC dbo.sp_cancelar_pedido @cod_pedido = @nuevo;

SELECT 'S3' AS prueba, estado FROM dbo.pedido WHERE cod_pedido = @nuevo;

REVERT;

SELECT 'S3' AS prueba, cod_producto, stock FROM dbo.producto WHERE cod_producto = 2;

ROLLBACK TRANSACTION;
GO

-- S4. Lectura y escritura directa de producto. Esperado: error 229.
-- > Error 229: permiso denegado sobre un OBJETO (la tabla producto entera).
EXECUTE AS USER = 'usuario_aplicacion';

BEGIN TRY
    UPDATE dbo.producto SET stock = stock + 1 WHERE cod_producto = 2;
END TRY
BEGIN CATCH
    SELECT 'S4' AS prueba, ERROR_NUMBER() AS error, ERROR_MESSAGE() AS mensaje;
END CATCH;

REVERT;
GO
