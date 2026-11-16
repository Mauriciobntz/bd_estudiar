# Contexto para estudiar con Claude (web): los 5 temas técnicos de SmartHome Store

> **Cómo usarlo:** pegá este archivo entero (o subilo como adjunto) al principio de una conversación
> nueva en claude.ai, y después escribí lo que quieras: "tomame examen del tema 2", "explicame el
> encadenamiento de propiedad como si fuera la primera vez", "hacé de profesor y repreguntame", etc.
>
> Todo el código de este archivo es el código real del proyecto (copiado del repo, sin las notas de estudio).

---

## 0. Instrucciones para Claude

Sos mi tutor para la defensa oral del proyecto final de **Bases de Datos I (UNNE, 2026)**. Mañana cada
integrante defiende **uno de estos 5 temas técnicos, elegido al azar**, durante **5 a 7 minutos**, aplicado
al proyecto, y después el profesor hace preguntas. No importa quién lo programó: todos tenemos que poder
defender los cinco.

1. Procedimientos y funciones almacenadas
2. Manejo de transacciones (y transacciones anidadas)
3. Triggers de auditoría
4. Manejo de permisos a nivel de usuarios
5. Optimización de consultas a través de índices

Cómo quiero que me ayudes:
- Hablá en **español rioplatense**, claro y directo.
- Basate **en el código y los resultados de este documento**. Si algo no está acá, decímelo; no inventes
  números, nombres de objetos ni resultados.
- Cuando te pida examen: una pregunta por vez, esperá mi respuesta, corregime y repreguntá como lo haría
  un profesor exigente (por qué, qué pasaría si, qué alternativa había).
- Si me equivoco en un concepto, explicámelo con un ejemplo del proyecto.

---

## 1. El proyecto en un minuto

- **Caso:** SmartHome Store, tienda online de productos de domótica (Argentina). Vende a clientes,
  compra a proveedores, factura, maneja stock, promociones, envíos y auditoría.
- **Motor:** SQL Server (probado en SQL Server 2025 Express). Base `smarthome_store`.
- **Equipo 37:** Enzo Benitez, Lisandro "Licha" Lopez y Mercedes "Mechi" Fernandez.
- **Etapas:**
  - **I:** caso, 30 reglas de negocio (RN.01 a RN.30) y casos de uso.
  - **II:** DER, modelo relacional, normalización hasta 3FN y decisiones de diseño.
  - **III:** DDL (`sql/ddl/crear_bd.sql`, 22 tablas con PK, FK, CHECK, UNIQUE, DEFAULT), datos de
    prueba (`sql/dml/cargar_datos.sql`) y 52 pruebas de validación de restricciones.
  - **IV:** consultas (consulta avanzada con JOIN, GROUP BY/HAVING, subconsultas correlacionadas,
    CTE, EXISTS, `> ALL`, funciones de ventana; factura/comprobante; reporte agregado).
  - **V:** los 5 temas técnicos de este documento.

**Datos de prueba que conviene recordar** (salen de `cargar_datos.sql`):
- 12 pedidos (el 10 está pendiente, el 11 cancelado; el resto confirmados).
- 10 productos. El **producto 2** (auriculares) tiene **stock 40**; el producto 1 tiene 12; el producto 4
  (Funda Notebook) tiene una promoción del 35 % (precio final 5200,00 al 20/09/2026).
- 10 facturas y 10 filas iniciales en `auditoria`.
- Compra 9 pendiente (5 unidades del producto 1 y 5 del 9).

**Reglas de negocio que más aparecen:**

| RN | Qué dice (resumen) |
|---|---|
| RN.03 | El precio de venta se congela en el detalle: cambiar el precio de lista no altera pedidos viejos |
| RN.04 | El pedido usa la dirección principal del cliente u otra suya |
| RN.09 | El stock baja con la venta y sube con la compra confirmada |
| RN.10 | El total del pedido no se guarda: se calcula desde el detalle |
| RN.11 | No se vende sin stock suficiente |
| RN.14 | Los cambios importantes (precio, stock, estados, facturas) se auditan |
| RN.17/21 | Una factura por pedido; la factura es un comprobante fiscal |
| RN.19 | `precio_lista` es neto: el precio final suma el IVA |
| RN.20 | La compra nace pendiente y el stock sube solo al confirmarla |
| RN.24 | Si hay varias promociones vigentes se aplica la de mayor descuento |
| RN.28 | Cada producto tiene una alícuota de IVA |
| RN.30 | Cancelar un pedido confirmado repone el stock |

**Dónde está cada tema en el repo:**

| Tema | Teoría | Código |
|---|---|---|
| 1 | `docs/etapa-05/procedimientos_funciones/investigacion.md` | `docs/etapa-05/procedimientos_funciones/scripts.sql` |
| 2 | `docs/etapa-05/transacciones/investigacion.md` | `docs/etapa-05/transacciones/scripts.sql` |
| 3 | `docs/etapa-05/triggers_auditoria/investigacion.md` | `docs/etapa-05/triggers_auditoria/scripts.sql` |
| 4 | `docs/etapa-05/seguridad/investigacion.md` | `sql/tecnico/seguridad/01_permisos_estado_pedido.sql` y `02_usuarios_y_roles.sql` |
| 5 | `docs/etapa-05/optimizacion_indices/investigacion.md` | `sql/tecnico/indices/01_carga_masiva.sql` y `02_pruebas_indices.sql` |

**Quién hizo qué** (por si preguntan):
- **Licha:** tipo tabla, las 3 funciones de precio/total, `sp_registrar_venta_completa` y sus pruebas;
  transacciones T1 a T5; los 4 triggers de auditoría y las pruebas A1 a A5; datos de prueba; reporte agregado.
- **Mechi:** DDL original; consulta avanzada; ABM `usp_producto_*`; transacciones T7 a T16 y
  `usp_confirmar_compra`; comparación de eficiencia.
- **Enzo:** índices; seguridad; `sp_cancelar_pedido` (T6); `trg_factura_no_borrar`; A6 y A7;
  columna `usuario_bd`; normalización de ubicación; factura/comprobante; README.

---

## 2. Tema 1 — Procedimientos y funciones almacenadas

### Teoría

| | Función | Procedimiento |
|---|---|---|
| Devuelve | Un valor (escalar) o una tabla | Nada obligatorio; parámetros `OUTPUT`, conjuntos de resultados, código de retorno |
| Cómo se usa | Dentro de una consulta (`SELECT`, `WHERE`, `CROSS APPLY`) | Con `EXEC` |
| Modifica datos | No (no puede hacer INSERT/UPDATE/DELETE sobre tablas) | Sí |
| Transacciones | No puede abrirlas | Sí (`BEGIN TRAN`, `COMMIT`, `ROLLBACK`) |
| Manejo de errores | No admite `TRY/CATCH` ni `THROW` | Sí |

