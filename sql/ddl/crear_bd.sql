-- =============================================================
-- DDL: creación de la base SmartHome Store (equipo 37)
-- Crea las 22 tablas con sus claves, restricciones y valores por defecto,
-- los dos índices filtrados de direccion y el trigger de la dirección principal.
-- Ejecutar primero, en un servidor que todavía no tenga la base smarthome_store.
-- Después se carga sql/dml/cargar_datos.sql.
-- Esperado: termina sin errores y la base queda con 22 tablas vacías.
-- =============================================================
-- =============================================================
-- GUIA DE ESTUDIO PARA LA DEFENSA (rama estudio-defensa, no se sube)
-- Las lineas "-- >" son notas de estudio.
-- > Tipos de restricciones (integridad):
-- >   PRIMARY KEY (PK): identifica cada fila; no se repite y no admite NULL.
-- >     Crea un indice agrupado por defecto.
-- >   FOREIGN KEY (FK): el valor tiene que existir en la tabla referenciada
-- >     (integridad referencial). Ejemplo: no hay un pedido de un cliente inexistente.
-- >   UNIQUE (UQ): no se repite, pero no es la clave (por ejemplo, el email).
-- >   CHECK (CK): una condicion que cada fila tiene que cumplir (stock >= 0).
-- >   DEFAULT (DF): el valor que toma la columna si no se indica.
-- >   NOT NULL: la columna es obligatoria.
-- > IDENTITY: SQL Server genera el codigo solo (1, 2, 3...). No se reutilizan los
-- >   valores ni se vuelven atras con un ROLLBACK.
-- > Acciones de una FK al borrar o actualizar la fila referenciada:
-- >   ON DELETE NO ACTION: no deja borrar si hay filas que la referencian (un
-- >     cliente con pedidos no se puede borrar).
-- >   ON DELETE CASCADE: borra tambien las filas que la referencian (al borrar un
-- >     pedido se borran sus renglones).
-- >   ON UPDATE CASCADE: si cambia el codigo, se actualiza en las tablas que lo usan.
-- > Nombres: PK_tabla, FK_tabla_otra, UQ_..., CK_..., DF_...: con nombre propio,
-- >   el mensaje de error dice que regla fallo.
-- > GO: separa lotes. Un CREATE TRIGGER, por ejemplo, tiene que ir solo en su lote.
-- > Orden de las tablas: primero las que no dependen de otras (provincia), despues
-- >   las que las referencian (localidad, cliente...). Una FK no puede apuntar a
-- >   una tabla que todavia no existe.
-- =============================================================
CREATE DATABASE smarthome_store;
GO
USE smarthome_store;
GO
SET QUOTED_IDENTIFIER ON; -- lo exigen los indices filtrados de direccion
GO
-- Catálogo de provincias (RN.29). El nombre no se repite.
CREATE TABLE provincia
(
  cod_provincia INT IDENTITY CONSTRAINT PK_provincia PRIMARY KEY,
  nombre VARCHAR(50) NOT NULL,
  CONSTRAINT UQ_provincia_nombre UNIQUE (nombre)
);
GO
-- Catálogo de localidades: cada una pertenece a una provincia (RN.29).
-- Hay nombres repetidos en provincias distintas, por eso la unicidad es nombre + provincia.
CREATE TABLE localidad
(
  cod_localidad INT IDENTITY CONSTRAINT PK_localidad PRIMARY KEY,
  nombre VARCHAR(50) NOT NULL,
  cod_provincia INT NOT NULL,
  CONSTRAINT UQ_localidad_nombre_provincia UNIQUE (nombre, cod_provincia),
  CONSTRAINT FK_localidad_provincia FOREIGN KEY (cod_provincia) REFERENCES provincia(cod_provincia) ON DELETE NO ACTION ON UPDATE CASCADE
);
GO
-- Clientes de la tienda online (RN.01). El email es único y debe tener un formato válido.
-- La contraseña se guarda como hash y la fecha de alta es la actual (RN.16).
-- Las direcciones están en la tabla direccion: el cliente puede registrarse sin ellas (RN.29)
-- y solo necesita una para generar un pedido (RN.01).
-- > CHECK (email LIKE '%_@__%.__%'): un control simple de formato.
-- >   % = cualquier cantidad de caracteres; _ = exactamente un caracter.
-- >   Exige algo, una arroba, algo, un punto y al menos dos caracteres.
-- > CHECK (activo IN (0,1)): un BIT ya solo admite 0, 1 o NULL; el CHECK lo deja
-- >   explicito.
CREATE TABLE cliente
(
  cod_cliente INT IDENTITY CONSTRAINT PK_cliente PRIMARY KEY,
  nombre VARCHAR(50) NOT NULL,
  apellido VARCHAR(50) NOT NULL,
  email VARCHAR(100) NOT NULL,
  contrasena_hash VARCHAR(255) NOT NULL,
  fecha_registro DATE NOT NULL CONSTRAINT DF_cliente_fecha_registro DEFAULT CAST(GETDATE() AS DATE),
  activo BIT NOT NULL CONSTRAINT DF_cliente_activo DEFAULT 1,
  telefono VARCHAR (20) NOT NULL,
  CONSTRAINT UQ_cliente_email UNIQUE (email),
  CONSTRAINT CK_cliente_estado CHECK(activo IN (0,1)),
  CONSTRAINT CK_cliente_email CHECK (email LIKE '%_@__%.__%')
);
GO
-- Usuarios internos (RN.12): nombre único y rol DEPOSITO, ADMINISTRADOR o SOPORTE,
-- escrito en mayúsculas (RN.13). estado = 0 da de baja al usuario sin borrarlo.
CREATE TABLE usuario
(
  cod_usuario INT IDENTITY CONSTRAINT PK_usuario PRIMARY KEY,
  nombre_usuario VARCHAR(50) NOT NULL,
  contrasena_hash VARCHAR(255) NOT NULL,
  rol VARCHAR(20) NOT NULL,
  estado BIT NOT NULL CONSTRAINT DF_usuario_estado DEFAULT 1,
  CONSTRAINT UQ_usuario_nombre_usuario UNIQUE (nombre_usuario), 
  CONSTRAINT CK_usuario_rol CHECK(UPPER(rol) IN ('DEPOSITO', 'ADMINISTRADOR', 'SOPORTE') AND rol = UPPER(rol)),
  CONSTRAINT CK_usuario_estado CHECK(estado IN (0,1))
);
GO
-- Categorías de productos (RN.06). cod_categoria_padre arma la jerarquía
-- (por ejemplo, Audio dentro de Electrónica); NULL indica una categoría principal.
-- > FK de categoria a si misma (autorrelacion): cod_categoria_padre apunta a otra
-- >   fila de la misma tabla y arma la jerarquia.
-- > UNIQUE (nombre, cod_categoria_padre): no puede haber dos subcategorias con el
-- >   mismo nombre dentro del mismo padre.
CREATE TABLE categoria
(
  cod_categoria INT IDENTITY CONSTRAINT PK_categoria PRIMARY KEY,
  nombre VARCHAR(50) NOT NULL,
  cod_categoria_padre INT NULL, --para una jerarquía
  activo BIT NOT NULL CONSTRAINT DF_categoria_activo DEFAULT 1,
  CONSTRAINT UQ_categoria_nombre_padre UNIQUE (nombre, cod_categoria_padre),
  CONSTRAINT FK_categoria_categoria_padre FOREIGN KEY (cod_categoria_padre) REFERENCES categoria(cod_categoria) ON DELETE NO ACTION ON UPDATE NO ACTION,
  CONSTRAINT CK_categoria_estado CHECK(activo IN (0,1))
);
GO
-- Catálogo de alícuotas de IVA (RN.28). El código no es IDENTITY: se usa el que asigna
-- ARCA a cada alícuota en la factura electrónica (decisión 13 de la Etapa II).
CREATE TABLE alicuota_iva
(
  cod_alicuota INT CONSTRAINT PK_alicuota_iva PRIMARY KEY,
  nombre VARCHAR(50) NOT NULL,
  porcentaje DECIMAL(4,2) NOT NULL,
  CONSTRAINT UQ_alicuota_iva_nombre UNIQUE (nombre),
  CONSTRAINT UQ_alicuota_iva_porcentaje UNIQUE (porcentaje),
  CONSTRAINT CK_alicuota_iva_porcentaje CHECK (porcentaje >= 0 AND porcentaje < 100)
);
GO
-- Productos del catálogo (RN.06 y RN.28). precio_lista es el precio neto, sin IVA (RN.19).
-- El stock nunca queda negativo (RN.09 y RN.11). activo = 0 da de baja el producto sin borrarlo.
CREATE TABLE producto
(
  cod_producto INT IDENTITY CONSTRAINT PK_producto PRIMARY KEY,
  nombre VARCHAR(50) NOT NULL,
  descripcion VARCHAR(1000) NOT NULL,
  precio_lista DECIMAL(10,2) NOT NULL,
  cod_alicuota INT NOT NULL,
  stock INT NOT NULL,
  cod_categoria INT NOT NULL,
  activo BIT NOT NULL CONSTRAINT DF_producto_activo DEFAULT 1,
  CONSTRAINT FK_producto_categoria FOREIGN KEY (cod_categoria) REFERENCES categoria(cod_categoria) ON DELETE NO ACTION ON UPDATE CASCADE,
  CONSTRAINT FK_producto_alicuota_iva FOREIGN KEY (cod_alicuota) REFERENCES alicuota_iva(cod_alicuota) ON DELETE NO ACTION ON UPDATE NO ACTION,
  CONSTRAINT CK_producto_estado CHECK(activo IN (0,1)),
  CONSTRAINT CK_producto_precio_lista CHECK (precio_lista > 0),
  CONSTRAINT CK_producto_stock CHECK (stock >= 0)
);
GO
-- Proveedores (RN.07). CUIT y email únicos; el CUIT con el formato NN-NNNNNNNN-N.
CREATE TABLE proveedor
(
  cod_proveedor INT IDENTITY CONSTRAINT PK_proveedor PRIMARY KEY,
  razon_social VARCHAR(50) NOT NULL,
  nombre VARCHAR(50) NOT NULL,
  email VARCHAR(100) NOT NULL,
  cuit VARCHAR(13) NOT NULL,
  activo BIT NOT NULL CONSTRAINT DF_proveedor_activo DEFAULT 1,
  CONSTRAINT UQ_proveedor_cuit UNIQUE (cuit),
  CONSTRAINT UQ_proveedor_email UNIQUE (email),
  CONSTRAINT CK_proveedor_email CHECK (email LIKE '%_@__%.__%'),
  CONSTRAINT CK_proveedor_cuit CHECK (cuit LIKE '[0-9][0-9]-[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-[0-9]'),
  CONSTRAINT CK_proveedor_estado CHECK(activo IN (0,1))
);
GO
-- Direcciones de clientes y proveedores (RN.04 y RN.29). Cada fila pertenece a un solo
-- titular: un cliente o un proveedor, nunca a los dos ni a ninguno (CK_direccion_titular).
-- Si se borra el titular, se borran sus direcciones (ON DELETE CASCADE).
-- > CK_direccion_titular: la direccion es de un cliente O de un proveedor.
-- >   (cliente no nulo y proveedor nulo) o (cliente nulo y proveedor no nulo).
-- >   Una sola tabla para los dos titulares evita repetir la estructura.
CREATE TABLE direccion
(
  cod_direccion INT IDENTITY CONSTRAINT PK_direccion PRIMARY KEY,
  calle VARCHAR(50) NOT NULL,
  numero VARCHAR(10) NOT NULL,
  cod_postal VARCHAR(10) NOT NULL,
  principal BIT NOT NULL CONSTRAINT DF_direccion_principal DEFAULT 0,
  cod_localidad INT NOT NULL,
  cod_cliente INT NULL,
  cod_proveedor INT NULL,
  CONSTRAINT FK_direccion_localidad FOREIGN KEY (cod_localidad) REFERENCES localidad(cod_localidad) ON DELETE NO ACTION ON UPDATE CASCADE,
  CONSTRAINT FK_direccion_cliente FOREIGN KEY (cod_cliente) REFERENCES cliente(cod_cliente) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT FK_direccion_proveedor FOREIGN KEY (cod_proveedor) REFERENCES proveedor(cod_proveedor) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT CK_direccion_titular CHECK ((cod_cliente IS NOT NULL AND cod_proveedor IS NULL) OR (cod_cliente IS NULL AND cod_proveedor IS NOT NULL))
);
GO
-- Cada titular tiene como máximo una dirección principal (RN.04 y RN.29).
-- Son índices filtrados: solo cuentan las filas con principal = 1.
-- > INDICE UNICO FILTRADO: "UNIQUE ... WHERE principal = 1" hace que la unicidad
-- >   valga solo para las filas principales. Cada cliente puede tener muchas
-- >   direcciones, pero solo una con principal = 1. Un UNIQUE comun sobre
-- >   cod_cliente impediria tener mas de una direccion.
-- > Los indices filtrados exigen SET QUOTED_IDENTIFIER ON: por eso esta al
-- >   principio del script.
CREATE UNIQUE INDEX UQ_direccion_principal_cliente ON direccion(cod_cliente) WHERE principal = 1 AND cod_cliente IS NOT NULL;
GO
CREATE UNIQUE INDEX UQ_direccion_principal_proveedor ON direccion(cod_proveedor) WHERE principal = 1 AND cod_proveedor IS NOT NULL;
GO
-- Si un titular con direcciones se queda sin principal, se marca la más reciente (RN.04)
-- > trg_direccion_principal, trigger AFTER INSERT, UPDATE, DELETE sobre direccion:
-- >   si un titular con direcciones se queda SIN principal (por ejemplo, porque
-- >   se borro la principal), marca como principal la mas reciente (RN.04).
-- >   IF @@ROWCOUNT = 0 RETURN: si la sentencia no afecto filas, no hace nada.
-- >     Va primero, antes de que SET NOCOUNT cambie @@ROWCOUNT.
-- >   CTE "titulares": los clientes o proveedores afectados, de inserted y de
-- >     deleted. UNION (sin ALL) quita los repetidos.
-- >   CTE "sin_principal": por titular, MAX(cod_direccion) = la mas reciente.
-- >     HAVING MAX(CAST(principal AS INT)) = 0: el titular no tiene ninguna
-- >     principal. Se hace CAST porque MAX no acepta BIT.
-- >   UPDATE ... FROM ... JOIN: marca esas direcciones como principales.
-- >   Trabaja por conjuntos: un DELETE de varias direcciones lo resuelve de una vez.
CREATE TRIGGER trg_direccion_principal
ON direccion
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
  IF @@ROWCOUNT = 0 RETURN;
  SET NOCOUNT ON;

  WITH titulares AS
  (
    SELECT cod_cliente, cod_proveedor FROM inserted
    UNION
    SELECT cod_cliente, cod_proveedor FROM deleted
  ),
  sin_principal AS
  (
    SELECT MAX(x.cod_direccion) AS cod_direccion
    FROM direccion x
    INNER JOIN titulares t ON x.cod_cliente = t.cod_cliente OR x.cod_proveedor = t.cod_proveedor
    GROUP BY x.cod_cliente, x.cod_proveedor
    HAVING MAX(CAST(x.principal AS INT)) = 0
  )
  UPDATE x
  SET x.principal = 1
  FROM direccion x
  INNER JOIN sin_principal s ON s.cod_direccion = x.cod_direccion;
