# Podcasts con NotebookLM: uno por tema técnico

## Cómo hacerlo

1. Entrá a https://notebooklm.google.com y creá **un cuaderno por tema** (5 en total). Si los
   mezclás en uno solo, el podcast salta de un tema a otro.
2. En cada cuaderno subí las **fuentes** que figuran en su tema (abajo).
   - Los archivos están en https://github.com/Mauriciobntz/bd_estudiar: abrí el archivo, tocá **Raw**,
     copiá todo y usá **"Texto copiado"** como fuente. Si te deja subir el archivo directamente, mejor.
   - Los PDF de la cátedra (guías de lectura) se suben tal cual.
3. Configurá el **idioma de salida en español** (en la configuración del cuaderno o de NotebookLM).
4. En **Resumen de audio** tocá **Personalizar**, pegá el prompt del tema y generalo.
5. Escuchalo, y si algo no coincide con el proyecto, creele a los documentos del repo, no al audio.

> Fuente común para los 5 cuadernos: `DEFENSA_TEMAS_TECNICOS.md` (la sección del tema) y
> `GUION_DEFENSA.md` (la sección del tema).

---

## Tema 1 — Procedimientos y funciones almacenadas

**Fuentes:**
- `GUION_DEFENSA.md` y `DEFENSA_TEMAS_TECNICOS.md` (sección Tema 1)
- `docs/etapa-05/procedimientos_funciones/investigacion.md`
- `docs/etapa-05/procedimientos_funciones/scripts.sql`
- PDF de la cátedra: `BDI_U05_guia_lectura` (Tema 14)

**Prompt:**
```
Hacé un podcast en español rioplatense, de unos 12 minutos, entre dos estudiantes de Bases de Datos I
(UNNE) que preparan la defensa oral de su proyecto final, SmartHome Store, en SQL Server. El tema es
"Procedimientos y funciones almacenadas aplicados al proyecto".

Estructura:
1. Qué es una función y qué es un procedimiento, y la diferencia (la función devuelve un valor o una
   tabla, se usa dentro de una consulta y no modifica datos; el procedimiento se ejecuta con EXEC,
   modifica datos, maneja transacciones y devuelve valores con OUTPUT). Ventajas: reglas en un solo
   lugar, rendimiento y seguridad.
2. Cómo se aplicó en el proyecto: las funciones fn_descuento_vigente, fn_precio_final y fn_total_pedido
   (con las reglas RN.24, RN.19 y RN.10), y el procedimiento sp_registrar_venta_completa paso a paso:
   tipo tabla de productos, parámetro OUTPUT, validaciones con errores 50001 a 50007, bloqueo con
   UPDLOCK y HOLDLOCK, precio congelado en el detalle (RN.03) y SCOPE_IDENTITY en vez de @@IDENTITY.
   Mencioná el ABM de productos y la baja lógica.
3. Los resultados de las pruebas con sus números: Funda Notebook a 5200 con 35 % de descuento, error
   50005 por stock insuficiente, y la comparación de eficiencia.
4. Las preguntas difíciles que puede hacer un profesor y cómo responderlas.

Usá solo la información de las fuentes; si algo no está en ellas, no lo inventes. Explicá el código con
palabras, sin leerlo línea por línea. Terminá con un resumen de tres ideas clave para recordar.
```

---

## Tema 2 — Manejo de transacciones

**Fuentes:**
- `GUION_DEFENSA.md` y `DEFENSA_TEMAS_TECNICOS.md` (sección Tema 2)
- `docs/etapa-05/transacciones/investigacion.md`
- `docs/etapa-05/transacciones/scripts.sql`
- PDF de la cátedra: `BDI_U01_guia_lectura` (propiedades ACID) y `BDI_U05_guia_lectura`

**Prompt:**
```
Hacé un podcast en español rioplatense, de unos 12 minutos, entre dos estudiantes de Bases de Datos I
(UNNE) que preparan la defensa oral de su proyecto final, SmartHome Store, en SQL Server. El tema es
"Manejo de transacciones aplicado al proyecto".

Estructura:
1. Qué es una transacción y las propiedades ACID, con un ejemplo de la venta (pedido, detalle y stock).
   BEGIN TRANSACTION, COMMIT, ROLLBACK, SAVE TRANSACTION, el patrón TRY/CATCH y las variables
   @@TRANCOUNT, XACT_STATE y @@ROWCOUNT.
2. Cómo se aplicó: las pruebas T1 a T5 (COMMIT, ROLLBACK por stock insuficiente, atomicidad, punto de
   guardado, transacción del llamador), la cancelación de pedidos con sp_cancelar_pedido (RN.30,
   errores 50008 a 50011, reposición del stock en la misma transacción) y el contraste de T10: el mismo
   error sin transacción deja un pedido huérfano.
3. El anidamiento explicado con calma: SQL Server no tiene transacciones anidadas reales, el COMMIT
   interno solo baja el contador, un ROLLBACK deshace todo y SAVE TRANSACTION permite deshacer una
   parte (T11, T12 y T13). Las dos estrategias del proyecto: XACT_ABORT ON en la venta (todo o nada) y
   punto de guardado en usp_confirmar_compra.
4. El límite: el aislamiento no se probó con dos sesiones simultáneas, y cómo lo cubre el diseño.
5. Las preguntas difíciles que puede hacer un profesor y cómo responderlas.

Usá solo la información de las fuentes; si algo no está en ellas, no lo inventes. Explicá el código con
palabras, sin leerlo línea por línea. Terminá con un resumen de tres ideas clave para recordar.
```

---

## Tema 3 — Triggers de auditoría

**Fuentes:**
- `GUION_DEFENSA.md` y `DEFENSA_TEMAS_TECNICOS.md` (sección Tema 3)
- `docs/etapa-05/triggers_auditoria/investigacion.md`
- `docs/etapa-05/triggers_auditoria/scripts.sql`

