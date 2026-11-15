# Aportes de Enzo Mauricio Antonio Benitez (GitHub: Mauriciobntz)

> Para responder "¿qué hiciste vos?" en la defensa. Las líneas son las del repo del proyecto
> (`MercedesSilFer/proyecto-bd1-equipo_37`, rama `main`). Commits: 41 en el historial.

## Cómo contarlo en un minuto

"En la Etapa V hice dos temas completos, **índices** y **seguridad**, y la **cancelación de pedidos**
dentro de transacciones, con su permiso para que la aplicación no pueda cancelar a mano. Sumé al tema
de triggers el que **impide borrar facturas** y el **usuario de la base en la auditoría**. Antes, en la
Etapa IV, hice la **consulta del comprobante de factura**. A lo largo del proyecto **normalicé la
ubicación** (provincia, localidad, varias direcciones con una principal) y mantuve alineados el DER,
el modelo, el DDL, la documentación y el README."

---

## 1. Tema 5 — Optimización con índices (completo)

- **Archivos:** `sql/tecnico/indices/01_carga_masiva.sql`, `02_pruebas_indices.sql`, `03_limpieza.sql`;
  `docs/etapa-05/optimizacion_indices/investigacion.md`; planes en `.../evidencias/*.sqlplan`.
- **Commit:** `aa902c0` Agrega el tema de índices.

```sql
-- 01_carga_masiva.sql:19 y 35  tabla auxiliar con un millón de ventas
CREATE TABLE dbo.venta_historica (cod_venta INT, fecha_venta DATETIME, ..., importe DECIMAL(10,2), ...);
INSERT INTO dbo.venta_historica WITH (TABLOCK) (...)
SELECT i, DATEADD(SECOND, CAST((i * 2654435761) % 189216000 AS INT), '2021-01-01'), ...
FROM (SELECT TOP (1000000) CAST(ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS BIGINT) AS i
      FROM sys.all_objects a CROSS JOIN sys.all_objects b) AS numeros;

-- 02_pruebas_indices.sql:34 y 49
CREATE CLUSTERED INDEX IX_venta_historica_fecha ON dbo.venta_historica (fecha_venta);
CREATE NONCLUSTERED INDEX IX_venta_historica_fecha_cubre
    ON dbo.venta_historica (fecha_venta) INCLUDE (cod_venta, importe);
```

| Escenario | Plan | Lecturas lógicas |
|---|---|---|
| Sin índice (heap) | Table Scan | 25.642 |
| Agrupado | Clustered Index Seek | 367 |
| No agrupado con INCLUDE | Index Seek | 67 |

**Decisiones que tomé y cómo las justifico:**
- **Tabla aparte, no `pedido`:** `pedido` ya tiene agrupado en la PK y su trigger generaría un millón de filas de auditoría.
- **No agrupado con INCLUDE en vez de "agrupado con INCLUDE":** SQL Server no lo permite; el agrupado ya tiene todas las columnas.
- **Medí lecturas lógicas, no solo tiempo:** el tiempo depende del equipo y de la memoria.
- **Datos deterministas** (calculados con el número de fila): la medición se puede repetir y da lo mismo.

---

## 2. Tema 4 — Permisos a nivel de usuarios (completo)

- **Archivos:** `sql/tecnico/seguridad/01_permisos_estado_pedido.sql`, `02_usuarios_y_roles.sql`,
  `99_limpieza_usuarios.sql`; `docs/etapa-05/seguridad/investigacion.md`.
- **Commits:** `0a9e299` tema de seguridad · `24a44d6` impide cambiar el estado del pedido sin los procedimientos.

```sql
-- 01_permisos_estado_pedido.sql:24-29
GRANT SELECT ON dbo.pedido TO rol_aplicacion;
GRANT UPDATE ON dbo.pedido (estado_envio, fecha_envio, transportista,
                            fecha_entrega, nro_seguimiento, cod_usuario) TO rol_aplicacion;
DENY  UPDATE ON dbo.pedido (estado) TO rol_aplicacion;     -- no puede cancelar "a mano"
GRANT EXECUTE ON dbo.sp_registrar_venta_completa TO rol_aplicacion;
GRANT EXECUTE ON dbo.sp_cancelar_pedido          TO rol_aplicacion;
```