- **Tipos de función:** escalar (`RETURNS DECIMAL`), de tabla en línea (`RETURNS TABLE AS RETURN (SELECT ...)`,
  se comporta como una vista con parámetros) y de tabla multisentencia.
- **Ventajas:** reglas de negocio en un solo lugar (no dependen de quien escribe la consulta), plan de
  ejecución reutilizable, menos tráfico de red, y **seguridad**: se puede dar `EXECUTE` sin dar permiso
  sobre las tablas (ver tema 4).
- **Parámetros:** de entrada, `OUTPUT`, opcionales (con valor por defecto) y **de tipo tabla** (`READONLY`).

### Código: tipo tabla y funciones

```sql
-- Tipo tabla: lista de productos y cantidades de una venta
CREATE TYPE dbo.tipo_items_pedido AS TABLE
(
    cod_producto INT NOT NULL PRIMARY KEY,
    cantidad     INT NOT NULL CHECK (cantidad > 0)
);

-- Descuento vigente: el mayor entre las promociones vigentes (RN.24); 0 si no hay
CREATE OR ALTER FUNCTION dbo.fn_descuento_vigente (@cod_producto INT, @fecha DATETIME)
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

-- Precio final: lista + IVA (RN.19) - descuento vigente. NULL si el producto no existe
CREATE OR ALTER FUNCTION dbo.fn_precio_final (@cod_producto INT, @fecha DATETIME)
RETURNS DECIMAL(10,2)
AS
BEGIN
    DECLARE @precio DECIMAL(10,2);
    SELECT @precio = ROUND(
               p.precio_lista
               * (1 + a.porcentaje / 100)
               * (1 - dbo.fn_descuento_vigente(p.cod_producto, @fecha) / 100), 2)
    FROM dbo.producto p
    INNER JOIN dbo.alicuota_iva a ON a.cod_alicuota = p.cod_alicuota
    WHERE p.cod_producto = @cod_producto;
    RETURN @precio;
END;

-- Total del pedido: no se guarda, se calcula desde el detalle (RN.10)
CREATE OR ALTER FUNCTION dbo.fn_total_pedido (@cod_pedido INT)
RETURNS DECIMAL(12,2)
AS
BEGIN
    RETURN ISNULL(
        (SELECT SUM(cantidad * precio_unitario_venta)
         FROM dbo.detalle_pedido
         WHERE cod_pedido = @cod_pedido), 0);
END;

-- Función de tabla en línea: pedidos de un cliente con su monto
CREATE OR ALTER FUNCTION dbo.fn_pedidos_cliente (@cod_cliente INT)
RETURNS TABLE
AS
RETURN
(
    SELECT p.cod_pedido, p.fecha_pedido, p.estado, p.estado_pago,
           ISNULL(SUM(d.cantidad * d.precio_unitario_venta), 0) AS monto
    FROM dbo.pedido p
    LEFT JOIN dbo.detalle_pedido d ON d.cod_pedido = p.cod_pedido
    WHERE p.cod_cliente = @cod_cliente
    GROUP BY p.cod_pedido, p.fecha_pedido, p.estado, p.estado_pago
);
```

### Código: el procedimiento central de la venta

```sql
-- Errores propios: 50001 cliente inexistente/inactivo · 50002 método de pago inexistente
-- 50003 venta sin productos · 50004 producto inexistente/inactivo · 50005 stock insuficiente
-- 50006 falta la referencia de pago · 50007 la dirección no es del cliente
CREATE OR ALTER PROCEDURE dbo.sp_registrar_venta_completa
    @cod_cliente     INT,
    @cod_metodo_pago INT,
    @ref_transaccion VARCHAR(50),
    @items           dbo.tipo_items_pedido READONLY,   -- parámetro de tipo tabla
    @cod_pedido      INT OUTPUT,                        -- devuelve el pedido creado
    @cod_direccion   INT = NULL                         -- opcional: si no viene, la principal
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;   -- ante cualquier error, la transacción entera queda condenada

    -- Si quien llama ya abrió una transacción, no abrimos otra
    DECLARE @tran_propia BIT = CASE WHEN @@TRANCOUNT = 0 THEN 1 ELSE 0 END;
    DECLARE @ahora DATETIME = GETDATE();

    BEGIN TRY
        IF @tran_propia = 1 BEGIN TRANSACTION;

        -- 1. Validaciones
        IF NOT EXISTS (SELECT 1 FROM dbo.cliente WHERE cod_cliente = @cod_cliente AND activo = 1)
            THROW 50001, 'Cliente inexistente o inactivo.', 1;

        IF @cod_direccion IS NULL
            SELECT @cod_direccion = cod_direccion
            FROM dbo.direccion WHERE cod_cliente = @cod_cliente AND principal = 1;

        IF NOT EXISTS (SELECT 1 FROM dbo.direccion
                       WHERE cod_direccion = @cod_direccion AND cod_cliente = @cod_cliente)
            THROW 50007, 'La direccion no existe o no es del cliente.', 1;

        IF NOT EXISTS (SELECT 1 FROM dbo.metodo_pago WHERE cod_metodo_pago = @cod_metodo_pago)
            THROW 50002, 'Metodo de pago inexistente.', 1;

        IF @ref_transaccion IS NULL
            THROW 50006, 'Falta la referencia de la transaccion de pago.', 1;

        IF NOT EXISTS (SELECT 1 FROM @items)
            THROW 50003, 'La venta no tiene productos.', 1;

        IF EXISTS (SELECT 1 FROM @items i
                   LEFT JOIN dbo.producto p ON p.cod_producto = i.cod_producto
                   WHERE p.cod_producto IS NULL OR p.activo = 0)
            THROW 50004, 'Producto inexistente o inactivo.', 1;

        -- 2. Stock: bloqueo las filas para que nadie las cambie hasta terminar
        IF EXISTS (SELECT 1 FROM @items i
                   INNER JOIN dbo.producto p WITH (UPDLOCK, HOLDLOCK)
                           ON p.cod_producto = i.cod_producto
                   WHERE p.stock < i.cantidad)
            THROW 50005, 'Stock insuficiente para al menos un producto de la venta.', 1;

        -- 3. Encabezado (copia la dirección: el pedido guarda dónde se envió)
        INSERT INTO dbo.pedido (estado, estado_pago, ref_transaccion,
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

        SET @cod_pedido = SCOPE_IDENTITY();   -- no @@IDENTITY: el trigger inserta en auditoria

        -- 4. Detalle con precio, alícuota e IVA congelados (RN.03, RN.19, RN.28)
        INSERT INTO dbo.detalle_pedido (cod_pedido, cod_producto, item, cantidad,
                                        precio_unitario_venta, alicuota_iva, iva_monto)
        SELECT @cod_pedido, i.cod_producto,
               ROW_NUMBER() OVER (ORDER BY i.cod_producto),
               i.cantidad, pf.precio, a.porcentaje,
               ROUND(i.cantidad * pf.precio
                     - (i.cantidad * pf.precio) / (1 + a.porcentaje / 100), 2)
        FROM @items i
        INNER JOIN dbo.producto p ON p.cod_producto = i.cod_producto
        INNER JOIN dbo.alicuota_iva a ON a.cod_alicuota = p.cod_alicuota
        CROSS APPLY (SELECT dbo.fn_precio_final(p.cod_producto, @ahora) AS precio) pf;

        -- 5. Salida de stock (RN.09)
        UPDATE p SET p.stock = p.stock - i.cantidad
        FROM dbo.producto p
        INNER JOIN @items i ON i.cod_producto = p.cod_producto;

        IF @tran_propia = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @tran_propia = 1 AND @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;   -- re-lanza el error original a quien llamó
    END CATCH
END;
```