**Prompt:**
```
Hacé un podcast en español rioplatense, de unos 12 minutos, entre dos estudiantes de Bases de Datos I
(UNNE) que preparan la defensa oral de su proyecto final, SmartHome Store, en SQL Server. El tema es
"Triggers de auditoría aplicados al proyecto".

Estructura:
1. Qué es un trigger, la diferencia entre AFTER e INSTEAD OF, las tablas virtuales inserted y deleted,
   y por qué se dispara una vez por sentencia y hay que escribirlo por conjuntos.
2. Cómo se aplicó: la regla RN.14, los cuatro triggers AFTER sobre producto, pedido, compra y factura,
   la técnica del FULL OUTER JOIN entre inserted y deleted para saber si fue INSERT, UPDATE o DELETE,
   y los dos usuarios que se guardan (el empleado por SESSION_CONTEXT y el login con SUSER_SNAME).
   El trigger INSTEAD OF DELETE que impide borrar facturas con el error 50012.
3. Las pruebas: A1 (antes y después del stock), A3 (la auditoría se revierte con la transacción), A4
   (si falla la auditoría, el cambio no se aplica) y A5 (diez filas con un solo UPDATE).
4. Los límites: un administrador puede deshabilitar el trigger y el usuario por defecto cuando la
   aplicación no informa el empleado.
5. Las preguntas difíciles que puede hacer un profesor y cómo responderlas.

Usá solo la información de las fuentes; si algo no está en ellas, no lo inventes. Explicá el código con
palabras, sin leerlo línea por línea. Terminá con un resumen de tres ideas clave para recordar.
```

---

## Tema 4 — Manejo de permisos a nivel de usuarios

**Fuentes:**
- `GUION_DEFENSA.md` y `DEFENSA_TEMAS_TECNICOS.md` (sección Tema 4)
- `docs/etapa-05/seguridad/investigacion.md`
- `sql/tecnico/seguridad/01_permisos_estado_pedido.sql` y `02_usuarios_y_roles.sql`
- PDF de la cátedra: `BDI_U01_guia_lectura` (tema 6, roles) y `BDI_U05_guia_lectura` (Tema 12)

**Prompt:**
```
Hacé un podcast en español rioplatense, de unos 12 minutos, entre dos estudiantes de Bases de Datos I
(UNNE) que preparan la defensa oral de su proyecto final, SmartHome Store, en SQL Server. El tema es
"Manejo de permisos a nivel de usuarios aplicado al proyecto".

Estructura:
1. La diferencia entre login y usuario, el modo de autenticación mixto, GRANT, DENY y REVOKE (DENY gana
   sobre GRANT), los roles fijos db_owner y db_datareader, los roles propios y el principio de mínimo
   privilegio.
2. El encadenamiento de propiedad, explicado con calma: si el procedimiento y las tablas tienen el mismo
   dueño, solo se controla el permiso de ejecutar.
3. Cómo se aplicó: los cuatro usuarios de prueba, el rol que solo lee productos, y el problema de
   negocio resuelto con un DENY sobre la columna estado de pedido, para que la aplicación tenga que
   cancelar con sp_cancelar_pedido, que repone el stock.
4. Las pruebas con EXECUTE AS y REVERT: el usuario de solo lectura no puede modificar (error 229) pero sí
   vender con el procedimiento, y el usuario de la aplicación no puede cambiar el estado (error 230).
5. Los límites (DENY no alcanza a dbo ni sysadmin, contraseñas solo de demostración) y las preguntas
   difíciles que puede hacer un profesor, con sus respuestas.

Usá solo la información de las fuentes; si algo no está en ellas, no lo inventes. Explicá el código con
palabras, sin leerlo línea por línea. Terminá con un resumen de tres ideas clave para recordar.
```

---

## Tema 5 — Optimización de consultas a través de índices

**Fuentes:**
- `GUION_DEFENSA.md` y `DEFENSA_TEMAS_TECNICOS.md` (sección Tema 5)
- `docs/etapa-05/optimizacion_indices/investigacion.md`
- `sql/tecnico/indices/01_carga_masiva.sql` y `02_pruebas_indices.sql`
- PDF de la cátedra: `BDI_U05_SQL_avanzado_OLP` (planes de ejecución y optimizador)

**Prompt:**
```
Hacé un podcast en español rioplatense, de unos 12 minutos, entre dos estudiantes de Bases de Datos I
(UNNE) que preparan la defensa oral de su proyecto final, SmartHome Store, en SQL Server. El tema es
"Optimización de consultas a través de índices aplicada al proyecto".

Estructura:
1. Qué es un índice (árbol B), qué es un heap, la diferencia entre índice agrupado y no agrupado, qué
   hace INCLUDE y qué es un índice cubriente, la diferencia entre Seek y Scan, y el costo de los índices
   en espacio y en escrituras.
2. Por qué se midió en una tabla auxiliar de un millón de ventas y no en las tablas reales, y por qué se
   miden lecturas lógicas y no tiempo.
3. Los tres escenarios con sus números: sin índice, Table Scan con 25.642 lecturas; índice agrupado,
   Clustered Index Seek con 367; no agrupado con INCLUDE, Index Seek con 67. Por qué el cubriente lee
   menos que el agrupado.
4. Por qué no se hizo un agrupado con INCLUDE como pedía la consigna (SQL Server no lo permite), y las
   desventajas del índice cubriente.
5. Las preguntas difíciles que puede hacer un profesor y cómo responderlas.

Usá solo la información de las fuentes; si algo no está en ellas, no lo inventes. Explicá los números
con ejemplos simples. Terminá con un resumen de tres ideas clave para recordar.
```
