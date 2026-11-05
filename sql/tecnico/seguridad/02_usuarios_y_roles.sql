-- =============================================================
-- ETAPA V - Seguridad: permisos a nivel de usuarios y de roles
-- Requiere el script de procedimientos_funciones
-- (sp_registrar_venta_completa). Los datos que modifican las pruebas
-- se revierten. Se limpia con 99_limpieza_usuarios.sql.
--
-- Las contraseñas son solo para esta demostración.
-- Las pruebas usan EXECUTE AS LOGIN, que funciona en cualquier modo de
-- autenticación. Para conectarse con estos usuarios desde SSMS o sqlcmd,
-- el servidor tiene que estar en modo mixto.
-- =============================================================

-- =============================================================
-- GUIA DE ESTUDIO PARA LA DEFENSA (rama estudio-defensa, no se sube)
-- Las lineas "-- >" son notas de estudio.
-- > Dos niveles de seguridad en SQL Server:
-- >   LOGIN (servidor): permite CONECTARSE al servidor. Se crea en master.
-- >   USER (base de datos): permite entrar a UNA base, y ahi se le dan permisos.
-- >   Un usuario se crea "FOR LOGIN": conecta el login con la base.
-- > Modo de autenticacion:
-- >   Solo Windows: se entra con la cuenta de Windows.
-- >   Mixto: ademas acepta logins de SQL Server con usuario y contrasena (los de
-- >   este script). Hay que activarlo en el servidor y reiniciar el servicio.
-- > Roles fijos de la base usados aca:
-- >   db_owner     : puede hacer todo en la base.
-- >   db_datareader: puede leer (SELECT) todas las tablas, y nada mas.
-- > Parte 1: permisos dados a cada usuario. Parte 2: permisos dados a un ROL, que
-- >   reciben todos sus miembros.
-- =============================================================
-- > SERVERPROPERTY('IsIntegratedSecurityOnly'): 1 = solo Windows; 0 = mixto.
-- M1. Modo de autenticación. 0 = mixto (Windows y SQL Server); 1 = solo Windows.
SELECT SERVERPROPERTY('IsIntegratedSecurityOnly') AS solo_windows;
GO

-- Inicios de sesión del servidor
-- > SUSER_ID('x') IS NULL: crea el login solo si no existe.
-- > CREATE LOGIN ... WITH PASSWORD: login de SQL Server, con contrasena. SQL Server
-- >   aplica la politica de contrasenas de Windows (largo y complejidad).
IF SUSER_ID('smarthome_admin') IS NULL
    CREATE LOGIN smarthome_admin WITH PASSWORD = 'Demo.Admin.2026!';
IF SUSER_ID('smarthome_lectura') IS NULL
    CREATE LOGIN smarthome_lectura WITH PASSWORD = 'Demo.Lectura.2026!';
IF SUSER_ID('smarthome_con_rol') IS NULL
    CREATE LOGIN smarthome_con_rol WITH PASSWORD = 'Demo.ConRol.2026!';
IF SUSER_ID('smarthome_sin_rol') IS NULL
    CREATE LOGIN smarthome_sin_rol WITH PASSWORD = 'Demo.SinRol.2026!';
GO

USE smarthome_store;
GO
SET NOCOUNT ON;
GO

-- =============================================================
-- PARTE 1: permisos a nivel de usuarios
-- =============================================================
IF DATABASE_PRINCIPAL_ID('smarthome_admin') IS NULL
    CREATE USER smarthome_admin FOR LOGIN smarthome_admin;
IF DATABASE_PRINCIPAL_ID('smarthome_lectura') IS NULL
    CREATE USER smarthome_lectura FOR LOGIN smarthome_lectura;
GO

ALTER ROLE db_owner ADD MEMBER smarthome_admin;
ALTER ROLE db_datareader ADD MEMBER smarthome_lectura;

-- El usuario de solo lectura puede ejecutar la venta. El procedimiento recibe
-- un tipo tabla, así que también necesita permiso sobre ese tipo.
GRANT EXECUTE ON dbo.sp_registrar_venta_completa TO smarthome_lectura;
GRANT EXECUTE ON TYPE::dbo.tipo_items_pedido TO smarthome_lectura;
GO

-- U1. INSERT directo con el administrador. Esperado: se inserta 1 fila; se revierte.
BEGIN TRANSACTION;

-- > EXECUTE AS LOGIN = 'x': la sesion pasa a actuar como ese login (y como su
-- >   usuario en esta base) hasta el REVERT. Asi se prueban permisos sin
-- >   conectarse con otra cuenta.
-- > USER_NAME(): el usuario de la base con el que se esta actuando.
EXECUTE AS LOGIN = 'smarthome_admin';
INSERT INTO dbo.pedido (calle, numero, ciudad, provincia, cod_postal, cod_cliente, cod_metodo_pago)
VALUES ('Prueba', '1', 'Corrientes', 'CORRIENTES', '3400', 1, 1);
SELECT 'U1' AS prueba, USER_NAME() AS usuario, @@ROWCOUNT AS filas_insertadas;
REVERT;

ROLLBACK TRANSACTION;
GO

-- U2. El usuario de solo lectura puede leer. Esperado: 12 pedidos.
EXECUTE AS LOGIN = 'smarthome_lectura';
SELECT 'U2' AS prueba, USER_NAME() AS usuario, COUNT(*) AS pedidos FROM dbo.pedido;
REVERT;
GO

-- U3. INSERT directo con el usuario de solo lectura. Esperado: error 229.
-- > U3 y U5: db_datareader solo da SELECT; un INSERT o un UPDATE dan error 229
-- >   (permiso denegado sobre el objeto).
EXECUTE AS LOGIN = 'smarthome_lectura';

