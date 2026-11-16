-- =============================================================
-- ETAPA V - Seguridad: limpieza
-- Elimina los usuarios, el rol y los inicios de sesión de
-- 02_usuarios_y_roles.sql. Los inicios de sesión son del servidor:
-- no se borran al eliminar la base.
-- =============================================================

USE smarthome_store;
GO

-- > ORDEN: primero los usuarios (viven en la base) y después los logins (viven en el servidor).
-- > IF EXISTS hace que no falle si ya se borraron: el script se puede ejecutar varias veces.
DROP USER IF EXISTS smarthome_admin;
DROP USER IF EXISTS smarthome_lectura;
DROP USER IF EXISTS smarthome_con_rol;
DROP USER IF EXISTS smarthome_sin_rol;
-- > DROP ROLE falla si el rol todavía tiene miembros: por eso va después de borrar a
-- >   smarthome_con_rol, que era su único miembro.
DROP ROLE IF EXISTS rol_lectura_producto;
GO

-- > Los logins son del servidor: sobreviven aunque se elimine la base, por eso hay que
-- >   borrarlos a mano. SUSER_ID devuelve NULL si el login no existe.
-- > rol_aplicacion y usuario_aplicacion (01_permisos_estado_pedido.sql) no se borran acá:
-- >   el usuario es WITHOUT LOGIN y los dos desaparecen al eliminar la base.
-- > Esperado: sin errores; SELECT name FROM sys.server_principals WHERE name LIKE 'smarthome%'
-- >   devuelve 0 filas.
IF SUSER_ID('smarthome_admin') IS NOT NULL DROP LOGIN smarthome_admin;
IF SUSER_ID('smarthome_lectura') IS NOT NULL DROP LOGIN smarthome_lectura;
IF SUSER_ID('smarthome_con_rol') IS NOT NULL DROP LOGIN smarthome_con_rol;
IF SUSER_ID('smarthome_sin_rol') IS NOT NULL DROP LOGIN smarthome_sin_rol;
GO
