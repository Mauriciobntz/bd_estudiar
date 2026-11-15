# Defensa de los 5 temas técnicos (para Enzo y Licha)

> Cualquiera de los dos puede tener que defender **cualquier tema**, lo haya hecho o no.
> Para cada tema: **qué decir en 2 minutos**, **qué mostrar en vivo**, **qué esperar** y **5 preguntas**.
> Las líneas son las del repo del proyecto (`MercedesSilFer/proyecto-bd1-equipo_37`, `main`).
> Para más detalle: `GUIA_DEFENSA.md` y `PREGUNTAS_DEFENSA.md`.

## Antes de entrar (preparar SSMS)

1. Ejecutar `sql/ddl/crear_bd.sql` y `sql/dml/cargar_datos.sql` (base limpia).
2. Ejecutar la **parte 1** de `docs/etapa-05/procedimientos_funciones/scripts.sql` (hasta la línea 221): crea las funciones y el procedimiento que usan los demás temas.
3. Ejecutar la parte de creación de `transacciones/scripts.sql` (`sp_cancelar_pedido`, línea 257) y de `triggers_auditoria/scripts.sql` (líneas 1-178).
4. Control: `SELECT COUNT(*) FROM pedido` → 12 · `SELECT stock FROM producto WHERE cod_producto = 2` → 40.
5. Para mostrar algo en vivo: **seleccionar solo el bloque** y F5. Los resultados de `PRINT` salen en la pestaña **Mensajes**.

---

## Tema 1 — Procedimientos y funciones almacenadas

### Qué decir (2 minutos)
> "Una **función** devuelve un valor o una tabla y se usa dentro de una consulta; no puede modificar
> datos. Un **procedimiento** se ejecuta con EXEC, puede modificar datos, manejar transacciones y
> errores y devolver valores con OUTPUT. Las usamos para que las reglas de negocio estén en un solo
> lugar. Hicimos tres funciones para el precio: `fn_descuento_vigente` busca el mayor descuento vigente
> (RN.24), `fn_precio_final` le suma el IVA y le aplica ese descuento, y `fn_total_pedido` calcula el
> total desde el detalle, porque el total no se guarda (RN.10). El procedimiento central es
> `sp_registrar_venta_completa`: recibe la lista de productos en un **tipo tabla**, valida, controla el
> stock bloqueando las filas, crea el pedido, copia el precio al detalle y baja el stock, todo en una
> transacción. Además hay un ABM de productos con validaciones; el de eliminar hace baja lógica si el
> producto tiene historial. Y comparamos eficiencia contra operaciones directas."

### Dónde está
`docs/etapa-05/procedimientos_funciones/scripts.sql` — tipo tabla 18 · funciones 32, 56, 84, 387, 398 · `sp_registrar_venta_completa` 119 · ABM 428, 475, 527 · eficiencia 810.

### Qué mostrar en vivo
```sql
-- A1 (línea 237): las funciones en una consulta
SELECT cod_producto, nombre, precio_lista,
       dbo.fn_descuento_vigente(cod_producto, '2026-09-20') AS descuento_pct,
       dbo.fn_precio_final(cod_producto, '2026-09-20')      AS precio_final
FROM producto ORDER BY cod_producto;
-- Esperado: producto 4 -> 35.00 y 5200.00; el resto 0 y precio con IVA.

-- B1 (línea 277): una venta dentro de una transacción que se revierte
BEGIN TRANSACTION;
DECLARE @items dbo.tipo_items_pedido, @nuevo INT;
INSERT INTO @items (cod_producto, cantidad) VALUES (2, 2), (4, 1);
EXEC dbo.sp_registrar_venta_completa @cod_cliente = 1, @cod_metodo_pago = 1,
     @ref_transaccion = 'DEMO-0001', @items = @items, @cod_pedido = @nuevo OUTPUT;
SELECT * FROM detalle_pedido WHERE cod_pedido = @nuevo;   -- 2 renglones, precio congelado
SELECT dbo.fn_total_pedido(@nuevo) AS total;
ROLLBACK TRANSACTION;                                       -- no deja datos
```
Capturas: `procedimientos_funciones/evidencias/01_funciones_precio.png` a `06_cliente_inexistente.png`, `C1`-`C4`, `D1`-`D6`, `prueba_eficiencia1/2.png`.