BEGIN TRY
    INSERT INTO dbo.pedido (calle, numero, ciudad, provincia, cod_postal, cod_cliente, cod_metodo_pago)
    VALUES ('Prueba', '1', 'Corrientes', 'CORRIENTES', '3400', 1, 1);
    SELECT 'U3' AS prueba, 'NO FALLO' AS resultado;
END TRY
BEGIN CATCH
    SELECT 'U3' AS prueba, ERROR_NUMBER() AS error, ERROR_MESSAGE() AS mensaje;
END CATCH;

REVERT;
GO

-- U4. INSERT a través del procedimiento con el usuario de solo lectura.
-- Esperado: se crea el pedido y baja el stock, aunque no tenga permiso sobre las
-- tablas (encadenamiento de propiedad); se revierte.
BEGIN TRANSACTION;

-- > U4: el mismo usuario que no puede insertar en pedido vende a traves del
-- >   procedimiento. Tiene EXECUTE, y por el encadenamiento de propiedad (mismo
-- >   dueno, dbo) no se controlan sus permisos sobre pedido ni producto.
-- >   Ventaja: el usuario solo puede cambiar datos de la forma que el
-- >   procedimiento permite, con sus validaciones.
EXECUTE AS LOGIN = 'smarthome_lectura';

DECLARE @items dbo.tipo_items_pedido;
DECLARE @nuevo INT;

INSERT INTO @items (cod_producto, cantidad) VALUES (2, 1);

EXEC dbo.sp_registrar_venta_completa
     @cod_cliente     = 1,
     @cod_metodo_pago = 1,
     @ref_transaccion = 'TX-U4',
     @items           = @items,
     @cod_pedido      = @nuevo OUTPUT;

SELECT 'U4' AS prueba, USER_NAME() AS usuario, cod_pedido, estado, ref_transaccion
FROM dbo.pedido WHERE cod_pedido = @nuevo;

SELECT 'U4' AS prueba, cod_producto, stock FROM dbo.producto WHERE cod_producto = 2;

REVERT;

ROLLBACK TRANSACTION;
GO

-- U5. El usuario de solo lectura no puede modificar datos directamente.
-- Esperado: error 229.
EXECUTE AS LOGIN = 'smarthome_lectura';

BEGIN TRY
    UPDATE dbo.producto SET stock = stock + 1 WHERE cod_producto = 2;
    SELECT 'U5' AS prueba, 'NO FALLO' AS resultado;
END TRY
BEGIN CATCH
    SELECT 'U5' AS prueba, ERROR_NUMBER() AS error, ERROR_MESSAGE() AS mensaje;
END CATCH;

REVERT;
GO

-- =============================================================
-- PARTE 2: permisos a nivel de roles
-- =============================================================
-- > CREATE ROLE: rol definido por nosotros. GRANT SELECT ON producto TO rol: todos
-- >   sus miembros pueden leer producto y nada mas.
-- > Ventaja de los roles: si entra un empleado nuevo, se lo agrega al rol en vez
-- >   de repetir cada permiso.
IF DATABASE_PRINCIPAL_ID('rol_lectura_producto') IS NULL
    CREATE ROLE rol_lectura_producto;
GO

GRANT SELECT ON dbo.producto TO rol_lectura_producto;
GO

IF DATABASE_PRINCIPAL_ID('smarthome_con_rol') IS NULL
    CREATE USER smarthome_con_rol FOR LOGIN smarthome_con_rol;
IF DATABASE_PRINCIPAL_ID('smarthome_sin_rol') IS NULL
    CREATE USER smarthome_sin_rol FOR LOGIN smarthome_sin_rol;
GO

ALTER ROLE rol_lectura_producto ADD MEMBER smarthome_con_rol;
GO

-- R1. Usuario con el rol. Esperado: lee los 10 productos.
-- > R1, R2 y R3: con el rol lee producto (R1); sin el rol, error 229 (R2); con el
-- >   rol, pero sobre otra tabla, tambien 229 (R3): el permiso es solo sobre la
-- >   tabla indicada.
EXECUTE AS LOGIN = 'smarthome_con_rol';
SELECT 'R1' AS prueba, USER_NAME() AS usuario, COUNT(*) AS productos FROM dbo.producto;
REVERT;
GO

-- R2. Usuario sin el rol. Esperado: error 229.
EXECUTE AS LOGIN = 'smarthome_sin_rol';

BEGIN TRY
    SELECT 'R2' AS prueba, COUNT(*) AS productos FROM dbo.producto;
END TRY
BEGIN CATCH
    SELECT 'R2' AS prueba, USER_NAME() AS usuario, ERROR_NUMBER() AS error, ERROR_MESSAGE() AS mensaje;
END CATCH;

REVERT;
GO

-- R3. El rol solo alcanza a la tabla indicada. Esperado: error 229 sobre pedido.
EXECUTE AS LOGIN = 'smarthome_con_rol';

BEGIN TRY
    SELECT 'R3' AS prueba, COUNT(*) AS pedidos FROM dbo.pedido;
END TRY
BEGIN CATCH
    SELECT 'R3' AS prueba, USER_NAME() AS usuario, ERROR_NUMBER() AS error, ERROR_MESSAGE() AS mensaje;
END CATCH;

REVERT;
GO

-- Estado final. Esperado: 12 pedidos y stock 40; las pruebas no dejaron datos.
SELECT COUNT(*) AS pedidos, (SELECT stock FROM dbo.producto WHERE cod_producto = 2) AS stock_producto_2
FROM dbo.pedido;
GO