**Cómo se llama:**

```sql
DECLARE @items dbo.tipo_items_pedido, @nuevo INT;
INSERT INTO @items (cod_producto, cantidad) VALUES (2, 2), (4, 1);

EXEC dbo.sp_registrar_venta_completa
     @cod_cliente = 1, @cod_metodo_pago = 1, @ref_transaccion = 'TX-DEMO',
     @items = @items, @cod_pedido = @nuevo OUTPUT;

SELECT @nuevo AS pedido_creado, dbo.fn_total_pedido(@nuevo) AS total;
```

### Código: ABM de productos (baja lógica)

```sql
CREATE OR ALTER PROCEDURE dbo.usp_producto_eliminar
    @cod_producto INT,
    @resultado    VARCHAR(12) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM dbo.producto WHERE cod_producto = @cod_producto)
            THROW 50121, 'El producto indicado no existe.', 1;

        -- Sin historial: se borra. Con historial: baja lógica (no se pierde trazabilidad)
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
```

También existen `usp_producto_insertar` (errores 50101-50104, devuelve el código con `OUTPUT`) y
`usp_producto_modificar` (50111-50114), y la función `fn_stock_disponible` (0 si el producto no existe
o está inactivo).

### Resultados de las pruebas

| Prueba | Caso | Resultado |
|---|---|---|
| A1 | Precio al 20/09/2026 | Producto 4 (Funda Notebook): descuento 35 %, precio 5200,00 |
| A2 | Totales de pedidos 1, 2 y 9 | 245.000,00 / 89.250,00 / 405.000,01 |
| A3 | Función contra precios guardados | 0 diferencias |
| B1 | Venta 2 auriculares + 1 funda | Total 58.000,00; stock 40→38 y 30→29 (se revierte) |
| B2 | 6 lavarropas con stock 5 | Error 50005, sin pedido, stock igual |
| B3 | Cliente inexistente | Error 50001 |
| C1-C4 | Funciones complementarias | `fn_pedidos_cliente(2)`: pedido 2 → 89.250,00 y 12 → 30.200,00; casos límite sin error (NULL, 0, 0,00, 0 filas) |
| D1-D6 | ABM | Insertar directo vs. procedimiento: iguales; modificar +10 %; eliminar → `ELIMINADO` o `BAJA_LOGICA`; errores 50121, 50102 y 547 (CHECK de precio) |

**Eficiencia (segunda corrida):**

| Prueba | Qué compara | Repeticiones | ms |
|---|---|---|---|
| A | `INSERT` directo en bucle | 2.000 | 55 |
| B | `EXEC usp_producto_insertar` en bucle | 2.000 | 156 |
| C | Un `INSERT ... SELECT` | 2.000 | 300 |
| D | Total con la función escalar `fn_total_pedido` | 240.000 | 11 |
| E | Total con subconsulta `CROSS APPLY` | 240.000 | 57 |

Conclusión: el procedimiento cuesta ~0,05 ms más por alta (validaciones); la función escalar no fue lenta
porque SQL Server 2019+ la expande en línea (*scalar UDF inlining*). Se usan por centralizar reglas y por
seguridad, no por velocidad. C fue más lento probablemente por generar los números con `sys.all_objects`.

### Preguntas típicas
- ¿Por qué `SCOPE_IDENTITY()` y no `@@IDENTITY`? → `@@IDENTITY` devuelve el último identity de la sesión
  **en cualquier ámbito**, y el trigger de pedido inserta en `auditoria`: devolvería el id de auditoría.
- ¿Para qué `UPDLOCK, HOLDLOCK`? → Bloquea las filas de producto desde que se verifica el stock hasta el
  COMMIT, para que dos ventas simultáneas no vendan la misma última unidad.
- ¿Por qué el precio se guarda en el detalle si hay una función que lo calcula? → RN.03: el precio de la
  venta se congela; si mañana cambia el precio de lista, el pedido viejo no cambia.
- ¿Por qué `@tran_propia`? → Para que funcione solo o dentro de la transacción de otro (prueba T5).
- ¿Por qué tipo tabla y no un parámetro por producto? → Una venta tiene N productos; se valida y se
  inserta todo por conjuntos, sin cursores.

---

## 3. Tema 2 — Manejo de transacciones

### Teoría
- **Transacción:** unidad lógica de trabajo; o se aplica entera o no se aplica nada.
- **ACID:** Atomicidad (todo o nada), Consistencia (de un estado válido a otro válido), Aislamiento (las
  transacciones concurrentes no se ven a medias), Durabilidad (lo confirmado sobrevive a una caída,
  gracias al log de transacciones).
- **Sentencias:** `BEGIN TRANSACTION`, `COMMIT`, `ROLLBACK`, `SAVE TRANSACTION nombre` (punto de guardado).
- **Variables:** `@@TRANCOUNT` (nivel de anidamiento), `XACT_STATE()` (1 = activa y confirmable,
  -1 = condenada: solo se puede hacer ROLLBACK, 0 = no hay transacción), `@@ROWCOUNT` (filas afectadas).
- **`SET XACT_ABORT ON`:** ante un error en tiempo de ejecución, SQL Server revierte la transacción
  completa. Sin él, algunos errores solo cancelan la sentencia y la transacción sigue abierta.
- **Modo autocommit:** sin `BEGIN TRAN`, cada sentencia es su propia transacción (por eso T10 deja un
  pedido huérfano).

**Anidamiento en SQL Server (clave para el examen):**

| Acción | Efecto en `@@TRANCOUNT` | Qué pasa realmente |
|---|---|---|
| `BEGIN TRAN` | +1 | Solo el primero abre una transacción real |
| `COMMIT` interno | −1 | No confirma nada; solo baja el contador |
| `COMMIT` cuando el contador llega a 0 | 0 | Recién ahí se confirma todo |
| `ROLLBACK` (sin nombre), en cualquier nivel | queda en 0 | Deshace **todo**, también lo "externo" |
| `ROLLBACK TRAN punto` | no cambia | Deshace solo lo posterior al `SAVE TRANSACTION` |