### Puntos que no pueden faltar
- `@items ... READONLY` (tipo tabla), `@cod_pedido INT OUTPUT`, `@cod_direccion INT = NULL` (opcional).
- `SCOPE_IDENTITY()` y no `@@IDENTITY` (el trigger de auditoría inserta en otra tabla).
- `WITH (UPDLOCK, HOLDLOCK)` en el control de stock (línea 170).
- Errores propios con `THROW 50001...50007` (deben ser ≥ 50000).
- `CROSS APPLY (SELECT dbo.fn_precio_final(...) AS precio)` para calcular una vez y usar dos veces.

### 5 preguntas
1. **¿Por qué la venta no es una función?** Modifica datos y usa una transacción; una función no puede.
2. **¿Qué es una función de tabla en línea?** `fn_pedidos_cliente`: devuelve filas y se usa en el FROM, como una vista con parámetro; se combina con `CROSS APPLY`.
3. **¿Ventajas de los procedimientos?** Reglas en un lugar, plan compilado, y seguridad: se da EXECUTE sin dar permiso sobre las tablas.
4. **¿Qué pasa si elimino un producto vendido?** Baja lógica (`activo = 0`); la FK de `detalle_pedido` impide borrarlo.
5. **¿Qué mostró la eficiencia?** El INSERT directo fue ≈2,8 veces más rápido que el procedimiento (costo de llamada y validaciones); el `INSERT ... SELECT` fue el más lento en esa corrida, al revés de la teoría; la función escalar fue más rápida que la subconsulta (posible inlining, no verificado).

---

## Tema 2 — Manejo de transacciones

### Qué decir (2 minutos)
> "Una **transacción** es un grupo de operaciones que se hace completo o no se hace. Cumple **ACID**:
> atomicidad (todo o nada), consistencia (siempre se cumplen las reglas), aislamiento (no se ven
> cambios a medias de otra transacción) y durabilidad (después del COMMIT queda guardado en el log).
> Se usa `BEGIN TRANSACTION`, `COMMIT`, `ROLLBACK` y `SAVE TRANSACTION`, con `TRY...CATCH` para
> capturar el error. En el proyecto la venta es la transacción central: pedido, detalle y stock juntos.
> Probamos el COMMIT, el ROLLBACK por stock insuficiente, la atomicidad y el punto de guardado, y
> contrastamos el mismo error **sin** transacción: queda un pedido sin renglones. Agregamos la
> **cancelación** de pedidos, que repone el stock en la misma transacción. Y mostramos que SQL Server
> no tiene transacciones anidadas reales: el COMMIT interno solo baja el contador y un ROLLBACK deshace todo."

### Dónde está
`docs/etapa-05/transacciones/scripts.sql` — T1-T5 líneas 13-243 · `sp_cancelar_pedido` 257 (T6 hasta 415) · T7-T10 445-720 · anidadas T11-T13 721-775 · `usp_confirmar_compra` 803 · T14-T16 852-970.

### Qué mostrar en vivo
```sql
-- T10 contra T8: la diferencia que convence
-- Sin transacción: el INSERT del pedido queda aunque después falle -> pedido huérfano.
-- Con transacción: el CATCH hace ROLLBACK -> no queda nada.

-- T11 (línea 735): anidamiento. Ver la pestaña Mensajes
PRINT @@TRANCOUNT;                 -- 0
BEGIN TRANSACTION externa;         -- 1
    BEGIN TRANSACTION interna;     -- 2
        INSERT INTO dbo.categoria (nombre) VALUES ('DEMO-ANIDADA-1');
    COMMIT TRANSACTION interna;    -- 1: todavía no confirmó nada
ROLLBACK TRANSACTION externa;      -- 0: la fila desaparece
SELECT COUNT(*) FROM dbo.categoria WHERE nombre = 'DEMO-ANIDADA-1';   -- 0

-- T6a: cancelar un pedido confirmado devuelve el stock
BEGIN TRANSACTION;
-- (vender 1 unidad del producto 2 con el procedimiento: stock 40 -> 39)
EXEC dbo.sp_cancelar_pedido @cod_pedido = @nuevo;   -- stock vuelve a 40
ROLLBACK TRANSACTION;
```
Capturas: `transacciones/evidencias/01_commit_venta.png` a `16_confirmar_compra_anidada_Mensajes.png` (hay 23; la cancelación es `06`).

### Puntos que no pueden faltar
- Patrón: `BEGIN TRY / BEGIN TRANSACTION / COMMIT / END TRY / BEGIN CATCH / IF @@TRANCOUNT > 0 ROLLBACK`.
- `@@TRANCOUNT`, `XACT_STATE()` (1, 0, −1), `@@ROWCOUNT` (T9: si el UPDATE no afectó filas, no había stock).
- `SET XACT_ABORT ON`: cualquier error aborta toda la transacción.
- Dos estrategias: venta y cancelación (todo o nada, `XACT_ABORT ON`) contra compra (punto de guardado, solo deshace su parte).