| Prueba | Resultado |
|---|---|
| S1 `UPDATE pedido SET estado` | error **230** (permiso de columna) |
| S3 vender y cancelar con procedimientos | funciona; stock vuelve a 40 |
| U3/U5 usuario `db_datareader` modifica | error **229** |
| U4 el mismo usuario vende con el procedimiento | funciona (**encadenamiento de propiedad**) |
| R1-R3 rol propio | lee producto; sin rol o en otra tabla, 229 |

**Por qué lo hice así:** cambiar el estado a mano no repone el stock. Con el DENY, la aplicación solo
puede cancelar con `sp_cancelar_pedido`. Límite que reconozco: DENY no alcanza a dbo ni sysadmin.
Las pruebas con login real requieren el servidor en **modo mixto**.

---

## 3. Cancelación de pedidos (Tema 2, prueba T6)

- **Archivo:** `docs/etapa-05/transacciones/scripts.sql:244-415` · **Regla:** RN.30 · **Decisión 17**.
- **Commit:** `b0064da` Agrega la cancelación de pedidos con reposición de stock.

```sql
-- transacciones/scripts.sql:257
CREATE OR ALTER PROCEDURE dbo.sp_cancelar_pedido @cod_pedido INT AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    DECLARE @tran_propia BIT = CASE WHEN @@TRANCOUNT = 0 THEN 1 ELSE 0 END;
    BEGIN TRY
        IF @tran_propia = 1 BEGIN TRANSACTION;
        SELECT @estado = estado, @estado_envio = estado_envio
        FROM dbo.pedido WITH (UPDLOCK, HOLDLOCK) WHERE cod_pedido = @cod_pedido;
        IF @estado IS NULL          THROW 50008, 'Pedido inexistente.', 1;
        IF @estado = 'cancelado'    THROW 50009, 'El pedido ya está cancelado.', 1;
        IF EXISTS (SELECT 1 FROM dbo.factura WHERE cod_pedido = @cod_pedido)
                                    THROW 50010, 'El pedido ya tiene factura...', 1;
        IF @estado_envio IN ('despachado', 'entregado')
                                    THROW 50011, 'El pedido ya fue despachado...', 1;
        IF @estado = 'confirmado'   -- solo un confirmado descontó stock
            UPDATE p SET p.stock = p.stock + d.cantidad
            FROM dbo.producto p INNER JOIN dbo.detalle_pedido d ON d.cod_producto = p.cod_producto
            WHERE d.cod_pedido = @cod_pedido;
        UPDATE dbo.pedido SET estado = 'cancelado', estado_envio = NULL WHERE cod_pedido = @cod_pedido;
        IF @tran_propia = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @tran_propia = 1 AND @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
```

**Pruebas T6a-T6f:** confirmado → stock 40→39→40; pendiente → no toca stock; errores 50008 a 50011.
**Por qué transacción:** si se repone el stock y falla el cambio de estado, quedaría stock de más.

---

## 4. Agregados al Tema 3 (triggers de auditoría)

- **Commits:** `4f4761a` usuario de la base en la auditoría · `40b6f58` trigger que impide borrar facturas.

```sql
-- crear_bd.sql:214  la columna se completa sola, sin tocar los triggers
usuario_bd VARCHAR(128) NOT NULL CONSTRAINT DF_auditoria_usuario_bd DEFAULT SUSER_SNAME(),

-- triggers_auditoria/scripts.sql:168
CREATE OR ALTER TRIGGER dbo.trg_factura_no_borrar ON dbo.factura INSTEAD OF DELETE AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (SELECT 1 FROM deleted)
        THROW 50012, 'Una factura no se puede eliminar: es un comprobante fiscal.', 1;
END;
```

- **Pruebas A6** (línea 357: `usuario_bd` = login) y **A7** (línea 379: error 50012, la factura sigue).
- **Por qué dos usuarios:** `cod_usuario` es el empleado que informa la aplicación; `usuario_bd`, el login de SQL Server.

---

## 5. Normalización de la ubicación y dirección principal (Etapas II y III)

