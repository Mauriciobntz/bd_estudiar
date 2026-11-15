# Guía para la defensa — SmartHome Store (Equipo 37)

> **Cómo leer las ubicaciones:** los números de línea son los del repositorio del proyecto
> (`MercedesSilFer/proyecto-bd1-equipo_37`, rama `main`), que es lo que abren los profes.
> En este repo de estudio (`bd_estudiar`) los mismos archivos tienen notas `-- >` agregadas,
> así que las líneas están corridas: buscá por el nombre del objeto (Ctrl+F).

---

## 0. El proyecto en 30 segundos

- **Caso:** SmartHome Store, minorista de electrodomésticos que vendía por teléfono y redes y
  llevaba pedidos y stock en planillas → errores (vender sin stock, datos duplicados).
- **Objetivo:** base relacional que soporte el ciclo completo de venta con integridad,
  consistencia y sin redundancia.
- **Números para recordar:** 30 reglas de negocio · 22 tablas · 52 pruebas de validación ·
  17 consultas (15 casos de uso) · 5 temas técnicos · 0 errores al ejecutar todo desde cero.
- **Motor:** SQL Server (T-SQL).

| Etapa | Qué hay | Dónde |
|---|---|---|
| I. Requerimientos | Caso, alcance, actores, 30 RN | `docs/etapa-01/` |
| II. Modelado | DER, modelo relacional, normalización, 17 decisiones | `docs/etapa-02/` |
| III. Implementación | DDL (22 tablas), datos, restricciones, 52 pruebas | `sql/ddl/`, `sql/dml/`, `docs/etapa-03/` |
| IV. Consultas | Comprobante, reporte agregado, 13 consultas avanzadas | `sql/consultas/`, `docs/etapa-04/` |
| V. Temas técnicos | Los 5 temas | `docs/etapa-05/`, `sql/tecnico/` |

---

## 1. Etapas I a IV (resumen rápido)

### Etapa I — Requerimientos (Unidad 1-2)
- **Archivos:** `docs/etapa-01/descripcion-caso.md`, `alcance.md`, `reglas-negocio.md`.
- **Reglas clave que te pueden preguntar:**
  - **RN.03** el precio queda congelado en el detalle del pedido.
  - **RN.04 / RN.29** varias direcciones por titular, una principal; la del pedido se copia como texto.
  - **RN.10** el total del pedido NO se guarda, se calcula.
  - **RN.11** no se vende sin stock.
  - **RN.14** cambios sensibles quedan auditados.
  - **RN.17** una sola factura por pedido.
  - **RN.20** la compra nace pendiente y suma stock recién al confirmarse.
  - **RN.30** cancelación: solo si no está facturado ni despachado; si estaba confirmado, repone stock.

### Etapa II — Modelado (Unidades 2, 3 y 4)
- **DER:** `docs/etapa-02/DER/DER.png` · **Modelo relacional:** `docs/etapa-02/modelo-relacional.md`
- **Normalización:** `docs/etapa-02/normalizacion.md` — se parte de la planilla del negocio:
  - **1FN:** atributos atómicos, sin grupos repetidos (los productos de un pedido van a `detalle_pedido`).
  - **2FN:** sin dependencias parciales. En `detalle_pedido` (clave pedido + producto), `nombre_producto` y `categoria` dependían solo de `cod_producto` ⇒ tabla `producto`. Precio y cantidad sí dependen de la clave completa.
  - **3FN:** sin dependencias transitivas. `cod_pedido → cod_cliente → nombre, email, dirección` ⇒ tabla `cliente`; y `cod_cliente → cod_localidad → provincia` ⇒ `direccion`, `localidad` y `provincia`.
  - El mismo proceso se hizo con la planilla de **compras** (sección 6).