### 5 preguntas
1. **¿Qué hace un COMMIT dentro de otra transacción?** Solo resta 1 a `@@TRANCOUNT`; no confirma nada.
2. **¿Y un ROLLBACK interno?** Deshace todo, también la externa, y deja el contador en 0 (T12).
3. **¿Cómo deshago solo una parte?** `SAVE TRANSACTION punto` y `ROLLBACK TRANSACTION punto` (T4 y T13).
4. **¿Probaron dos ventas simultáneas?** No, está documentado como límite; el diseño lo cubre con `UPDLOCK, HOLDLOCK` y el `CHECK (stock >= 0)`.
5. **¿Por qué la cancelación necesita transacción?** Repone stock y cambia el estado: si fallara entre los dos, quedaría stock de más.

---

## Tema 3 — Triggers de auditoría

### Qué decir (2 minutos)
> "Un **trigger** es código que SQL Server ejecuta solo cuando hay un INSERT, UPDATE o DELETE en una
> tabla. Usamos triggers **AFTER** en producto, pedido, compra y factura para cumplir RN.14: cada cambio
> sensible queda en la tabla `auditoria` con la operación, el valor anterior, el nuevo, el empleado y
> el login. Dentro del trigger existen las tablas `inserted` y `deleted`; con un `FULL OUTER JOIN`
> entre las dos sabemos si fue INSERT, UPDATE o DELETE. El trigger se dispara una vez por sentencia,
> así que está escrito por conjuntos. Como corre dentro de la misma transacción, si se revierte el
> cambio se revierte la auditoría, y si falla la auditoría el cambio no se aplica. Además, un trigger
> **INSTEAD OF** impide borrar facturas, porque son comprobantes fiscales."

### Dónde está
`docs/etapa-05/triggers_auditoria/scripts.sql` — triggers 16, 55, 94, 131 (auditoría) y 168 (`INSTEAD OF`) · pruebas A0 185, A1 200, A2 234, A3 264, A4 307, A5 330, A6 357, A7 379.
Tabla: `crear_bd.sql:204` (`auditoria`, con `usuario_bd DEFAULT SUSER_SNAME()`).

### Qué mostrar en vivo
```sql
-- A1 (línea 200): un cambio queda auditado con antes y después
EXEC sys.sp_set_session_context @key = N'cod_usuario', @value = 3;   -- "se loguea" el empleado 3
UPDATE producto SET stock = stock - 1 WHERE cod_producto = 2;
SELECT TOP 1 operacion, valor_anterior, valor_nuevo, cod_usuario, usuario_bd
FROM auditoria ORDER BY cod_auditoria DESC;
-- Esperado: UPDATE | precio_lista=20661.16; stock=40 | ...stock=39 | 3 | tu login
UPDATE producto SET stock = stock + 1 WHERE cod_producto = 2;        -- limpiar

-- A7 (línea 379): no se puede borrar una factura
BEGIN TRY DELETE FROM factura WHERE cod_factura = 1; END TRY
BEGIN CATCH SELECT ERROR_NUMBER(), ERROR_MESSAGE(); END CATCH;      -- 50012
```
Capturas: `triggers_auditoria/evidencias/01_triggers_creados.png` a `06_auditoria_masiva.png` (A6 y A7 sin captura, verificados con sqlcmd).

### Puntos que no pueden faltar
- AFTER contra INSTEAD OF · `inserted` / `deleted` · una vez por sentencia (A5: 10 filas de un UPDATE).
- `SESSION_CONTEXT(N'cod_usuario')`: el empleado que informa la aplicación; si falta, el usuario 1.
- `usuario_bd = SUSER_SNAME()`: el login real.
- Transaccional: A3 (se revierte con la venta) y A4 (si falla la auditoría, falla el cambio).
- `TRIGGER_NESTLEVEL() > 1 RETURN` para no auditar dos veces.

### 5 preguntas
1. **¿Por qué en la base y no en la aplicación?** Así queda registrado cualquier cambio, también uno hecho a mano.
2. **¿Qué hay en `inserted` y `deleted` en un UPDATE?** Las filas nuevas y las viejas.
3. **¿Por qué FULL OUTER JOIN?** Para cubrir los tres casos en un solo SELECT.
4. **¿Qué pasa si se deshabilita el trigger?** Deja de auditar; es el límite. Solo pocos usuarios deberían poder hacerlo.
5. **¿Por qué dos usuarios en la auditoría?** El empleado (`cod_usuario`) y el login (`usuario_bd`); con un login compartido, el login solo no alcanza.