### Código: punto de guardado (T4)

```sql
BEGIN TRY
    BEGIN TRANSACTION;
        INSERT INTO pedido (estado, estado_pago, calle, numero, ciudad, provincia, cod_postal,
                            cod_cliente, cod_metodo_pago)
        SELECT 'pendiente', 'pendiente', dir.calle, dir.numero, loc.nombre, prov.nombre, dir.cod_postal,
               c.cod_cliente, 1
        FROM cliente c
        INNER JOIN direccion dir ON dir.cod_cliente = c.cod_cliente AND dir.principal = 1
        INNER JOIN localidad loc ON loc.cod_localidad = dir.cod_localidad
        INNER JOIN provincia prov ON prov.cod_provincia = loc.cod_provincia
        WHERE c.cod_cliente = 1;

        DECLARE @cod4 INT = SCOPE_IDENTITY();

        SAVE TRANSACTION punto_detalle;

        INSERT INTO detalle_pedido (cod_pedido, cod_producto, item, cantidad,
                                    precio_unitario_venta, alicuota_iva, iva_monto)
        VALUES (@cod4, 2, 1, 1, 25000.00, 21.00, 4338.84);

        ROLLBACK TRANSACTION punto_detalle;   -- desaparece el detalle, el pedido sigue

    ROLLBACK TRANSACTION;                     -- se revierte todo para no dejar datos
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    SELECT ERROR_NUMBER() AS error, ERROR_MESSAGE() AS mensaje;
END CATCH;
```

### Código: transacción del llamador (T5)

```sql
DECLARE @stock_antes5 INT = (SELECT stock FROM producto WHERE cod_producto = 2);   -- 40
BEGIN TRANSACTION;
    DECLARE @items5 dbo.tipo_items_pedido, @nuevo5 INT;
    INSERT INTO @items5 (cod_producto, cantidad) VALUES (2, 1);
    EXEC dbo.sp_registrar_venta_completa @cod_cliente = 1, @cod_metodo_pago = 1,
         @ref_transaccion = 'TX-T5-EXTERNA', @items = @items5, @cod_pedido = @nuevo5 OUTPUT;
    -- acá @@TRANCOUNT = 1 y el stock es 39: el procedimiento NO confirmó por su cuenta
ROLLBACK TRANSACTION;
-- stock vuelve a 40
```

### Código: cancelación de pedido (T6, RN.30)

```sql
-- Errores: 50008 inexistente · 50009 ya cancelado · 50010 tiene factura · 50011 despachado/entregado
CREATE OR ALTER PROCEDURE dbo.sp_cancelar_pedido
    @cod_pedido INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @tran_propia BIT = CASE WHEN @@TRANCOUNT = 0 THEN 1 ELSE 0 END;
    DECLARE @estado VARCHAR(20), @estado_envio VARCHAR(20);

    BEGIN TRY
        IF @tran_propia = 1 BEGIN TRANSACTION;

        SELECT @estado = estado, @estado_envio = estado_envio
        FROM dbo.pedido WITH (UPDLOCK, HOLDLOCK)
        WHERE cod_pedido = @cod_pedido;

        IF @estado IS NULL          THROW 50008, 'Pedido inexistente.', 1;
        IF @estado = 'cancelado'    THROW 50009, 'El pedido ya está cancelado.', 1;
        IF EXISTS (SELECT 1 FROM dbo.factura WHERE cod_pedido = @cod_pedido)
            THROW 50010, 'El pedido ya tiene factura: no se puede cancelar.', 1;
        IF @estado_envio IN ('despachado', 'entregado')
            THROW 50011, 'El pedido ya fue despachado o entregado: no se puede cancelar.', 1;

        -- Solo un pedido confirmado descontó stock: se repone en la MISMA transacción
        IF @estado = 'confirmado'
            UPDATE p SET p.stock = p.stock + d.cantidad
            FROM dbo.producto p
            INNER JOIN dbo.detalle_pedido d ON d.cod_producto = p.cod_producto
            WHERE d.cod_pedido = @cod_pedido;

        UPDATE dbo.pedido SET estado = 'cancelado', estado_envio = NULL
        WHERE cod_pedido = @cod_pedido;

        IF @tran_propia = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @tran_propia = 1 AND @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
```

### Código: contraste sin transacción (T10)

```sql
SET XACT_ABORT OFF;
BEGIN TRY
    INSERT INTO dbo.pedido (...) SELECT ...;           -- se confirma solo (autocommit)
    SET @cod_pedido = SCOPE_IDENTITY();
    THROW 50299, 'Error provocado intencionalmente despues del INSERT.', 1;
END TRY
BEGIN CATCH
    PRINT 'T10: error SIN transaccion. Motivo: ' + ERROR_MESSAGE();
END CATCH;
-- Resultado: pedidos 12 -> 13 con un pedido SIN detalle (huérfano). Después se borra a mano.
```

### Código: anidamiento (T11, T12, T13)

```sql
-- T11: COMMIT interno + ROLLBACK externo  →  contador 0,1,2,1,0 y la fila NO queda
BEGIN TRANSACTION externa;
    BEGIN TRANSACTION interna;
        INSERT INTO dbo.categoria (nombre) VALUES ('DEMO-ANIDADA-1');
    COMMIT TRANSACTION interna;      -- @@TRANCOUNT = 1: todavía no es permanente
ROLLBACK TRANSACTION externa;        -- deshace también lo "confirmado" adentro

-- T12: ROLLBACK en la interna deshace TODO y deja el contador en 0
BEGIN TRANSACTION;
    BEGIN TRANSACTION;
        INSERT INTO dbo.categoria (nombre) VALUES ('DEMO-ANIDADA-2');
    ROLLBACK TRANSACTION;            -- @@TRANCOUNT = 0, no queda nada

-- T13: punto de recuperación → se deshace una parte y se confirma el resto
BEGIN TRANSACTION;
    INSERT INTO dbo.categoria (nombre) VALUES ('DEMO-SP-A');
    SAVE TRANSACTION punto_1;
    INSERT INTO dbo.categoria (nombre) VALUES ('DEMO-SP-B');
    ROLLBACK TRANSACTION punto_1;    -- solo se va DEMO-SP-B; @@TRANCOUNT sigue en 1
COMMIT TRANSACTION;                  -- queda solo DEMO-SP-A
```

### Código: la otra estrategia — `usp_confirmar_compra` (RN.20)