- **Decisiones de diseño:** `docs/etapa-02/decisiones-diseno.md` (17). Las más defendibles:
  - **7, 9 y 12 — copias históricas a propósito:** dirección en el pedido (7), alícuota (9) y precio con promoción (12) en el detalle. No es redundancia mal hecha: es una foto del momento de la venta (desnormalización deliberada, Unidad 4).
  - **13 — alícuotas con el código de ARCA** (3=0 %, 4=10,5 %, 5=21 %...).
  - **16 — por qué 22 tablas:** cada una responde a una regla o a la normalización.
  - **17 — cancelación** con transacción.

### Etapa III — Implementación (Unidad 3 y DDL)
- **DDL:** `sql/ddl/crear_bd.sql` · **Datos:** `sql/dml/cargar_datos.sql`
- **Restricciones:** `docs/etapa-03/restricciones-integridad.md` · **Pruebas:** `docs/etapa-03/pruebas-validacion.md` (52 casos).
- Líneas clave de `crear_bd.sql`:

| Línea | Qué es | Concepto que demuestra |
|---|---|---|
| 23 | `cliente` (`CK_cliente_email`, `UQ_cliente_email`) | CHECK con LIKE, UNIQUE |
| 103 | `direccion` + `CK_direccion_titular` | o cliente o proveedor, nunca los dos |
| 119-121 | Índices **únicos filtrados** `WHERE principal = 1` | una sola principal por titular |
| 124 | `trg_direccion_principal` | trigger que asigna la principal más reciente |
| 159 | `pedido` (`CK_pedido_ref_transaccion`) | "si aprobado ⇒ tiene referencia" |
| 204 | `auditoria` (`DEFAULT SUSER_SNAME()`) | DEFAULT con función |
| 219 | `factura` (`UQ_factura_pedido`) | relación 1:1 pedido-factura |
| 245 | `detalle_pedido` PK compuesta + `ON DELETE CASCADE` | tabla intermedia N:M |
| 274 | `promocion` (`CK_promocion_beneficio`) | CHECK con OR |

```sql
-- crear_bd.sql:116  una dirección es de un cliente O de un proveedor
CONSTRAINT CK_direccion_titular CHECK (
  (cod_cliente IS NOT NULL AND cod_proveedor IS NULL) OR
  (cod_cliente IS NULL AND cod_proveedor IS NOT NULL))

-- crear_bd.sql:119  índice único FILTRADO: solo cuenta las filas principales
CREATE UNIQUE INDEX UQ_direccion_principal_cliente
  ON direccion(cod_cliente) WHERE principal = 1 AND cod_cliente IS NOT NULL;
```

- **CASCADE vs NO ACTION** (pregunta clásica): `detalle_pedido` y `direccion` usan **CASCADE** (no existen sin su padre: entidad débil). `pedido → cliente` usa **NO ACTION**: no se puede borrar un cliente con ventas (se perdería historial).

### Etapa IV — Consultas (Unidad 5: SELECT, JOIN, agregación, subconsultas)
- **Archivos:** `sql/consultas/factura_comprobante.sql`, `reporte_agregado.sql`, `consulta_avanzada.sql`; explicación en `docs/etapa-04/`.

| Archivo:línea | Consulta | Técnica | Resultado esperado |
|---|---|---|---|
| factura:12 | Encabezado del comprobante | INNER JOIN de 5 tablas, `RIGHT('0000'+CAST(...))` | Factura B 0001-00000004, total 858000.00 |
| factura:40 | Detalle | `SUM() OVER (ORDER BY item)` (función de ventana) | 2 renglones, acumulado 858000.00 |
| reporte:13 | Ventas por categoría | GROUP BY, `COUNT(DISTINCT)`, `DATEADD` | 8 categorías, Línea blanca primera |
| reporte:38 | Por categoría principal | autorrelación `categoria` + `COALESCE` | 5 categorías |
| avanzada:9 | Clientes de alto valor | HAVING con subconsulta (AVG de SUM) | 4 clientes |
| avanzada:42 | Margen bajo | **CTE** (`WITH`), costo ponderado | 4 productos |
| avanzada:109 | Clientes sin compras | **NOT EXISTS** correlacionado | Federico Molina |
| avanzada:147 | Clientes por categoría | **IN** anidado 4 niveles | 3 clientes (Audio) |
| avanzada:179 | Promos vigentes | EXISTS + `BETWEEN` | 4 productos |
| avanzada:227 | Pedido de mayor importe | tablas derivadas + `= MAX` | pedido 4 |
| avanzada:281 | Más caros que una categoría | **`> ALL`** | 1 producto |
| avanzada:318 | Facturas sobre el promedio de su tipo | subconsulta correlacionada | 5 facturas |

