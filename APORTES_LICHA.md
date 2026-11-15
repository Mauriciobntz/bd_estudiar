# Aportes de Lisandro Lopez (GitHub: Lisandro Lopez)

> Para responder "¿qué hiciste vos?" en la defensa. Las líneas son las del repo del proyecto
> (`MercedesSilFer/proyecto-bd1-equipo_37`, rama `main`). Commits: 15 en el historial.

## Cómo contarlo en un minuto

"En la Etapa V armé la base de los tres primeros temas técnicos: las **funciones y el procedimiento
de venta**, las **pruebas de transacciones T1 a T5** y los **cuatro triggers de auditoría** con sus
pruebas A1 a A5. Antes hice la **carga de datos de prueba** (Etapa III), el **reporte agregado de
ventas por categoría** (Etapa IV, CU-15) y completé el **modelo relacional** (Etapa II)."

---

## 1. Tema 1 — Funciones y procedimiento de venta

- **Archivo:** `docs/etapa-05/procedimientos_funciones/scripts.sql:1-362` (partes 1 y 2)
- **Commits:** `7ace1b3` scripts · `93e0f49` evidencias · `07d3e54` documentación.

| Línea | Objeto | Qué hace |
|---|---|---|
| 18 | `tipo_items_pedido` | tipo tabla: la lista de productos de una venta |
| 32 | `fn_descuento_vigente` | mayor descuento vigente de un producto (RN.24) |
| 56 | `fn_precio_final` | precio con IVA y descuento (RN.19, RN.28) |
| 84 | `fn_total_pedido` | total calculado desde el detalle (RN.10) |
| 119 | `sp_registrar_venta_completa` | pedido + detalle + stock en una operación |
| 237-362 | Pruebas A1-A3, B1-B3 | funciones y casos del procedimiento |

```sql
-- scripts.sql:32  función escalar
CREATE OR ALTER FUNCTION dbo.fn_descuento_vigente (@cod_producto INT, @fecha DATETIME)
RETURNS DECIMAL(5,2) AS
BEGIN
    RETURN ISNULL(
        (SELECT MAX(pr.porcentaje_descuento)                     -- la de mayor descuento
         FROM dbo.promocion pr
         INNER JOIN dbo.promocion_producto pp ON pp.cod_promocion = pr.cod_promocion
         WHERE pp.cod_producto = @cod_producto
           AND @fecha BETWEEN pr.fecha_inicio AND pr.fecha_fin),
        0);                                                       -- sin promoción: 0
END;
```

```sql
-- scripts.sql:119  procedimiento de venta (resumen)
CREATE OR ALTER PROCEDURE dbo.sp_registrar_venta_completa
    @cod_cliente INT, @cod_metodo_pago INT, @ref_transaccion VARCHAR(50),
    @items dbo.tipo_items_pedido READONLY, @cod_pedido INT OUTPUT, @cod_direccion INT = NULL
AS BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    DECLARE @tran_propia BIT = CASE WHEN @@TRANCOUNT = 0 THEN 1 ELSE 0 END;
    BEGIN TRY
        IF @tran_propia = 1 BEGIN TRANSACTION;
        -- 1. validaciones: errores 50001 a 50007
        -- 2. stock bloqueando las filas (línea 170)
        IF EXISTS (SELECT 1 FROM @items i
                   INNER JOIN dbo.producto p WITH (UPDLOCK, HOLDLOCK) ON p.cod_producto = i.cod_producto
                   WHERE p.stock < i.cantidad)
            THROW 50005, 'Stock insuficiente para al menos un producto de la venta.', 1;
        -- 3. INSERT del pedido copiando la dirección; SCOPE_IDENTITY() (línea 189)
        -- 4. INSERT del detalle congelando precio, alícuota e IVA (CROSS APPLY fn_precio_final)
        -- 5. UPDATE del stock con JOIN a @items
        IF @tran_propia = 1 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @tran_propia = 1 AND @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
```

**Resultados:** A1 Funda Notebook al 20/09/2026 → 35 % y 5200.00 · A3 la función reproduce todos
los precios guardados (0 diferencias) · B1 venta con 2 renglones y total 58000.00 · B2 error 50005 ·
B3 error 50001.