---

## Tema 4 — Manejo de permisos a nivel de usuarios

### Qué decir (2 minutos)
> "En SQL Server hay dos niveles: el **login**, que permite conectarse al servidor, y el **usuario**,
> que permite entrar a una base y recibir permisos. Los permisos se dan con **GRANT**, se prohíben con
> **DENY**, que gana sobre cualquier GRANT, y se quitan con **REVOKE**. Se agrupan en **roles** para
> aplicar el mínimo privilegio. Probamos un usuario administrador (`db_owner`), uno de solo lectura
> (`db_datareader`) y un rol propio que solo puede leer productos. La clave es que el usuario de solo
> lectura **no puede insertar en `pedido`, pero sí puede vender con el procedimiento**: es el
> **encadenamiento de propiedad**, porque el procedimiento y las tablas son del mismo dueño y solo se
> controla el permiso EXECUTE. Además, con un **DENY por columna** impedimos que la aplicación cambie
> el estado del pedido a mano, para que tenga que cancelar con el procedimiento que repone el stock."

### Dónde está
`sql/tecnico/seguridad/01_permisos_estado_pedido.sql` (rol de la aplicación, S1-S4) · `02_usuarios_y_roles.sql` (logins 19-25, usuarios 37-39, roles 42-43 y 132-144, pruebas U1-U5 y R1-R3) · `99_limpieza_usuarios.sql` · doc `docs/etapa-05/seguridad/investigacion.md`.

### Qué mostrar en vivo
```sql
-- Ejecutar 02_usuarios_y_roles.sql hasta la línea 49 (crea logins, usuarios y permisos)

EXECUTE AS LOGIN = 'smarthome_lectura';        -- actuar como el usuario de solo lectura
SELECT COUNT(*) FROM dbo.pedido;               -- U2: 12 (puede leer)
BEGIN TRY
    UPDATE dbo.producto SET stock = stock + 1 WHERE cod_producto = 2;
END TRY
BEGIN CATCH SELECT ERROR_NUMBER() AS error; END CATCH;   -- U5: 229 (no puede modificar)
REVERT;                                        -- volver a mi usuario

-- 01_permisos_estado_pedido.sql:26 y S1 (línea 32)
DENY UPDATE ON dbo.pedido (estado) TO rol_aplicacion;
EXECUTE AS USER = 'usuario_aplicacion';
BEGIN TRY UPDATE dbo.pedido SET estado = 'cancelado' WHERE cod_pedido = 10; END TRY
BEGIN CATCH SELECT ERROR_NUMBER() AS error; END CATCH;   -- 230 (permiso de columna)
REVERT;

-- Al final: 99_limpieza_usuarios.sql
```
Evidencia: tabla de resultados en `seguridad/investigacion.md` (verificado con `sqlcmd`, **sin capturas**). Las pruebas con login real necesitan el servidor en **modo mixto**.

### Puntos que no pueden faltar
- Login (servidor) contra usuario (base); `CREATE USER ... FOR LOGIN`.
- GRANT / DENY / REVOKE; DENY gana.
- Roles fijos (`db_owner`, `db_datareader`) y rol propio (`CREATE ROLE`, `ALTER ROLE ... ADD MEMBER`).
- Errores 229 (objeto) y 230 (columna).
- Encadenamiento de propiedad; `EXECUTE AS` / `REVERT` para probar.
- Límite: DENY no alcanza a dbo ni sysadmin.

### 5 preguntas
1. **¿Un usuario de solo lectura que vende no es un agujero?** No: solo puede cambiar datos como el procedimiento lo permite, con sus validaciones.
2. **¿Diferencia entre DENY y REVOKE?** REVOKE quita un permiso dado; DENY prohíbe y gana sobre un GRANT, también uno heredado de un rol.
3. **¿Por qué roles?** Para no repetir permisos por persona y aplicar el mínimo privilegio por función.
4. **¿Qué es el modo mixto?** El servidor acepta logins de Windows y también de SQL Server con contraseña.
5. **¿Por qué `GRANT EXECUTE ON TYPE::`?** El procedimiento recibe el tipo tabla y hay que poder declarar una variable de ese tipo.

---

## Tema 5 — Optimización de consultas a través de índices