**Conceptos de la Unidad 5 que salen de estas consultas:**
- **Orden lógico (OLP):** FROM → ON → JOIN → WHERE → GROUP BY → HAVING → SELECT → DISTINCT → ORDER BY. Por eso un alias del SELECT **no** sirve en WHERE pero **sí** en ORDER BY.
- **WHERE vs HAVING:** WHERE filtra filas antes de agrupar; HAVING filtra grupos después. Filtrar en WHERE cuando se puede es más eficiente.
- **NULL:** `= NULL` da UNKNOWN; se usa `IS NULL`. `COUNT(*)` cuenta filas, `COUNT(col)` ignora NULL. `NOT IN` con un NULL devuelve vacío → por eso usamos `NOT EXISTS`.
- **No se pueden anidar agregados** (`AVG(SUM(...))`): se resuelve con tabla derivada.

---

## 2. Tema 1 — Procedimientos y funciones almacenadas

**Archivo:** `docs/etapa-05/procedimientos_funciones/scripts.sql` · **Doc:** `.../investigacion.md`

**Concepto:**
- **Función:** devuelve un valor (escalar) o una tabla; se usa *dentro* de una consulta; **no puede modificar datos**.
- **Procedimiento:** se llama con `EXEC`; puede modificar datos, manejar transacciones y errores, devolver valores con `OUTPUT`.
- **Ventajas:** la regla de negocio queda en un solo lugar, rendimiento (plan compilado), **seguridad** (se da permiso de EXECUTE sin dar permiso sobre las tablas).

| Línea | Objeto | Para qué |
|---|---|---|
| 18 | `tipo_items_pedido` (tipo tabla) | pasar todos los productos de la venta en una llamada |
| 32 | `fn_descuento_vigente` | mayor descuento vigente (RN.24) |
| 56 | `fn_precio_final` | lista × (1+IVA) × (1−descuento) |
| 84 | `fn_total_pedido` | total calculado (RN.10) |
| 119 | `sp_registrar_venta_completa` | venta completa en una operación |
| 387 | `fn_stock_disponible` | stock si el producto está activo |
| 398 | `fn_pedidos_cliente` | función de **tabla en línea** |
| 428 / 475 / 527 | `usp_producto_insertar/modificar/eliminar` | ABM de productos |
| 810 | Parte 5 | comparación de eficiencia |

```sql
-- scripts.sql:56  función escalar que usa otra función
SELECT @precio = ROUND(
         p.precio_lista
         * (1 + a.porcentaje / 100)                                       -- IVA
         * (1 - dbo.fn_descuento_vigente(p.cod_producto, @fecha) / 100),  -- descuento
         2)
FROM dbo.producto p
INNER JOIN dbo.alicuota_iva a ON a.cod_alicuota = p.cod_alicuota
WHERE p.cod_producto = @cod_producto;
-- Ejemplo: Funda Notebook al 20/09/2026 = 6611.57 * 1,21 * 0,65 = 5200.00
```

```sql
-- scripts.sql:119  firma del procedimiento de venta
CREATE OR ALTER PROCEDURE dbo.sp_registrar_venta_completa
    @cod_cliente     INT,
    @cod_metodo_pago INT,
    @ref_transaccion VARCHAR(50),
    @items           dbo.tipo_items_pedido READONLY,  -- parámetro de tipo tabla
    @cod_pedido      INT OUTPUT,                      -- parámetro de salida
    @cod_direccion   INT = NULL                       -- opcional: si no, la principal
```