```sql
-- XACT_ABORT OFF + punto de guardado: si la llaman dentro de otra transacción y falla,
-- deshace SOLO su parte y el llamador puede seguir.
CREATE OR ALTER PROCEDURE dbo.usp_confirmar_compra
    @cod_compra INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT OFF;
    DECLARE @tran_propia BIT = 0;

    BEGIN TRY
        IF @@TRANCOUNT = 0
        BEGIN
            BEGIN TRANSACTION;
            SET @tran_propia = 1;
        END
        ELSE
            SAVE TRANSACTION sv_confirmar_compra;

        UPDATE dbo.compra SET estado = 'recibida'
        WHERE cod_compra = @cod_compra AND estado = 'pendiente';

        IF @@ROWCOUNT = 0
            THROW 50221, 'La compra no existe o no esta en estado pendiente.', 1;

        UPDATE p SET p.stock = p.stock + dc.cantidad
        FROM dbo.producto p
        INNER JOIN dbo.detalle_compra dc ON dc.cod_producto = p.cod_producto
        WHERE dc.cod_compra = @cod_compra;

        IF @tran_propia = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @tran_propia = 1
        BEGIN
            IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        END
        ELSE IF XACT_STATE() = 1
            ROLLBACK TRANSACTION sv_confirmar_compra;   -- solo su parte
        THROW;
    END CATCH;
END;
```

### Resumen de pruebas

| Prueba | Qué muestra | Resultado |
|---|---|---|
| T1 | Venta con COMMIT | Pedido creado y stock baja |
| T2 | Stock insuficiente | Error 50005, ROLLBACK, nada guardado |
| T3 | Atomicidad con varias sentencias | Pedido + detalle válido + detalle con cantidad 0 (viola `CK_detalle_pedido_cantidad`): el CATCH revierte las tres |
| T4 | `SAVE TRANSACTION` | El detalle desaparece, el pedido sigue |
| T5 | Transacción del llamador | Stock 40 → 39 adentro, 40 tras el ROLLBACK externo |
| T6a-f | Cancelación | Stock vuelve a 40; errores 50008, 50009, 50010 (pedido 1 facturado), 50011 |
| T7-T9 | Transacción explícita sin procedimiento | T7 COMMIT (pedidos 12 → 13, líneas 18 → 19, stock 40 → 39); T8 error 50299 después del primer INSERT → ROLLBACK; T9 stock insuficiente, error 50211 → ROLLBACK (12, 18 y 40 antes y después) |
| T10 | Sin transacción | Pedidos 12 → 13: pedido huérfano |
| T11-T13 | Anidamiento | Ver tabla de arriba |
| T14 | Confirmar compra 9 | pendiente → recibida; producto 1: 12 → 17, producto 9: 15 → 20 (se revierte) |
| T15 | Compras 1 (recibida), 10 (cancelada) e inexistente | Tres errores 50221, `@@TRANCOUNT` = 0 y estados sin cambios |
| T16 | Dentro de una transacción externa: confirma la 9 y después intenta la 10 | La 10 falla y se deshace solo su parte: contador 1, `XACT_STATE()` = 1, compra 9 recibida y stock del producto 1 = 17; tras el ROLLBACK externo, pendiente y 12 |

**Límite honesto:** el aislamiento no se probó con dos sesiones simultáneas; lo cubre el diseño
(`UPDLOCK, HOLDLOCK` en la venta y en la cancelación).

### Preguntas típicas
- ¿SQL Server tiene transacciones anidadas reales? → No. Solo cuenta niveles; el COMMIT interno no
  confirma y cualquier ROLLBACK sin nombre deshace todo.
- ¿Diferencia entre `XACT_ABORT ON` en la venta y el punto de guardado en `usp_confirmar_compra`? → La
  venta es todo o nada (si falla, condena la transacción del llamador). La compra permite que, dentro de
  un proceso mayor, se deshaga solo su parte.
- ¿Qué es `XACT_STATE() = -1`? → Transacción condenada: no se puede confirmar ni volver a un punto;
  solo ROLLBACK completo.
- ¿Por qué la cancelación repone el stock en la misma transacción? → Si se cancela el pedido pero falla
  la reposición, quedaría stock perdido: estado y stock tienen que cambiar juntos (atomicidad).

---

## 4. Tema 3 — Triggers de auditoría

### Teoría
- **Trigger:** código que el motor ejecuta automáticamente ante un evento (INSERT, UPDATE, DELETE).
- **AFTER:** corre después de la sentencia, dentro de la misma transacción; si falla, se revierte todo.
- **INSTEAD OF:** reemplaza a la sentencia; la operación original no ocurre salvo que el trigger la haga.
- **Tablas virtuales:** `inserted` (filas nuevas: INSERT y UPDATE) y `deleted` (filas viejas: DELETE y
  UPDATE). En un UPDATE están las dos.
- **Se dispara una vez por sentencia, no por fila:** un `UPDATE` de 10 filas llega con 10 filas en
  `inserted`. Por eso se escribe **por conjuntos** (INSERT ... SELECT), nunca con variables que asumen
  una sola fila.
- **Auditoría:** registrar quién cambió qué, cuándo y de qué valor a qué valor. Como el trigger corre en
  la misma transacción, la auditoría es transaccional: si el cambio se revierte, la auditoría también.

### Código: la tabla de auditoría (DDL)

```sql
CREATE TABLE auditoria
(
  cod_auditoria INT IDENTITY CONSTRAINT PK_auditoria PRIMARY KEY,
  entidad VARCHAR(50) NOT NULL,
  operacion VARCHAR(10) NOT NULL,
  registro_id INT NOT NULL,
  fecha DATETIME NOT NULL CONSTRAINT DF_auditoria_fecha DEFAULT GETDATE(),
  valor_anterior VARCHAR(255) NULL,
  valor_nuevo VARCHAR(255) NULL,
  cod_usuario INT NOT NULL,              -- el empleado de la aplicación
  usuario_bd VARCHAR(128) NOT NULL CONSTRAINT DF_auditoria_usuario_bd DEFAULT SUSER_SNAME(),  -- el login
  CONSTRAINT FK_auditoria_usuario FOREIGN KEY (cod_usuario) REFERENCES usuario(cod_usuario)
      ON DELETE NO ACTION ON UPDATE CASCADE,
  CONSTRAINT CK_auditoria_operacion CHECK (operacion IN ('INSERT', 'UPDATE', 'DELETE'))
);
```

### Código: trigger de producto (los otros tres son iguales en estructura)

```sql
CREATE OR ALTER TRIGGER dbo.trg_producto_auditoria
ON dbo.producto
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    IF TRIGGER_NESTLEVEL() > 1 RETURN;   -- si lo dispara otro trigger, no se repite

    -- El empleado lo informa la aplicación en la sesión; si no, el usuario 1
    DECLARE @cod_usuario INT = ISNULL(TRY_CAST(SESSION_CONTEXT(N'cod_usuario') AS INT), 1);

    INSERT INTO dbo.auditoria (entidad, operacion, registro_id, valor_anterior, valor_nuevo, cod_usuario)
    SELECT
        'producto',
        CASE WHEN d.cod_producto IS NULL THEN 'INSERT'     -- solo en inserted
             WHEN i.cod_producto IS NULL THEN 'DELETE'     -- solo en deleted
             ELSE 'UPDATE' END,                            -- en las dos
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
       OR i.precio_lista <> d.precio_lista     -- en un UPDATE solo audita si cambió
       OR i.stock        <> d.stock;           -- precio o stock
END;
```