### Qué decir (2 minutos)
> "Un **índice** es una estructura ordenada, un árbol B, que permite llegar a las filas sin leer toda
> la tabla. Una tabla sin índice agrupado es un **heap**: para buscar, la recorre entera (**Table
> Scan**). El índice **agrupado** ordena la tabla misma por esa columna y hay uno solo; el **no
> agrupado** es una estructura aparte con un puntero a la fila. Con **INCLUDE** el no agrupado guarda
> columnas extra y se vuelve **cubriente**: responde la consulta sin ir a la tabla. Para medirlo
> cargamos un millón de ventas en una tabla auxiliar y buscamos las de enero de 2025, unas 14.000
> filas, en tres escenarios, midiendo **lecturas lógicas**: sin índice 25.642, con el agrupado 367 y
> con el no agrupado con INCLUDE 67. La consigna pedía un agrupado con INCLUDE, pero SQL Server no lo
> permite porque el agrupado ya tiene todas las columnas. El costo de los índices es espacio y más
> trabajo en cada escritura."

### Dónde está
`sql/tecnico/indices/01_carga_masiva.sql` (tabla 19, carga 35-48) · `02_pruebas_indices.sql` (escenarios 20, 33 y 44; índices 34 y 49) · `03_limpieza.sql` · doc `docs/etapa-05/optimizacion_indices/investigacion.md` · planes `evidencias/plan_1_sin_indice.sqlplan`, `plan_2_indice_agrupado.sqlplan`, `plan_3_indice_no_agrupado_cubriente.sqlplan` (se abren en SSMS).

### Qué mostrar en vivo
```sql
-- 1. Ejecutar 01_carga_masiva.sql (tarda unos segundos)
-- 2. En 02_pruebas_indices.sql: Ctrl+M (plan real) y ejecutar
SET STATISTICS IO ON;   -- las lecturas aparecen en la pestaña Mensajes
SELECT cod_venta, fecha_venta, importe FROM dbo.venta_historica
WHERE fecha_venta >= '2025-01-01' AND fecha_venta < '2025-02-01';   -- Table Scan, 25.642
CREATE CLUSTERED INDEX IX_venta_historica_fecha ON dbo.venta_historica (fecha_venta);
-- misma consulta: Clustered Index Seek, 367
DROP INDEX IX_venta_historica_fecha ON dbo.venta_historica;
CREATE NONCLUSTERED INDEX IX_venta_historica_fecha_cubre
    ON dbo.venta_historica (fecha_venta) INCLUDE (cod_venta, importe);
-- misma consulta: Index Seek, 67
-- 3. Al final: 03_limpieza.sql (la base vuelve a 22 tablas)
```
Si no hay tiempo de ejecutar: abrir los tres `.sqlplan` y mostrar Scan contra Seek.

### Puntos que no pueden faltar
- Heap, agrupado, no agrupado, INCLUDE, cubriente.
- Seek (búsqueda dirigida) contra Scan (recorrido completo).
- Lecturas lógicas (páginas de 8 KB) son más confiables que el tiempo.
- Rango semiabierto `>= ... AND < ...`; con `YEAR(fecha) = 2025` no se usaría el índice.
- `DBCC DROPCLEANBUFFERS` vacía la memoria para medir en frío (solo en un equipo de pruebas).

### 5 preguntas
1. **¿Por qué no indexar todo?** Espacio y más trabajo en cada INSERT, UPDATE y DELETE.
2. **¿Por qué el cubriente lee menos que el agrupado?** Sus hojas tienen 3 columnas, no la fila entera: entran más filas por página.
3. **¿Desventaja del cubriente?** Solo sirve para esa consulta; si se pide otra columna, va a la tabla por cada fila (lookup).
4. **¿Por qué una tabla aparte?** Con 12 pedidos no hay diferencia; `pedido` ya tiene agrupado y su trigger generaría un millón de auditorías.
5. **¿Qué índices tiene la base real?** Los de las PK (agrupados), los de las UNIQUE y los dos únicos filtrados de `direccion`.

---

## Si te toca un tema que no hiciste

- **Arrancar por el concepto** (el primer párrafo de "Qué decir"): eso es lo que más evalúan.
- **Después, una prueba concreta con su resultado esperado**, y mostrarla en vivo o con su captura.
- **Terminar con el límite**: decirlo antes de que lo pregunten queda mejor que negarlo.
- **Si no sabés algo puntual:** "eso lo implementó tal compañero; lo que sé es que..." y volvé al concepto.