**Pasos del procedimiento de venta:** validar (errores 50001 a 50007) → verificar stock con
`UPDLOCK, HOLDLOCK` (línea 170) → INSERT del pedido copiando la dirección → `SCOPE_IDENTITY()`
(línea 189) → INSERT del detalle congelando precio e IVA → UPDATE del stock.

**Preguntas probables:**
- *¿Por qué `SCOPE_IDENTITY()` y no `@@IDENTITY`?* Porque el trigger de auditoría de `pedido` inserta en `auditoria`: `@@IDENTITY` devolvería el código de la auditoría.
- *¿Por qué eliminar a veces da baja lógica?* Con historial (vendido o comprado) no se puede borrar sin perder trazabilidad, y la FK lo impide: se pone `activo = 0`.
- *¿Qué mostró la comparación de eficiencia?* El INSERT directo fue más rápido que llamar al procedimiento 2000 veces (≈2,8 veces); la función escalar fue más rápida que la subconsulta en nuestra medición, lo contrario de la teoría (posible *inlining* de SQL Server 2019+, no verificado).

---

## 3. Tema 2 — Manejo de transacciones

**Archivo:** `docs/etapa-05/transacciones/scripts.sql` · **Doc:** `.../investigacion.md`

**Concepto — ACID:**
- **A**tomicidad: todo o nada. **C**onsistencia: siempre se cumplen las reglas.
- **A**islamiento (I de *Isolation*): no se ven cambios a medias de otra transacción. **D**urabilidad: tras el COMMIT queda guardado (log).
- Instrucciones: `BEGIN TRAN`, `COMMIT`, `ROLLBACK`, `SAVE TRANSACTION`.
- Control: `@@TRANCOUNT` (cuántas abiertas), `XACT_STATE()` (1 se puede confirmar, 0 no hay, −1 condenada), `@@ROWCOUNT`.

| Línea | Prueba | Qué demuestra |
|---|---|---|
| 13 | T1 | venta con COMMIT |
| 67 | T2 | stock insuficiente → ROLLBACK (50005) |
| 104 | T3 | atomicidad: falla el detalle, tampoco queda el pedido |
| 152 | T4 | `SAVE TRANSACTION` (punto de guardado) |
| 202 | T5 | el procedimiento respeta la transacción del llamador |
| 257 | `sp_cancelar_pedido` | **cancelación con reposición de stock (RN.30)** |
| 445-661 | T7-T10 | transacción explícita y **contraste sin transacción** |
| 735-762 | T11-T13 | anidamiento |
| 803 | `usp_confirmar_compra` | compra con punto de guardado |

```sql
-- Patrón que usan todas las pruebas
BEGIN TRY
    BEGIN TRANSACTION;
        -- INSERT pedido, INSERT detalle, UPDATE stock
    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;   -- deshace todo
    SELECT ERROR_NUMBER(), ERROR_MESSAGE();
END CATCH;
```

```sql
-- scripts.sql:257  sp_cancelar_pedido (lo central)
SELECT @estado = estado, @estado_envio = estado_envio
FROM dbo.pedido WITH (UPDLOCK, HOLDLOCK)          -- bloquea el pedido
WHERE cod_pedido = @cod_pedido;
-- 50008 inexistente · 50009 ya cancelado · 50010 tiene factura · 50011 despachado
IF @estado = 'confirmado'
    UPDATE p SET p.stock = p.stock + d.cantidad    -- repone stock
    FROM dbo.producto p
    INNER JOIN dbo.detalle_pedido d ON d.cod_producto = p.cod_producto
    WHERE d.cod_pedido = @cod_pedido;
UPDATE dbo.pedido SET estado = 'cancelado', estado_envio = NULL
WHERE cod_pedido = @cod_pedido;
```

**Anidamiento (lo que más preguntan):**
- SQL Server **no tiene transacciones anidadas reales**: un BEGIN dentro de otro solo suma 1 a `@@TRANCOUNT`.
- `COMMIT` interno solo resta 1; **no confirma nada**.
- `ROLLBACK` sin nombre (en cualquier nivel) **deshace todo** y deja `@@TRANCOUNT` en 0.
- Para deshacer solo una parte: `SAVE TRANSACTION punto` + `ROLLBACK TRANSACTION punto`.