END;
GO
-- Métodos de pago aceptados (RN.05); el nombre no se repite.
CREATE TABLE metodo_pago
(
  cod_metodo_pago INT IDENTITY CONSTRAINT PK_metodo_pago PRIMARY KEY,
  nombre VARCHAR(50) NOT NULL,
  CONSTRAINT UQ_metodo_pago_nombre UNIQUE (nombre)
);
GO
-- Pedidos de venta (RN.02, RN.05 y RN.16). El total no se guarda: se calcula desde el detalle (RN.10).
-- La dirección de entrega se copia como texto, para que no cambie si después el cliente
-- modifica la suya (RN.04 y RN.29).
-- Un pago aprobado exige la referencia de la transacción (CK_pedido_ref_transaccion).
-- Los datos de envío se completan después del pago (RN.15), y cod_usuario es el empleado
-- de depósito que despachó el pedido (RN.22); por eso aceptan NULL.
-- > Las FK de pedido usan NO ACTION al borrar: no se puede borrar un cliente o un
-- >   metodo de pago que tenga pedidos (se pierde el historial de ventas).
-- > CK_pedido_fecha (fecha_pedido <= GETDATE()): no se registran pedidos con
-- >   fecha futura.
-- > CK_pedido_ref_transaccion: "estado_pago <> 'aprobado' OR ref NOT NULL"
-- >   quiere decir "si el pago esta aprobado, tiene que tener la referencia".
-- >   Es la forma de escribir un "si ... entonces" en un CHECK.
CREATE TABLE pedido
(
  cod_pedido INT IDENTITY CONSTRAINT PK_pedido PRIMARY KEY,
  fecha_pedido DATETIME NOT NULL CONSTRAINT DF_pedido_fecha_pedido DEFAULT GETDATE(),
  estado VARCHAR(20) NOT NULL CONSTRAINT DF_pedido_estado DEFAULT 'pendiente',
  estado_pago VARCHAR(20) NOT NULL CONSTRAINT DF_pedido_estado_pago DEFAULT 'pendiente',
  ref_transaccion VARCHAR(50) NULL,
  calle  VARCHAR(50) NOT NULL,
  numero VARCHAR(10) NOT NULL,
  ciudad VARCHAR(50) NOT NULL,
  provincia VARCHAR(50) NOT NULL,
  cod_postal VARCHAR(10) NOT NULL,
  estado_envio VARCHAR(20) NULL,
  fecha_envio DATETIME NULL,
  transportista VARCHAR(50) NULL,
  fecha_entrega DATE NULL,
  nro_seguimiento VARCHAR(50) NULL,
  cod_cliente INT NOT NULL,
  cod_metodo_pago INT NOT NULL,
  cod_usuario INT NULL,
  CONSTRAINT CK_pedido_estado CHECK (estado IN ('pendiente', 'confirmado', 'cancelado')),
  CONSTRAINT CK_pedido_estado_pago CHECK (estado_pago IN ('pendiente', 'aprobado', 'rechazado')),
  CONSTRAINT CK_pedido_estado_envio CHECK (estado_envio IS NULL OR estado_envio IN ('pendiente', 'despachado', 'entregado')),
  CONSTRAINT CK_pedido_fecha CHECK (fecha_pedido <= GETDATE()),
  CONSTRAINT CK_pedido_ref_transaccion CHECK (estado_pago <> 'aprobado' OR ref_transaccion IS NOT NULL),
  CONSTRAINT FK_pedido_cliente FOREIGN KEY (cod_cliente) REFERENCES cliente(cod_cliente) ON DELETE NO ACTION ON UPDATE CASCADE,
  CONSTRAINT FK_pedido_metodo_pago FOREIGN KEY (cod_metodo_pago) REFERENCES metodo_pago(cod_metodo_pago) ON DELETE NO ACTION ON UPDATE CASCADE,
  CONSTRAINT FK_pedido_usuario FOREIGN KEY (cod_usuario) REFERENCES usuario(cod_usuario)
  
);
GO
-- Compras a proveedores (RN.07 y RN.20). Nacen pendientes y suben el stock recién al
-- confirmarse (recibida). cod_usuario es el empleado de depósito que la registró (RN.13).
CREATE TABLE compra
(
  cod_compra INT IDENTITY CONSTRAINT PK_compra PRIMARY KEY,
  fecha DATETIME NOT NULL CONSTRAINT DF_compra_fecha DEFAULT GETDATE(),
  estado VARCHAR(20) NOT NULL CONSTRAINT DF_compra_estado DEFAULT 'pendiente',
  nro_comprobante_prov VARCHAR(50) NOT NULL CONSTRAINT DF_compra_nro_comprobante_prov DEFAULT 'S/N',
  cod_proveedor INT NOT NULL,
  cod_usuario INT NOT NULL,
  CONSTRAINT FK_compra_proveedor FOREIGN KEY (cod_proveedor) REFERENCES proveedor(cod_proveedor) ON DELETE NO ACTION ON UPDATE CASCADE,
  CONSTRAINT FK_compra_usuario  FOREIGN KEY (cod_usuario) REFERENCES usuario(cod_usuario) ON DELETE NO ACTION ON UPDATE CASCADE,
  CONSTRAINT CK_compra_estado CHECK (estado IN ('pendiente', 'recibida', 'cancelada')),
  CONSTRAINT CK_compra_fecha CHECK (fecha <= GETDATE())
);
GO
-- Registro de cambios sobre datos sensibles (RN.14), que completan los triggers de la Etapa V.
-- cod_usuario es el empleado que informa la aplicación, y usuario_bd, el login de
-- SQL Server que ejecutó la operación (se completa solo).
CREATE TABLE auditoria
(
  cod_auditoria INT IDENTITY CONSTRAINT PK_auditoria PRIMARY KEY,
  entidad VARCHAR(50) NOT NULL,
  operacion VARCHAR(10) NOT NULL,
  registro_id INT NOT NULL,
  fecha DATETIME NOT NULL CONSTRAINT DF_auditoria_fecha DEFAULT GETDATE(),
  valor_anterior VARCHAR(255) NULL,
  valor_nuevo VARCHAR(255) NULL,
  cod_usuario INT NOT NULL,
  usuario_bd VARCHAR(128) NOT NULL CONSTRAINT DF_auditoria_usuario_bd DEFAULT SUSER_SNAME(),
  CONSTRAINT FK_auditoria_usuario FOREIGN KEY (cod_usuario) REFERENCES usuario(cod_usuario) ON DELETE NO ACTION ON UPDATE CASCADE,
  CONSTRAINT CK_auditoria_operacion CHECK (operacion IN ('INSERT', 'UPDATE', 'DELETE'))
);
GO
-- Comprobante de venta (RN.17 y RN.21): una sola factura por pedido (UQ_factura_pedido)
-- y número único por punto de venta. La condición de IVA y el documento del cliente se
-- guardan en la factura y no en el cliente (RN.18). cod_usuario es quien la emitió.
-- > UQ_factura_pedido (cod_pedido): una sola factura por pedido. Es una relacion
-- >   1 a 1 entre pedido y factura (RN.17).
-- > UQ_factura_pto_nro (punto_venta, numero): el numero no se repite dentro del
-- >   punto de venta, como exige la facturacion electronica.
CREATE TABLE factura
(
  cod_factura INT IDENTITY CONSTRAINT PK_factura PRIMARY KEY,
  tipo_comprobante CHAR(1) NOT NULL,
  numero INT NOT NULL,
  fecha_emision DATE NOT NULL CONSTRAINT DF_factura_fecha_emision DEFAULT CAST(GETDATE() AS DATE),
  cond_iva_cliente VARCHAR(30) NOT NULL,
  subtotal DECIMAL(12,2) NOT NULL,
  iva_total DECIMAL(12,2) NOT NULL,
  total DECIMAL(12,2) NOT NULL,
  cae VARCHAR(14) NOT NULL,
  fecha_vto_cae DATE NOT NULL,
  tipo_documento_cliente VARCHAR(10) NULL,
  nro_documento_cliente VARCHAR(20) NULL,
  razon_social VARCHAR(100) NULL,
  punto_venta INT NOT NULL,
  cod_pedido INT NOT NULL,
  cod_usuario INT NOT NULL,
  CONSTRAINT FK_factura_pedido FOREIGN KEY (cod_pedido) REFERENCES pedido(cod_pedido) ON DELETE NO ACTION ON UPDATE CASCADE,
  CONSTRAINT FK_factura_usuario FOREIGN KEY (cod_usuario) REFERENCES usuario(cod_usuario) ON DELETE NO ACTION ON UPDATE CASCADE,
  CONSTRAINT CK_factura_montos CHECK (subtotal >= 0 AND iva_total >= 0 AND total >= 0),
  CONSTRAINT CK_factura_tipo_comprobante CHECK (tipo_comprobante IN ('A','B','C')),
  CONSTRAINT UQ_factura_pto_nro UNIQUE (punto_venta, numero),
  CONSTRAINT UQ_factura_pedido UNIQUE (cod_pedido)
);
GO
-- Renglones del pedido. Precio, alícuota e IVA se copian al vender y no cambian después
-- (RN.03, RN.19 y RN.28). Un producto aparece una sola vez por pedido (clave compuesta).
-- Si se borra el pedido, se borran sus renglones.
-- > Clave primaria COMPUESTA (cod_pedido, cod_producto): la clave es la pareja.
-- >   detalle_pedido es la tabla intermedia de la relacion muchos a muchos entre
-- >   pedido y producto, con atributos propios (cantidad, precio, IVA).
-- > Por que se copian precio y alicuota: si se leyeran del producto, una venta
-- >   vieja cambiaria de importe al cambiar el catalogo (RN.03).
CREATE TABLE detalle_pedido
(
  item INT NOT NULL,
  precio_unitario_venta DECIMAL(10,2) NOT NULL,
  cantidad INT NOT NULL,
  alicuota_iva DECIMAL(4,2) NOT NULL,
  iva_monto DECIMAL(10,2) NOT NULL,
  cod_pedido INT NOT NULL,
  cod_producto INT NOT NULL,
  CONSTRAINT PK_detalle_pedido PRIMARY KEY (cod_pedido, cod_producto),
  CONSTRAINT FK_detalle_pedido_pedido FOREIGN KEY (cod_pedido) REFERENCES pedido(cod_pedido) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT FK_detalle_pedido_producto FOREIGN KEY (cod_producto) REFERENCES producto(cod_producto) ON DELETE NO ACTION ON UPDATE CASCADE,
  CONSTRAINT CK_detalle_pedido_cantidad CHECK (cantidad > 0),
  CONSTRAINT CK_detalle_pedido_precio CHECK (precio_unitario_venta > 0)
);
GO
-- Renglones de la compra, con el costo unitario de ese momento (RN.08).
CREATE TABLE detalle_compra
(
  costo_unitario DECIMAL(10,2) NOT NULL,
  cantidad INT NOT NULL,
  cod_producto INT NOT NULL,
  cod_compra INT NOT NULL,
  CONSTRAINT PK_detalle_compra PRIMARY KEY (cod_producto, cod_compra),
  CONSTRAINT FK_detalle_compra_producto FOREIGN KEY (cod_producto) REFERENCES producto(cod_producto),
  CONSTRAINT FK_detalle_compra_compra FOREIGN KEY (cod_compra) REFERENCES compra(cod_compra) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT CK_detalle_compra_cantidad CHECK (cantidad > 0),
  CONSTRAINT CK_detalle_compra_costo CHECK (costo_unitario > 0)
);
GO
-- Promociones (RN.23). La fecha de fin no es anterior a la de inicio, y deben dar al menos
-- un beneficio: descuento de hasta 75 % o cuotas sin interés (de 2 a 36).
-- > CK_promocion_beneficio (descuento > 0 OR cuotas > 1): una promocion tiene que
-- >   dar al menos un beneficio. Se combina con los otros CHECK de rango.
CREATE TABLE promocion (
    cod_promocion        INT IDENTITY(1,1) NOT NULL,
    nombre               VARCHAR(100)      NOT NULL,
    descripcion          VARCHAR(500)      NOT NULL,
    fecha_inicio         DATETIME          NOT NULL,
    fecha_fin            DATETIME          NOT NULL,
    porcentaje_descuento DECIMAL(5,2)      NOT NULL CONSTRAINT DF_promocion_descuento DEFAULT 0,
    nro_cuotas           INT               NOT NULL CONSTRAINT DF_promocion_cuotas DEFAULT 1,
    CONSTRAINT PK_promocion PRIMARY KEY (cod_promocion),
    CONSTRAINT CK_promocion_fechas
        CHECK (fecha_fin >= fecha_inicio),
    CONSTRAINT CK_promocion_descuento
        CHECK (porcentaje_descuento >= 0 AND porcentaje_descuento <= 75),
    CONSTRAINT CK_promocion_cuotas
        CHECK (nro_cuotas BETWEEN 1 AND 36),
    CONSTRAINT CK_promocion_beneficio
        CHECK (porcentaje_descuento > 0 OR nro_cuotas > 1)
);
GO
-- Productos de cada promoción (RN.24): relación de muchos a muchos.
CREATE TABLE promocion_producto (
    cod_promocion INT NOT NULL,
    cod_producto  INT NOT NULL,
    CONSTRAINT PK_promocion_producto PRIMARY KEY (cod_promocion, cod_producto),
    CONSTRAINT FK_promprod_promocion FOREIGN KEY (cod_promocion)
        REFERENCES promocion (cod_promocion)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT FK_promprod_producto FOREIGN KEY (cod_producto)
        REFERENCES producto (cod_producto)
        ON DELETE CASCADE ON UPDATE CASCADE
);
GO
-- Banners de una promoción (RN.25), con una URL https única.
CREATE TABLE slide (
    cod_slide     INT IDENTITY(1,1) NOT NULL,
    url           VARCHAR(500)      NOT NULL,
    cod_promocion INT               NOT NULL,
    CONSTRAINT PK_slide PRIMARY KEY (cod_slide),
    CONSTRAINT UQ_slide_url UNIQUE (url),
    CONSTRAINT CK_slide_url CHECK (url LIKE 'https://%'),
    CONSTRAINT FK_slide_promocion FOREIGN KEY (cod_promocion)
        REFERENCES promocion (cod_promocion)
        ON DELETE CASCADE ON UPDATE CASCADE
);
GO
-- Imágenes y videos de un producto (RN.26), con una URL https única.
CREATE TABLE multimedia (
    cod_multimedia INT IDENTITY(1,1) NOT NULL,
    url            VARCHAR(500)      NOT NULL,
    tipo           VARCHAR(10)       NOT NULL,
    cod_producto   INT               NOT NULL,
    CONSTRAINT PK_multimedia PRIMARY KEY (cod_multimedia),
    CONSTRAINT UQ_multimedia_url UNIQUE (url),
    CONSTRAINT CK_multimedia_url CHECK (url LIKE 'https://%'),
    CONSTRAINT CK_multimedia_tipo CHECK (tipo IN ('imagen', 'video')),
    CONSTRAINT FK_multimedia_producto FOREIGN KEY (cod_producto)
        REFERENCES producto (cod_producto)
        ON DELETE CASCADE ON UPDATE CASCADE
);
GO
-- Catálogo de especificaciones técnicas (RN.27), con nombre único.
CREATE TABLE especificacion (
    cod_especificacion INT IDENTITY(1,1) NOT NULL,
    nombre             VARCHAR(100)      NOT NULL,
    CONSTRAINT PK_especificacion PRIMARY KEY (cod_especificacion),
    CONSTRAINT UQ_especificacion_nombre UNIQUE (nombre)
);
GO
-- Valor de cada especificación para un producto (RN.27); no puede quedar vacío.
CREATE TABLE especificacion_producto (
    cod_producto       INT          NOT NULL,
    cod_especificacion INT          NOT NULL,
    valor              VARCHAR(150) NOT NULL,
    CONSTRAINT PK_especificacion_producto
        PRIMARY KEY (cod_producto, cod_especificacion),
    CONSTRAINT FK_espprod_producto FOREIGN KEY (cod_producto)
        REFERENCES producto (cod_producto)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT FK_espprod_especificacion FOREIGN KEY (cod_especificacion)
        REFERENCES especificacion (cod_especificacion)
        ON DELETE NO ACTION ON UPDATE CASCADE,
    CONSTRAINT CK_espprod_valor CHECK (LEN(valor) > 0)
);
GO