---

## 2. Tema 2 — Transacciones (T1 a T5)

- **Archivo:** `docs/etapa-05/transacciones/scripts.sql:1-243`
- **Commits:** `cefeeea` script · `49963a3` evidencias · `baad8b6` documentación.

| Línea | Prueba | Qué demuestra |
|---|---|---|
| 13 | T1 | venta con COMMIT (stock 40→39) |
| 67 | T2 | stock insuficiente → ROLLBACK, error 50005 |
| 104 | T3 | **atomicidad**: si falla el detalle, tampoco queda el pedido (error 547) |
| 152 | T4 | **SAVE TRANSACTION**: se deshace el detalle y el pedido sigue |
| 202 | T5 | el procedimiento usa la transacción del llamador (`tran_count` 1) |

```sql
-- Patrón de T1 a T5
BEGIN TRY
    BEGIN TRANSACTION;
        EXEC dbo.sp_registrar_venta_completa ... ;
    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    SELECT ERROR_NUMBER() AS error, ERROR_MESSAGE() AS mensaje;
END CATCH;

-- transacciones/scripts.sql:174  T4 punto de guardado
SAVE TRANSACTION punto_detalle;
    -- ...cambio que se quiere poder deshacer...
ROLLBACK TRANSACTION punto_detalle;   -- vuelve hasta el punto; la transacción sigue abierta
```

---

## 3. Tema 3 — Triggers de auditoría

- **Archivo:** `docs/etapa-05/triggers_auditoria/scripts.sql:1-356`
- **Commits:** `327823c` script · `982aa90` evidencias · `7bf5c3b` documentación.

| Línea | Trigger / prueba |
|---|---|
| 16 / 55 / 94 / 131 | `trg_producto_auditoria`, `trg_pedido_auditoria`, `trg_compra_auditoria`, `trg_factura_auditoria` |
| 200 | A1 UPDATE de stock → 1 fila con antes y después |
| 234 | A2 INSERT y DELETE de un producto |
| 264 | A3 venta dentro de una transacción revertida → la auditoría también se revierte |
| 307 | A4 empleado inexistente → falla la FK y el UPDATE no se aplica |
| 330 | A5 un UPDATE de 10 productos → 10 filas (por conjuntos) |

```sql
-- triggers_auditoria/scripts.sql:16
CREATE OR ALTER TRIGGER dbo.trg_producto_auditoria
ON dbo.producto AFTER INSERT, UPDATE, DELETE AS
BEGIN
    SET NOCOUNT ON;
    IF TRIGGER_NESTLEVEL() > 1 RETURN;
    DECLARE @cod_usuario INT = ISNULL(TRY_CAST(SESSION_CONTEXT(N'cod_usuario') AS INT), 1);
    INSERT INTO dbo.auditoria (entidad, operacion, registro_id, valor_anterior, valor_nuevo, cod_usuario)
    SELECT 'producto',
           CASE WHEN d.cod_producto IS NULL THEN 'INSERT'
                WHEN i.cod_producto IS NULL THEN 'DELETE' ELSE 'UPDATE' END,
           COALESCE(i.cod_producto, d.cod_producto),
           CASE WHEN d.cod_producto IS NULL THEN NULL
                ELSE CONCAT('precio_lista=', d.precio_lista, '; stock=', d.stock) END,
           CASE WHEN i.cod_producto IS NULL THEN NULL
                ELSE CONCAT('precio_lista=', i.precio_lista, '; stock=', i.stock) END,
           @cod_usuario
    FROM inserted i
    FULL OUTER JOIN deleted d ON d.cod_producto = i.cod_producto
    WHERE i.cod_producto IS NULL OR d.cod_producto IS NULL
       OR i.precio_lista <> d.precio_lista OR i.stock <> d.stock;
END;

-- Así "se loguea" el empleado en las pruebas (línea 221)
EXEC sys.sp_set_session_context @key = N'cod_usuario', @value = 3;
```

---

## 4. Etapas anteriores