**Dos estrategias en el proyecto:**
- **Venta y cancelación** (`XACT_ABORT ON` + `@tran_propia`): si falla, se cae toda la transacción del llamador. Es todo o nada.
- **Compra** (`usp_confirmar_compra`, `XACT_ABORT OFF` + `SAVE TRANSACTION`): si falla, deshace solo su parte y el llamador sigue (T16).

**Pregunta probable:** *¿Qué pasa sin transacción?* T10: el mismo error deja un **pedido huérfano** sin renglones. Con transacción (T8) no queda nada.

---

## 4. Tema 3 — Triggers de auditoría

**Archivo:** `docs/etapa-05/triggers_auditoria/scripts.sql` · **Doc:** `.../investigacion.md`

**Concepto:**
- Código que el motor ejecuta **solo** ante INSERT, UPDATE o DELETE. Nadie lo llama.
- **AFTER:** después de la sentencia, **dentro de su misma transacción**.
- **INSTEAD OF:** reemplaza la sentencia; la original no ocurre.
- Tablas virtuales: **`inserted`** (filas nuevas) y **`deleted`** (filas viejas). Un UPDATE tiene las dos.
- Se dispara **una vez por sentencia**, no por fila → hay que escribirlo por conjuntos.

| Línea | Trigger | Tabla | Qué guarda |
|---|---|---|---|
| 16 | `trg_producto_auditoria` | producto | precio y stock |
| 55 | `trg_pedido_auditoria` | pedido | estado, pago, envío |
| 94 | `trg_compra_auditoria` | compra | estado |
| 131 | `trg_factura_auditoria` | factura | tipo, número, total |
| 168 | `trg_factura_no_borrar` | factura | **INSTEAD OF DELETE** → error 50012 |

```sql
-- scripts.sql:16  estructura de un trigger de auditoría
CREATE OR ALTER TRIGGER dbo.trg_producto_auditoria
ON dbo.producto AFTER INSERT, UPDATE, DELETE
AS BEGIN
    IF TRIGGER_NESTLEVEL() > 1 RETURN;              -- no repetir si lo dispara otro trigger
    DECLARE @cod_usuario INT =
        ISNULL(TRY_CAST(SESSION_CONTEXT(N'cod_usuario') AS INT), 1);  -- empleado de la app
    INSERT INTO dbo.auditoria (entidad, operacion, registro_id, valor_anterior, valor_nuevo, cod_usuario)
    SELECT 'producto',
           CASE WHEN d.cod_producto IS NULL THEN 'INSERT'
                WHEN i.cod_producto IS NULL THEN 'DELETE' ELSE 'UPDATE' END,
           COALESCE(i.cod_producto, d.cod_producto),
           CONCAT('precio_lista=', d.precio_lista, '; stock=', d.stock),
           CONCAT('precio_lista=', i.precio_lista, '; stock=', i.stock),
           @cod_usuario
    FROM inserted i
    FULL OUTER JOIN deleted d ON d.cod_producto = i.cod_producto   -- antes y después
    WHERE i.cod_producto IS NULL OR d.cod_producto IS NULL
       OR i.precio_lista <> d.precio_lista OR i.stock <> d.stock;  -- solo si cambió
END;
```

| Línea | Prueba | Resultado |
|---|---|---|
| 200 | A1 UPDATE de stock | 1 fila de auditoría con antes/después |
| 264 | A3 venta + ROLLBACK | la auditoría también se revierte (**transaccional**) |
| 307 | A4 empleado inexistente | falla la FK → **el UPDATE tampoco se aplica** |
| 330 | A5 UPDATE de 10 productos | 10 filas en una sentencia (**por conjuntos**) |
| 357 | A6 usuario de la base | `usuario_bd` = login (`SUSER_SNAME()`) |
| 379 | A7 borrar factura | error 50012, la factura sigue |