Los otros: `trg_pedido_auditoria` (estado, estado_pago, estado_envio; un cambio de dirección no genera
fila), `trg_compra_auditoria` (estado) y `trg_factura_auditoria` (tipo, número y total; audita
cualquier cambio, sin filtrar columnas).

**Cómo informa la aplicación el empleado:**

```sql
EXEC sys.sp_set_session_context @key = N'cod_usuario', @value = 3;   -- lramirez, DEPOSITO
UPDATE producto SET stock = stock - 1 WHERE cod_producto = 2;
-- auditoria: valor_anterior 'precio_lista=20661.16; stock=40', valor_nuevo '...; stock=39', cod_usuario 3
```

### Código: INSTEAD OF que impide borrar facturas

```sql
CREATE OR ALTER TRIGGER dbo.trg_factura_no_borrar
ON dbo.factura
INSTEAD OF DELETE
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (SELECT 1 FROM deleted)
        THROW 50012, 'Una factura no se puede eliminar: es un comprobante fiscal.', 1;
END;
```

### Pruebas

| Prueba | Caso | Resultado |
|---|---|---|
| A0 | Triggers creados | 4 triggers AFTER habilitados |
| A1 | UPDATE de stock (usuario 3) | Stock 40 → 39, una fila con antes y después |
| A2 | INSERT y DELETE de un producto (usuario 9) | 2 filas: en INSERT `valor_anterior` NULL, en DELETE `valor_nuevo` NULL |
| A3 | Venta dentro de una transacción con ROLLBACK | Adentro 2 filas (pedido INSERT y producto UPDATE); tras el ROLLBACK, auditoría vuelve a 10 y stock 40 → **la auditoría es transaccional** |
| A4 | `cod_usuario` = 999 (no existe) | Error 547 (FK): **si la auditoría falla, el cambio no se aplica**; stock 40 |
| A5 | Un UPDATE sobre los 10 productos | 10 filas de auditoría en una sola sentencia → **set-based** |
| A6 | `usuario_bd` | Igual a `SUSER_SNAME()` de la sesión |
| A7 | Borrar la factura 1 | Error 50012; facturas 10/10; auditoría 10/10 |

**Límites:** un administrador puede deshabilitar el trigger (`DISABLE TRIGGER`); si la aplicación no
informa el empleado, queda el usuario 1 por defecto (por eso existe también `usuario_bd`, que no depende
de la aplicación).

### Preguntas típicas
- ¿Por qué FULL OUTER JOIN? → Un solo trigger para los tres eventos: si la fila solo está en `inserted`
  es INSERT, si solo está en `deleted` es DELETE, si está en las dos es UPDATE.
- ¿Por qué AFTER y no INSTEAD OF para auditar? → Queremos que la operación ocurra y registrarla; INSTEAD
  OF se usa cuando hay que impedir o reemplazar la operación (facturas).
- ¿Qué pasa si el trigger falla? → Como corre en la misma transacción, se revierte también el cambio (A4).
- ¿Por qué `TRIGGER_NESTLEVEL() > 1`? → Para no auditar dos veces si un trigger dispara a otro.
- ¿Por qué dos usuarios? → `cod_usuario` es el empleado de negocio (la app usa un login compartido);
  `usuario_bd` es el login real de la base, que no se puede falsear desde la sesión.

---

## 5. Tema 4 — Manejo de permisos a nivel de usuarios

### Teoría
- **Login vs. usuario:** el **login** es del servidor (autentica: quién sos). El **usuario** es de la
  base y se mapea a un login (autoriza: qué podés hacer en esa base).
- **Modo de autenticación:** solo Windows o **mixto** (Windows + SQL Server). Para conectarse con
  usuario y contraseña de SQL hace falta el mixto. `SERVERPROPERTY('IsIntegratedSecurityOnly')`: 1 = solo
  Windows, 0 = mixto.
- **GRANT** da un permiso, **DENY** lo prohíbe explícitamente (**gana sobre cualquier GRANT**, incluso el
  heredado de un rol), **REVOKE** quita un GRANT o DENY previo (vuelve a "sin definir").
- **Roles:** fijos (`db_owner` = todo en la base, `db_datareader` = leer todas las tablas,
  `db_datawriter`...) y roles propios (`CREATE ROLE`). Se da permiso al rol y se agregan miembros.
- **Mínimo privilegio:** cada usuario tiene solo los permisos que necesita.
- **Encadenamiento de propiedad (ownership chaining):** si un procedimiento y las tablas que usa tienen
  el **mismo dueño** (`dbo`), SQL Server solo verifica el permiso `EXECUTE` sobre el procedimiento y no
  vuelve a verificar las tablas. Así un usuario sin permiso de escritura puede vender **solo a través del
  procedimiento**, con sus validaciones.
- **Errores:** 229 = permiso denegado sobre un objeto; 230 = permiso denegado sobre una **columna**.
- **`EXECUTE AS LOGIN/USER` ... `REVERT`:** cambia temporalmente el contexto de seguridad para probar
  permisos sin abrir otra conexión.

### Código: usuarios y roles

```sql
-- Logins (servidor). Contraseñas solo de demostración.
CREATE LOGIN smarthome_admin   WITH PASSWORD = 'Demo.Admin.2026!';
CREATE LOGIN smarthome_lectura WITH PASSWORD = 'Demo.Lectura.2026!';
CREATE LOGIN smarthome_con_rol WITH PASSWORD = 'Demo.ConRol.2026!';
CREATE LOGIN smarthome_sin_rol WITH PASSWORD = 'Demo.SinRol.2026!';

USE smarthome_store;
-- Usuarios (base) mapeados a los logins
CREATE USER smarthome_admin   FOR LOGIN smarthome_admin;
CREATE USER smarthome_lectura FOR LOGIN smarthome_lectura;

ALTER ROLE db_owner      ADD MEMBER smarthome_admin;     -- administrador
ALTER ROLE db_datareader ADD MEMBER smarthome_lectura;   -- solo lectura

-- El de solo lectura puede vender, pero SOLO con el procedimiento
GRANT EXECUTE ON dbo.sp_registrar_venta_completa TO smarthome_lectura;
GRANT EXECUTE ON TYPE::dbo.tipo_items_pedido TO smarthome_lectura;   -- necesario por el tipo tabla

-- Rol propio: solo lee productos
CREATE ROLE rol_lectura_producto;
GRANT SELECT ON dbo.producto TO rol_lectura_producto;
CREATE USER smarthome_con_rol FOR LOGIN smarthome_con_rol;
CREATE USER smarthome_sin_rol FOR LOGIN smarthome_sin_rol;
ALTER ROLE rol_lectura_producto ADD MEMBER smarthome_con_rol;
```