| Etapa | Aporte | Archivo | Commit |
|---|---|---|---|
| II | Tablas del modelo relacional, reglas de mapeo y diagrama Mermaid | `docs/etapa-02/modelo-relacional.md` | `73ce948`, `a851d70` |
| III | **Carga de datos de prueba** (DML) | `sql/dml/cargar_datos.sql` | `bd60163` |
| IV | **Reporte agregado de ventas por categoría** + CU-15 | `sql/consultas/reporte_agregado.sql`, `docs/etapa-04/reporte-agregado.md` | `0dae467`, `0052200`, `0cb3a80` |

```sql
-- cargar_datos.sql  códigos explícitos para que las FK sean predecibles
SET IDENTITY_INSERT producto ON;
INSERT INTO producto (cod_producto, nombre, descripcion, precio_lista, cod_alicuota, stock, cod_categoria)
VALUES (1, 'Smart TV 50"', 'Televisor LED 4K...', 289256.20, 5, 12, 6),  -- alícuota 5 = 21 %
       (2, 'Auriculares BT', ..., 20661.16, 5, 40, 7), ...;
SET IDENTITY_INSERT producto OFF;
-- Orden: primero los padres (provincia, categoría...) y después los que los referencian.
```

```sql
-- reporte_agregado.sql:19  ventas por categoría en un período
SELECT cat.cod_categoria, cat.nombre AS categoria,
       COUNT(DISTINCT p.cod_pedido)                               AS cant_ventas,
       SUM(dp.cantidad)                                           AS unidades_vendidas,
       SUM(dp.cantidad * dp.precio_unitario_venta)                AS total_vendido,
       SUM(dp.cantidad * dp.precio_unitario_venta - dp.iva_monto) AS total_neto
FROM pedido p
INNER JOIN detalle_pedido dp  ON dp.cod_pedido     = p.cod_pedido
INNER JOIN producto       pr  ON pr.cod_producto   = dp.cod_producto
INNER JOIN categoria      cat ON cat.cod_categoria = pr.cod_categoria
WHERE p.estado = 'confirmado' AND p.estado_pago = 'aprobado'
  AND p.fecha_pedido >= @fecha_desde
  AND p.fecha_pedido <  DATEADD(DAY, 1, @fecha_hasta)     -- incluye todo el último día
GROUP BY cat.cod_categoria, cat.nombre
ORDER BY total_vendido DESC;
-- La segunda consulta (línea 44) agrupa por categoría PRINCIPAL con una autorrelación
-- (LEFT JOIN categoria padre) y COALESCE(padre.nombre, cat.nombre).
```

Resultado (01/07 al 30/09/2026): 8 categorías, Línea blanca primera con 1109999.99; por categoría
principal, 5, con Electrodomésticos primera (1279999.99).

---

## Preguntas que le pueden hacer

- **¿Función o procedimiento? ¿Por qué la venta es un procedimiento?** Porque modifica datos y maneja una transacción; una función no puede.
- **¿Para qué el tipo tabla?** Para recibir todos los productos de la venta en una sola llamada (`READONLY`).
- **¿Para qué `UPDLOCK, HOLDLOCK`?** Para que dos ventas de la última unidad no pasen las dos el control de stock (aislamiento).
- **¿Por qué `XACT_ABORT ON`?** Para que cualquier error revierta toda la transacción.
- **¿Qué son `inserted` y `deleted`?** Las filas nuevas y viejas de la sentencia; un UPDATE tiene las dos.
- **¿Por qué `FULL OUTER JOIN` en el trigger?** Para cubrir INSERT (solo inserted), DELETE (solo deleted) y UPDATE (las dos) en un solo SELECT.
- **¿Qué demuestran A3 y A4?** Que el trigger corre en la misma transacción: si se revierte el cambio, se revierte la auditoría, y si falla la auditoría, el cambio no se aplica.
- **En el reporte, ¿por qué `< DATEADD(DAY, 1, @fecha_hasta)`?** Porque `fecha_pedido` tiene hora; con `<=` se perderían las ventas del último día después de las 00:00.
- **¿Por qué `COUNT(DISTINCT p.cod_pedido)`?** El JOIN con el detalle repite el pedido en cada renglón.