**Preguntas probables:**
- *¿Dos usuarios en auditoría?* `cod_usuario` = el **empleado** que informa la app (por `SESSION_CONTEXT`); `usuario_bd` = el **login** de SQL Server. Con un login compartido, el segundo solo no alcanza.
- *¿Por qué en la base y no en la app?* Queda registrado cualquier cambio, también un UPDATE a mano.
- *¿Trigger o permiso DENY para no borrar facturas?* DENY no alcanza a dbo ni sysadmin; el trigger frena a todos.

---

## 5. Tema 4 — Permisos a nivel de usuarios (seguridad)

**Archivos:** `sql/tecnico/seguridad/01_permisos_estado_pedido.sql`, `02_usuarios_y_roles.sql`, `99_limpieza_usuarios.sql` · **Doc:** `docs/etapa-05/seguridad/investigacion.md`

**Concepto:**
- **LOGIN** (servidor): permite conectarse. **USER** (base): permite entrar a una base y recibir permisos.
- **Modo de autenticación:** solo Windows o **mixto** (también logins SQL con contraseña).
- **GRANT** da, **DENY** prohíbe (**gana sobre GRANT**), **REVOKE** quita.
- **Rol:** grupo de permisos; se agrega gente al rol en vez de repetir permisos.
- **Roles fijos:** `db_owner` (todo), `db_datareader` (solo leer).
- **Encadenamiento de propiedad:** si el procedimiento y las tablas son del mismo dueño (dbo), solo se controla EXECUTE.
- **Principio de mínimo privilegio** (Unidad 1, tema 6).

```sql
-- 01_permisos_estado_pedido.sql:24-29  la app no puede cancelar "a mano"
GRANT SELECT ON dbo.pedido TO rol_aplicacion;
GRANT UPDATE ON dbo.pedido (estado_envio, fecha_envio, transportista,
                            fecha_entrega, nro_seguimiento, cod_usuario) TO rol_aplicacion;
DENY  UPDATE ON dbo.pedido (estado) TO rol_aplicacion;           -- permiso por COLUMNA
GRANT EXECUTE ON dbo.sp_registrar_venta_completa TO rol_aplicacion;
GRANT EXECUTE ON dbo.sp_cancelar_pedido          TO rol_aplicacion;
GRANT EXECUTE ON TYPE::dbo.tipo_items_pedido     TO rol_aplicacion;
```

| Archivo:línea | Prueba | Resultado |
|---|---|---|
| 01:32 | S1 UPDATE directo del estado | **error 230** (permiso de columna) |
| 01:58 | S3 vender y cancelar con procedimientos | funciona, stock vuelve a 40 |
| 01:87 | S4 UPDATE de producto | **error 229** (permiso de objeto) |
| 02:51 | U1 admin (`db_owner`) inserta | 1 fila |
| 02:69 | U3 lectura inserta | error 229 |
| 02:84 | U4 lectura vende **con el procedimiento** | funciona (encadenamiento de propiedad) |
| 02:147-166 | R1-R3 con rol / sin rol / otra tabla | lee / 229 / 229 |

**Preguntas probables:**
- *¿Por qué el usuario de solo lectura puede vender?* Tiene EXECUTE sobre el procedimiento; por encadenamiento de propiedad no se controlan sus permisos sobre las tablas, y solo puede cambiar datos como el procedimiento lo permite.
- *¿Qué problema resuelve el DENY sobre `estado`?* Cambiar el estado a mano no repone el stock; se obliga a usar `sp_cancelar_pedido`.
- *`EXECUTE AS LOGIN` / `REVERT`:* actuar como otro usuario para probar sus permisos y volver.

---

## 6. Tema 5 — Optimización de consultas a través de índices

**Archivos:** `sql/tecnico/indices/01_carga_masiva.sql`, `02_pruebas_indices.sql`, `03_limpieza.sql` · **Doc:** `docs/etapa-05/optimizacion_indices/investigacion.md` · **Planes:** `.../evidencias/*.sqlplan`