### Código: pruebas con EXECUTE AS

```sql
-- U3. INSERT directo con solo lectura → error 229
EXECUTE AS LOGIN = 'smarthome_lectura';
BEGIN TRY
    INSERT INTO dbo.pedido (calle, numero, ciudad, provincia, cod_postal, cod_cliente, cod_metodo_pago)
    VALUES ('Prueba', '1', 'Corrientes', 'CORRIENTES', '3400', 1, 1);
END TRY
BEGIN CATCH
    SELECT 'U3' AS prueba, ERROR_NUMBER() AS error, ERROR_MESSAGE() AS mensaje;   -- 229
END CATCH;
REVERT;

-- U4. El MISMO usuario vende con el procedimiento → funciona (encadenamiento de propiedad)
BEGIN TRANSACTION;
EXECUTE AS LOGIN = 'smarthome_lectura';
DECLARE @items dbo.tipo_items_pedido, @nuevo INT;
INSERT INTO @items (cod_producto, cantidad) VALUES (2, 1);
EXEC dbo.sp_registrar_venta_completa @cod_cliente = 1, @cod_metodo_pago = 1,
     @ref_transaccion = 'TX-U4', @items = @items, @cod_pedido = @nuevo OUTPUT;
SELECT cod_producto, stock FROM dbo.producto WHERE cod_producto = 2;   -- 39
REVERT;
ROLLBACK TRANSACTION;
```

### Código: el problema de negocio — DENY sobre una columna

Si la aplicación pudiera hacer `UPDATE pedido SET estado = 'cancelado'`, el pedido quedaría cancelado
**sin reponer el stock** (rompe RN.30). Solución: prohibir esa columna y obligar a usar el procedimiento.

```sql
CREATE ROLE rol_aplicacion;
CREATE USER usuario_aplicacion WITHOUT LOGIN;
ALTER ROLE rol_aplicacion ADD MEMBER usuario_aplicacion;

GRANT SELECT ON dbo.pedido TO rol_aplicacion;
GRANT UPDATE ON dbo.pedido (estado_envio, fecha_envio, transportista, fecha_entrega,
                            nro_seguimiento, cod_usuario) TO rol_aplicacion;   -- datos de envío sí
DENY  UPDATE ON dbo.pedido (estado) TO rol_aplicacion;                        -- el estado NO
GRANT EXECUTE ON dbo.sp_registrar_venta_completa TO rol_aplicacion;
GRANT EXECUTE ON dbo.sp_cancelar_pedido TO rol_aplicacion;
GRANT EXECUTE ON TYPE::dbo.tipo_items_pedido TO rol_aplicacion;

-- S1. Cambiar el estado directo → error 230 (columna)
EXECUTE AS USER = 'usuario_aplicacion';
BEGIN TRY
    UPDATE dbo.pedido SET estado = 'cancelado' WHERE cod_pedido = 10;
END TRY
BEGIN CATCH
    SELECT 'S1' AS prueba, ERROR_NUMBER() AS error, ERROR_MESSAGE() AS mensaje;   -- 230
END CATCH;
REVERT;
```

### Pruebas

| Prueba | Caso | Resultado |
|---|---|---|
| U1 | INSERT con `smarthome_admin` | 1 fila (se revierte) |
| U2 | SELECT con `smarthome_lectura` | Lee los 12 pedidos |
| U3 | INSERT con `smarthome_lectura` | Error 229 |
| U4 | Venta con el procedimiento y `smarthome_lectura` | Pedido creado, stock 40 → 39 (se revierte) |
| U5 | UPDATE con `smarthome_lectura` | Error 229 |
| R1 | `smarthome_con_rol` lee producto | 10 productos |
| R2 | `smarthome_sin_rol` lee producto | Error 229 |
| R3 | `smarthome_con_rol` lee pedido | Error 229 (el rol solo alcanza a producto) |
| S1 | `usuario_aplicacion` cambia `estado` | Error 230 |
| S2 | `usuario_aplicacion` cambia transportista | 1 fila (permitido) |
| S3 | Venta y cancelación con procedimientos | Pedido cancelado y stock 40 |
| S4 | `usuario_aplicacion` modifica producto directo | Error 229 |

También se repitió con inicio de sesión real (`sqlcmd -U`) tras pasar el servidor a modo mixto; con
contraseña incorrecta, el login es rechazado.

**Límites:** DENY no alcanza a `dbo` ni a `sysadmin`; las contraseñas son de demostración.

### Preguntas típicas
- ¿Por qué el de solo lectura puede insertar con el procedimiento? → Encadenamiento de propiedad: mismo
  dueño (`dbo`) en procedimiento y tablas, solo se verifica `EXECUTE`.
- ¿DENY o simplemente no dar GRANT? → Sin GRANT, un permiso heredado de otro rol podría habilitarlo;
  DENY gana siempre.
- ¿Diferencia entre 229 y 230? → 229 objeto (tabla), 230 columna.
- ¿Por qué `GRANT EXECUTE ON TYPE`? → El procedimiento recibe un tipo tabla; sin permiso sobre el tipo,
  no se puede declarar la variable.
- ¿Qué hace `EXECUTE AS LOGIN` vs `EXECUTE AS USER`? → El primero suplanta el login (servidor y base);
  el segundo solo el usuario de la base (se usó para el usuario `WITHOUT LOGIN`).

---

## 6. Tema 5 — Optimización de consultas a través de índices

### Teoría
- **Índice:** estructura (árbol B+) que permite encontrar filas sin recorrer toda la tabla, como el
  índice de un libro.
- **Heap:** tabla sin índice agrupado; las filas no tienen orden.
- **Índice agrupado (clustered):** **es** la tabla, ordenada por la clave; las hojas contienen las filas
  completas. Uno solo por tabla. La PK crea uno por defecto.
- **Índice no agrupado (nonclustered):** estructura aparte con la clave y un puntero a la fila. Puede
  haber muchos.
- **`INCLUDE`:** agrega columnas a las hojas de un no agrupado sin que formen parte de la clave.
- **Índice cubriente:** contiene todas las columnas que pide la consulta → no hace falta ir a la tabla.
- **Operadores del plan:** `Table Scan` (recorre el heap entero), `Clustered Index Seek` (va directo al
  rango en el agrupado), `Index Seek` (va directo al rango en un no agrupado).
- **Costo de los índices:** ocupan espacio y hacen más lentas las escrituras (cada INSERT/UPDATE/DELETE
  tiene que mantenerlos).
- **Lecturas lógicas:** páginas de 8 KB leídas de memoria. Se repiten exactas en cada corrida; el tiempo
  depende de la PC. Por eso se mide con `SET STATISTICS IO ON`.