- **Commits:** `d9c03d9` normaliza ubicación y permite varias direcciones · `e918da7` dirección principal con trigger · `adfca96` DER final.
- **Problema:** ciudad y provincia como texto en `cliente` y `proveedor` = **dependencia transitiva** (3FN).
- **Solución:** catálogos `provincia` y `localidad`, tabla `direccion` con un solo titular, una principal.

```sql
-- crear_bd.sql:116, 119 y 124
CONSTRAINT CK_direccion_titular CHECK (
  (cod_cliente IS NOT NULL AND cod_proveedor IS NULL) OR
  (cod_cliente IS NULL AND cod_proveedor IS NOT NULL))
CREATE UNIQUE INDEX UQ_direccion_principal_cliente
  ON direccion(cod_cliente) WHERE principal = 1 AND cod_cliente IS NOT NULL;   -- índice filtrado
CREATE TRIGGER trg_direccion_principal ...   -- si queda sin principal, marca la más reciente (RN.04)
```

- **Por qué la dirección se copia en el pedido** (decisión 7): es una foto de la venta; si el cliente se muda, el pedido no cambia.
- **Cliente sin dirección:** permitido al registrarse (RN.29); la necesita para comprar (RN.01).

---

## 6. Etapa IV — Consulta del comprobante de factura

- **Archivos:** `sql/consultas/factura_comprobante.sql`, `docs/etapa-04/factura-comprobante.md`, CU-14.
- **Commits:** `32bd587` y `948b785`.

```sql
-- factura_comprobante.sql:20  número de comprobante 0001-00000004
RIGHT('0000' + CAST(f.punto_venta AS VARCHAR(4)), 4) + '-' +
RIGHT('00000000' + CAST(f.numero AS VARCHAR(8)), 8) AS nro_comprobante,
-- control: recalcula el total desde el detalle y debe coincidir con f.total
(SELECT SUM(dp.cantidad * dp.precio_unitario_venta)
 FROM detalle_pedido dp WHERE dp.cod_pedido = p.cod_pedido) AS total_calculado

-- factura_comprobante.sql:57  total acumulado con función de ventana
SUM(dp.cantidad * dp.precio_unitario_venta) OVER (ORDER BY dp.item ROWS UNBOUNDED PRECEDING)
```

Resultado para el pedido 4: factura B 0001-00000004, subtotal 775842.34 + IVA 82157.66 = 858000.00.

---

## 7. Otros aportes a lo largo del proyecto

| Etapa | Qué hice | Commit |
|---|---|---|
| I | Actores del sistema, aclaración de alícuotas y precios | `f7a70f7`, `e425dc0` |
| II | Decisiones de diseño (inicio), normalización de **compras**, justificación de las 22 tablas | `59576de`, `dbd446f`, `4ec34cb` |
| III | Correcciones y actualizaciones del DDL (UNIQUE en `factura.cod_pedido`, acentos), restricciones y pruebas al día (52 casos) | `d2e5453`, `fded9ac`, `1c15427` |
| V | Adapté los scripts del equipo al esquema nuevo; documenté las transacciones anidadas (después Mechi las rehízo como T7-T16) | `5d1293d`, `c6d5642` |
| General | README con el estado y el orden de ejecución | `5baa553`, `71bc9d2` |

> El DDL original lo creó Mechi (`c38cf5e`); yo lo corregí y lo fui actualizando con los cambios de diseño.

## Preguntas que me pueden hacer

- **¿Por qué el índice con INCLUDE lee menos que el agrupado?** Sus hojas solo guardan 3 columnas: entran más filas por página.
- **¿Qué costo tiene un índice?** Espacio y más trabajo en cada INSERT/UPDATE/DELETE.
- **¿Qué diferencia hay entre los errores 229 y 230?** 229 es sobre el objeto (la tabla) y 230 sobre una columna.
- **¿Qué es el encadenamiento de propiedad?** Si el procedimiento y la tabla tienen el mismo dueño, solo se controla EXECUTE.
- **¿Por qué la cancelación usa UPDLOCK, HOLDLOCK?** Para que nadie facture ni despache el pedido mientras se cancela.
- **¿Por qué INSTEAD OF y no AFTER para las facturas?** AFTER se ejecuta después del borrado; INSTEAD OF lo reemplaza y no deja borrar.
- **¿Qué problema de normalización resolviste?** Una dependencia transitiva: cliente → localidad → provincia (3FN).