**Concepto:**
- **Índice:** estructura ordenada (árbol B) para llegar a las filas sin leer toda la tabla.
- **Heap:** tabla sin índice agrupado; buscar = leer todo (**Table Scan**).
- **Agrupado (CLUSTERED):** ordena la tabla misma; uno por tabla; la PK lo crea por defecto.
- **No agrupado (NONCLUSTERED):** estructura aparte con puntero a la fila; puede haber varios.
- **INCLUDE:** guarda columnas extra en las hojas → índice **cubriente** (responde sin ir a la tabla).
- **Seek** = búsqueda dirigida; **Scan** = recorrido completo.
- **Costo:** ocupan espacio y cada INSERT/UPDATE/DELETE debe actualizarlos.
- Se mide con **lecturas lógicas** (páginas de 8 KB), más confiables que el tiempo.

```sql
-- 01_carga_masiva.sql:35  generador de 1.000.000 de filas (tabla auxiliar venta_historica)
SELECT TOP (1000000) CAST(ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS BIGINT) AS i
FROM sys.all_objects a CROSS JOIN sys.all_objects b

-- 02_pruebas_indices.sql  la misma consulta en los 3 escenarios (ventas de enero 2025)
SET STATISTICS IO, TIME ON;                                     -- línea 17
SELECT cod_venta, fecha_venta, importe FROM dbo.venta_historica
WHERE fecha_venta >= '2025-01-01' AND fecha_venta < '2025-02-01';

CREATE CLUSTERED INDEX IX_venta_historica_fecha                 -- línea 34
  ON dbo.venta_historica (fecha_venta);
CREATE NONCLUSTERED INDEX IX_venta_historica_fecha_cubre        -- línea 49
  ON dbo.venta_historica (fecha_venta) INCLUDE (cod_venta, importe);
```

| Escenario | Operador del plan | Filas | Lecturas lógicas |
|---|---|---|---|
| 1. Sin índice | Table Scan | 14.158 de 1.000.000 | **25.642** |
| 2. Agrupado por fecha | Clustered Index Seek | 14.158 | **367** (−98,6 %) |
| 3. No agrupado con INCLUDE | Index Seek | 14.158 | **67** (−99,7 %) |

**Preguntas probables:**
- *¿Por qué no un agrupado con INCLUDE como pedía la consigna?* SQL Server no lo permite: el agrupado ya contiene todas las columnas.
- *¿Por qué una tabla aparte y no `pedido`?* `pedido` ya tiene agrupado en su PK, y su trigger generaría un millón de filas de auditoría.
- *¿Por qué el cubriente lee menos?* Sus hojas solo tienen 3 columnas, no la fila entera: entran más filas por página.
- *Desventaja del cubriente:* ocupa espacio extra y solo cubre esta consulta.
- *¿Por qué no `YEAR(fecha) = 2025`?* Aplicar una función a la columna impide usar el índice (rango semiabierto sí).
- *DBCC DROPCLEANBUFFERS:* vacía la memoria para medir "en frío"; solo en un equipo de pruebas.

---

## 7. Cómo ejecutar todo (por si lo piden en vivo)

Orden del README: `crear_bd.sql` → `cargar_datos.sql` → consultas → `procedimientos_funciones/scripts.sql` → `transacciones/scripts.sql` → `triggers_auditoria/scripts.sql` → seguridad 01 y 02 (limpiar con 99) → índices 01, 02, 03.

**Control rápido después de cargar:** 22 tablas · 12 pedidos · 18 renglones · 10 productos · 10 facturas · 10 auditorías · stock del producto 2 = 40.

---

## 8. Límites honestos (mejor decirlos antes de que los marquen)

- El **aislamiento** (`UPDLOCK, HOLDLOCK`) no se probó con dos sesiones simultáneas.
- Faltan capturas de SSMS de seguridad y de A6/A7 (verificado con `sqlcmd`).
- Quedan fuera del alcance: devoluciones y notas de crédito, costo de envío, integración real con pagos y con ARCA.