### Por qué una tabla auxiliar
Los datos reales tienen 12 pedidos: ningún índice mostraría diferencia. Además `pedido` ya tiene índice
agrupado en la PK y su trigger generaría un millón de filas de auditoría. Se creó `venta_historica` sin
índices y con **un millón de ventas** de 2021 a 2026, que se borra al final.

```sql
CREATE TABLE dbo.venta_historica
(
    cod_venta    INT           NOT NULL,
    fecha_venta  DATETIME      NOT NULL,
    cod_cliente  INT           NOT NULL,
    cod_producto INT           NOT NULL,
    cantidad     INT           NOT NULL,
    importe      DECIMAL(10,2) NOT NULL,
    observacion  VARCHAR(200)  NOT NULL
);

-- Carga determinística de 1.000.000 de filas (siempre los mismos datos)
WITH numeros AS
(
    SELECT TOP (1000000) CAST(ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS BIGINT) AS i
    FROM sys.all_objects a CROSS JOIN sys.all_objects b
)
INSERT INTO dbo.venta_historica WITH (TABLOCK)
    (cod_venta, fecha_venta, cod_cliente, cod_producto, cantidad, importe, observacion)
SELECT i,
       DATEADD(SECOND, CAST((i * 2654435761) % 189216000 AS INT), '2021-01-01'),   -- 6 años
       1 + i % 10, 1 + (i * 7) % 10, 1 + i % 5, 1000 + (i * 13) % 100000,
       'Venta histórica de prueba para la comparación de índices ' + REPLICATE('-', 100)
FROM numeros;
```

### Código: los tres escenarios

```sql
SET STATISTICS IO, TIME ON;

-- La misma consulta en los tres escenarios: ventas de enero de 2025 (14.158 filas)
SELECT cod_venta, fecha_venta, importe
FROM dbo.venta_historica
WHERE fecha_venta >= '2025-01-01' AND fecha_venta < '2025-02-01';

-- Escenario 1: sin índice (heap) → Table Scan, 25.642 lecturas lógicas

-- Escenario 2: índice agrupado → Clustered Index Seek, 367 lecturas
CREATE CLUSTERED INDEX IX_venta_historica_fecha ON dbo.venta_historica (fecha_venta);

-- Escenario 3: no agrupado cubriente → Index Seek, 67 lecturas
DROP INDEX IX_venta_historica_fecha ON dbo.venta_historica;
CREATE NONCLUSTERED INDEX IX_venta_historica_fecha_cubre
    ON dbo.venta_historica (fecha_venta) INCLUDE (cod_venta, importe);

-- Antes de cada medición, en frío:
CHECKPOINT;
DBCC DROPCLEANBUFFERS WITH NO_INFOMSGS;   -- vacía la caché de datos: solo en un equipo de pruebas
```

### Resultados

| Escenario | Operador | Filas leídas | Lecturas lógicas | Costo estimado | Frío | Caliente |
|---|---|---|---|---|---|---|
| 1. Sin índice | Table Scan | 1.000.000 | **25.642** | 20,10 | 178 ms | 142 ms |
| 2. Agrupado | Clustered Index Seek | 14.158 | **367** | 0,29 | 44 ms | 32 ms |
| 3. No agrupado + INCLUDE | Index Seek | 14.158 | **67** | 0,06 | 42 ms | 29 ms |

| Estructura | Tamaño | Creación |
|---|---|---|
| Heap | 200 MB | — |
| Agrupado (reemplaza al heap) | 200 MB | 2.022 ms |
| No agrupado con INCLUDE (se suma) | 33 MB | 634 ms |

- Agrupado: **−98,6 %** de lecturas (las filas quedan ordenadas por fecha, el rango está contiguo).
- Cubriente: **−99,7 %**: sus hojas solo tienen 3 columnas (fecha, cod_venta, importe), así entran
  muchas más filas por página que en el agrupado, que guarda la fila entera (incluida `observacion`,
  de ~160 caracteres).
- Entre 2 y 3 el tiempo casi no cambia (32 vs 29 ms) porque la mayor parte se va en devolver las filas.

**Diferencia con la consigna:** pedía un agrupado con INCLUDE, pero SQL Server no lo permite (el
agrupado ya contiene todas las columnas). Por eso el escenario 3 es no agrupado con INCLUDE.

**Para el modelo real:** con 12 pedidos no se nota; si crece, convendría un no agrupado sobre
`pedido.fecha_pedido` (el agrupado ya lo usa la PK).

**Evidencias:** los tres planes reales `.sqlplan` en `docs/etapa-05/optimizacion_indices/evidencias/`
(se abren en SSMS; en SSMS, Ctrl+M antes de ejecutar muestra el plan real).

### Preguntas típicas
- ¿Por qué el cubriente lee menos que el agrupado si los dos hacen Seek? → Por el tamaño de las hojas:
  el agrupado guarda la fila completa, el cubriente solo 3 columnas.
- ¿Por qué no poner índices en todo? → Espacio y escrituras más lentas; el cubriente solo sirve para
  esta consulta: si se pide otra columna, tiene que ir a la tabla (Key Lookup / RID Lookup).
- ¿Por qué lecturas lógicas y no tiempo? → Son exactas y repetibles; el tiempo depende del equipo, la
  caché y la carga.
- ¿Por qué el rango `>= '2025-01-01' AND < '2025-02-01'` y no `MONTH(fecha_venta) = 1`? → Aplicar una
  función a la columna impide el Seek (la condición deja de ser *sargable*) y fuerza un Scan.
- ¿Qué hace `DBCC DROPCLEANBUFFERS`? → Vacía la caché de datos para medir en frío; nunca en producción.

---

## 7. Números para memorizar

| Qué | Valor |
|---|---|
| Lecturas índices | **25.642 → 367 → 67** |
| Filas de la consulta de índices | 14.158 de 1.000.000 |
| Permisos | **229** objeto · **230** columna |
| Venta | 50001-50007 (50005 = stock insuficiente) |
| Cancelación | 50008-50011 |
| Factura no se borra | **50012** |
| ABM producto | 50101-50104, 50111-50114, 50121 |
| Confirmar compra | 50221 |
| FK violada (A4) | 547 |
| Base | 22 tablas · 30 RN · 52 pruebas de validación · 12 pedidos · stock del producto 2 = 40 |

## 8. Estructura sugerida para los 5-7 minutos

1. **Apertura (20 s):** qué tema y en qué parte del proyecto se usa.
2. **Concepto (1:30):** definición y teoría clave (tablas de arriba).
3. **Aplicación (2:00):** qué se hizo en SmartHome Store y por qué (regla de negocio que resuelve).
4. **Demostración (1:30):** una prueba en SSMS con su resultado (número concreto).
5. **Límites y cierre (0:40):** qué no cubre y la idea principal.
