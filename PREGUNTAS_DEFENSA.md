# Preguntas difíciles para la defensa (y cómo responderlas)

> Pensadas para "matarnos": atacan contradicciones aparentes, decisiones discutibles y límites
> del proyecto. Regla general: **no negar el límite, explicar la decisión y el costo**.
> Las líneas son las del repo del proyecto (`main`).

---

## A. Diseño y justificación del modelo

**1. ¿No son demasiadas 22 tablas para una tienda?**
Cada tabla responde a una regla de negocio o a la normalización (decisión 16). Las que parecen
"de más" son catálogos (`provincia`, `localidad`, `alicuota_iva`, `metodo_pago`, `especificacion`)
o tablas intermedias de relaciones N:M (`detalle_pedido`, `detalle_compra`, `promocion_producto`,
`especificacion_producto`). Sacarlas obligaría a repetir datos y volverían las anomalías.

**2. RN.10 dice que el total del pedido no se guarda. ¿Por qué `factura` sí guarda `subtotal`, `iva_total` y `total`?**
Porque son cosas distintas. El pedido calcula su total desde el detalle (`fn_total_pedido`). La
factura es un **comprobante fiscal**: lo que se emitió no puede cambiar nunca, así que se guarda.
Y está controlado: la consulta del comprobante recalcula el total (`total_calculado`) y debe coincidir.

**3. Copian la dirección en el pedido y el precio en el detalle. ¿Eso no es redundancia? ¿No viola la 3FN?**
Es **desnormalización deliberada** (Unidad 4): una foto del momento de la venta (decisiones 7, 9 y 12,
RN.03 y RN.04). No es una dependencia funcional: el precio del renglón **no depende del producto**,
depende del producto **y del momento** en que se vendió. Si se leyera del catálogo, una venta vieja
cambiaría de importe al cambiar un precio.

**4. ¿En qué forma normal está la base?**
En **3FN**, que fue el objetivo y se documentó paso a paso (`docs/etapa-02/normalizacion.md`), tanto
para ventas como para compras. Las copias históricas son a propósito y están justificadas.

**5. ¿Y en FNBC (Boyce-Codd)?**
No hicimos un análisis formal de FNBC. Las tablas tienen como determinantes solo sus claves (las
UNIQUE como `email` o `cuit` también son claves candidatas), así que no detectamos violaciones,
pero lo verificado formalmente es 3FN. (Unidad 4: la 3FN es el estándar porque preserva dependencias.)

**6. ¿Por qué claves subrogadas (`IDENTITY`) y no naturales como el CUIT o el email?**
Porque una clave natural puede cambiar (un email se corrige) y obligaría a actualizar todas las FK.
La subrogada no cambia. Las naturales quedan como **UNIQUE** (`UQ_cliente_email`, `UQ_proveedor_cuit`).

**7. ¿Por qué `alicuota_iva` no tiene `IDENTITY`?**
Porque usamos el código que asigna ARCA a cada alícuota (3 = 0 %, 4 = 10,5 %, 5 = 21 %...),
decisión 13. Facilita integrar la facturación electrónica.

**8. ¿Por qué el cliente se puede registrar sin dirección si RN.01 dice que necesita una?**
RN.01 dice que la necesita **para generar un pedido**, no para registrarse (RN.29 lo aclara). El
procedimiento de venta lo controla: sin dirección da el error 50007.

**9. Una dirección es de un cliente o de un proveedor. ¿Por qué no dos tablas?**
Tienen la misma estructura, y una sola tabla evita repetirla. El `CHECK` (`crear_bd.sql:116`)
garantiza que tenga exactamente un titular.

**10. ¿Cómo garantizan una sola dirección principal?**
Con un **índice único filtrado** (`crear_bd.sql:119`): la unicidad vale solo para `principal = 1`.
Un `UNIQUE` común sobre `cod_cliente` impediría tener más de una dirección. Y si se borra la principal,
el trigger `trg_direccion_principal` (línea 124) marca la más reciente (RN.04).

**11. `pedido` tiene `estado`, `estado_pago` y `estado_envio`. ¿No es confuso?**
Son tres ciclos de vida independientes: el pedido (pendiente/confirmado/cancelado), el pago
(pendiente/aprobado/rechazado) y el envío (NULL hasta pagar, después pendiente/despachado/entregado,
RN.15). Mezclarlos en uno solo obligaría a combinar estados.

**12. `pedido.cod_usuario` acepta NULL. ¿No es un dato incompleto?**
No: es el empleado de depósito que **despacha** el pedido (RN.22). Hasta que se despacha no existe.

---

## B. Restricciones e integridad

**13. ¿Cuándo usaron CASCADE y cuándo NO ACTION? ¿No es peligroso CASCADE?**
CASCADE solo donde el hijo no tiene sentido sin el padre (entidad débil): renglones del pedido y de
la compra, direcciones, multimedia, slides, y las tablas intermedias de promociones y especificaciones. NO ACTION donde borrar perdería historial: no se puede
borrar un cliente con pedidos ni un producto vendido.

**14. ¿Qué diferencia hay entre RESTRICT y NO ACTION?**
Los dos rechazan la operación. RESTRICT controla antes y NO ACTION al final de la sentencia. SQL Server
solo implementa NO ACTION.

**15. ¿Qué pasa si quiero borrar un producto que ya se vendió?**
La FK de `detalle_pedido` lo impide. Por eso `usp_producto_eliminar` hace **baja lógica**
(`activo = 0`) si tiene historial, y borrado físico solo si nunca se vendió ni se compró.

**16. `CHECK (email LIKE '%_@__%.__%')` acepta emails inválidos.**
Sí, es un control de formato mínimo (arroba, punto, dominio). La validación completa le corresponde a
la aplicación (por ejemplo, mandar un correo de verificación). En la base evitamos lo obviamente mal cargado.

**17. ¿Por qué un `UNIQUE` y no otra `PRIMARY KEY`?**
Una tabla tiene una sola PK. `UNIQUE` sirve para las otras claves candidatas. Ojo: en SQL Server,
un `UNIQUE` admite **un solo NULL**.

**18. `CK_pedido_fecha` usa `GETDATE()`. ¿Qué pasa al cargar pedidos viejos?**
Se pueden cargar, porque la fecha es pasada. Lo que impide es registrar una fecha **futura** (RN.16).

---

## C. Consultas (Etapa IV y Unidad 5)

**19. ¿Por qué no pueden usar el alias del SELECT en el WHERE?**
Por el **orden lógico de procesamiento**: el WHERE (paso 4) se evalúa antes que el SELECT (paso 8),
donde nace el alias. En el ORDER BY (paso 10) sí se puede. Se resuelve con una subconsulta o una CTE.

**20. ¿Diferencia entre WHERE y HAVING? ¿Cuál es más eficiente?**
WHERE filtra filas antes de agrupar; HAVING filtra grupos después. WHERE es más eficiente porque reduce
los datos antes de la agregación ("empujar la selección hacia abajo"). HAVING se usa solo para
condiciones sobre agregados.

**21. ¿Por qué `COUNT(DISTINCT p.cod_pedido)` y no `COUNT(*)`?**
Porque el JOIN con `detalle_pedido` repite el pedido una vez por renglón. `COUNT(*)` contaría renglones.

**22. ¿Por qué `NOT EXISTS` y no `NOT IN`?**
Si la subconsulta de un `NOT IN` devuelve un NULL, la comparación da UNKNOWN para todas las filas y el
resultado queda vacío. `NOT EXISTS` no tiene ese problema.

**23. ¿Por qué no `AVG(SUM(...))`?**
SQL Server no permite anidar agregados. Primero se suma por cliente en una tabla derivada y después se
promedia (`consulta_avanzada.sql:9`).

**24. En el reporte, ¿por qué `< DATEADD(DAY, 1, @fecha_hasta)` y no `<= @fecha_hasta`?**
`fecha_pedido` es DATETIME. `'2026-09-30'` significa las 00:00, así que con `<=` se perderían las
ventas del 30 a cualquier hora posterior.

**25. ¿Qué diferencia hay entre una función de ventana y GROUP BY?**
GROUP BY junta varias filas en una. `OVER` mantiene todas las filas y le agrega el cálculo a cada una
(el total acumulado de la factura, `factura_comprobante.sql:57`).

**26. `> ALL` con una categoría que no existe, ¿qué devuelve?**
Todos los productos: "mayor que todos los de una lista vacía" es verdadero. Con `> (SELECT MAX(...))`
no pasa, porque el MAX de nada es NULL. Lo dejamos documentado en la consulta 11.

**27. ¿Por qué no usaron una CTE recursiva para la jerarquía de categorías?**
La jerarquía tiene dos niveles (categoría y subcategoría), y con una autorrelación alcanza
(`reporte_agregado.sql:38`). Con más niveles correspondería una CTE recursiva.

**28. ¿Por qué no usaron vistas?**
La seguridad la resolvimos con procedimientos y permisos por columna. Una vista de solo lectura para
reportes sería una mejora válida: daría acceso a un subconjunto sin permisos sobre las tablas.

---

## D. Tema 1 — Procedimientos y funciones

**29. ¿Por qué la venta es un procedimiento y no una función?**
Porque modifica datos y maneja una transacción. Una función no puede hacer ni INSERT ni UPDATE.

**30. ¿Por qué `SCOPE_IDENTITY()` y no `@@IDENTITY`?**
Porque el trigger de auditoría de `pedido` inserta una fila en `auditoria`: `@@IDENTITY` devolvería
el código de la auditoría y no el del pedido.

**31. ¿Qué es el tipo tabla y por qué READONLY?**
Un tipo que define la forma de una tabla para pasarla como parámetro: la venta recibe todos sus
productos en una llamada. SQL Server exige que los parámetros de tipo tabla sean READONLY.

**32. Midieron que la función escalar fue más rápida que la subconsulta, al revés de la teoría. ¿No está mal la medición?**
Puede ser el *inlining* de funciones escalares de SQL Server 2019 en adelante, que convierte la función
en parte de la consulta. No lo verificamos en el plan, y lo decimos así: con pocas filas y una sola PC
no se puede generalizar.

**33. ¿Y por qué el INSERT directo fue más rápido que el procedimiento?**
Por el costo de cada llamada y de las validaciones (cuatro consultas por alta). A cambio, el
procedimiento garantiza las reglas en un solo lugar y permite no dar permisos sobre la tabla.

---

## E. Tema 2 — Transacciones

**34. ¿SQL Server tiene transacciones anidadas?**
No reales. Un BEGIN dentro de otro solo suma 1 a `@@TRANCOUNT`; el COMMIT interno solo resta 1 y no
confirma nada; un ROLLBACK sin nombre deshace todo. Para deshacer una parte está `SAVE TRANSACTION` (T11 a T13).

**35. ¿Probaron el aislamiento? ¿Qué pasa si dos clientes compran la última unidad a la vez?**
**No lo probamos con dos sesiones simultáneas**, y lo documentamos. El diseño lo cubre: `UPDLOCK, HOLDLOCK`
bloquea las filas del producto hasta el final, así que la segunda venta espera y después ve el stock ya
descontado. Además, el `CHECK (stock >= 0)` es la última barrera.

**36. ¿Qué nivel de aislamiento usan?**
El predeterminado de SQL Server, READ COMMITTED. En la venta lo reforzamos con `HOLDLOCK`, que mantiene
los bloqueos hasta el final de la transacción (comportamiento de SERIALIZABLE sobre esas filas).

**37. ¿Qué pasa sin transacción?**
T10: el mismo error deja un pedido sin renglones (huérfano). Con transacción (T8) no queda nada.

**38. ¿Por qué la venta usa `XACT_ABORT ON` y la compra `OFF`?**
Son dos estrategias. La venta es todo o nada: si falla, se cae también lo del llamador. La compra usa un
punto de guardado para deshacer solo su parte y que el llamador siga, y con `XACT_ABORT ON` la
transacción quedaría condenada (`XACT_STATE = -1`) y no se podría volver al punto.

**39. ¿Qué es la durabilidad y cómo la garantiza SQL Server?**
Después del COMMIT el cambio queda aunque se caiga el servidor, porque se escribe primero en el log de
transacciones.

**40. ¿Pueden hacer ROLLBACK de un CREATE TABLE?**
En SQL Server sí, si está dentro de una transacción explícita. La lectura de DDL de la cátedra lo
presenta como auto-commit, que es lo que pasa en otros motores. Conviene aclararlo si lo preguntan.

---

## F. Tema 3 — Triggers

**41. ¿Por qué un trigger y no hacerlo en la aplicación?**
Queda registrado **cualquier** cambio, también un UPDATE hecho a mano en SSMS (RN.14). Si la auditoría
dependiera de la aplicación, alcanzaría con saltearla.

**42. Si alguien con permisos deshabilita el trigger, ¿la auditoría sirve?**
No: es el límite. Un dbo o sysadmin puede deshabilitarlo. Se mitiga dando esos permisos solo a pocas
personas (mínimo privilegio).

**43. ¿Qué pasa si un UPDATE cambia 1000 filas?**
El trigger se dispara una vez con 1000 filas en `inserted` y `deleted`, y las inserta todas con un solo
`INSERT ... SELECT` (A5 lo prueba con 10).

**44. Si la aplicación no informa el empleado, la auditoría queda a nombre del usuario 1. ¿No es engañoso?**
Es un valor de respaldo para que la auditoría no falle. Por eso agregamos `usuario_bd`, que guarda
siempre el login real (`SUSER_SNAME()`). Lo documentamos como limitación.

**45. ¿Por qué INSTEAD OF para las facturas y no un DENY DELETE?**
DENY no alcanza a dbo ni sysadmin; el trigger frena a todos. Además, INSTEAD OF reemplaza el borrado,
así que no se audita algo que no pasó.

**46. ¿Para qué `TRIGGER_NESTLEVEL() > 1`?**
Para que, si el trigger se dispara desde otro trigger, no audite dos veces ni entre en un ciclo.

---

## G. Tema 4 — Seguridad

**47. Un usuario de solo lectura puede vender. ¿No es un agujero de seguridad?**
Es a propósito: es el **encadenamiento de propiedad**. Puede vender solo a través del procedimiento, con
sus validaciones, y no puede tocar las tablas directamente (U3 y U5 dan error 229). Es la forma
recomendada de dar acceso.

**48. ¿Diferencia entre login y usuario?**
El login es del servidor (permite conectarse); el usuario es de cada base (permite entrar y recibir
permisos). Un usuario se crea `FOR LOGIN`.

**49. ¿Diferencia entre DENY y REVOKE?**
REVOKE quita un permiso dado antes (vuelve a "sin permiso"). DENY lo prohíbe explícitamente y gana
sobre cualquier GRANT, incluso uno heredado de un rol.

**50. ¿Error 229 y 230?**
229: permiso denegado sobre un objeto (la tabla). 230: sobre una columna (`pedido.estado`).

**51. ¿Por qué roles y no permisos a cada usuario?**
Si entra un empleado nuevo se lo agrega al rol en vez de repetir cada permiso, y se aplica el mínimo
privilegio por función (Unidad 1, tema 6).

**52. Las contraseñas están escritas en el script. ¿No es inseguro?**
Son solo para la demostración, se borran con `99_limpieza_usuarios.sql` y está aclarado en el script.
En producción irían fuera del código.

---

## H. Tema 5 — Índices

**53. ¿Por qué probaron en una tabla inventada y no en las tablas reales?**
Con 12 pedidos cualquier consulta es instantánea y no se ve diferencia. Hacía falta volumen (un millón
de filas), y `pedido` ya tiene índice agrupado y un trigger que generaría un millón de auditorías.

**54. ¿Si los índices son tan buenos, por qué no indexar todo?**
Ocupan espacio y cada INSERT, UPDATE y DELETE tiene que actualizarlos. Se indexa lo que se consulta seguido.

**55. ¿Por qué el no agrupado con INCLUDE leyó menos que el agrupado?**
Es cubriente: sus hojas solo tienen las 3 columnas de la consulta, no la fila entera con la observación
larga, así que entran más filas por página.

**56. ¿Desventaja del índice cubriente?**
Solo cubre esa consulta: si se pide otra columna, tiene que ir a la tabla por cada fila (lookup) y la
ventaja se pierde. Además ocupa espacio extra.

**57. ¿Por qué miden lecturas lógicas y no tiempo?**
El tiempo depende del equipo, la memoria y lo que esté corriendo. Las lecturas son las mismas en
cualquier corrida.

**58. ¿Qué índices tiene la base real?**
Los que crean las PK (agrupados) y las UNIQUE, más los dos índices únicos filtrados de `direccion`. No
agregamos índices sobre FK; con más volumen convendría, por ejemplo, en `pedido(cod_cliente)`.

---

## I. Preguntas sobre el trabajo en equipo y el proceso

**59. ¿Qué hizo cada uno?**
Ver `APORTES_ENZO.md` y `APORTES_LICHA.md`. En resumen: Mechi, estructura inicial, DDL original,
consultas avanzadas, ABM y pruebas T7-T16; Licha, base de los temas 1 a 3, carga de datos y reporte
agregado; Enzo, índices, seguridad, cancelación, normalización de la ubicación y comprobante.

**60. ¿Usaron inteligencia artificial?**
Responder con la verdad: sí, como asistente para escribir y revisar scripts y documentación, pero
cada uno ejecutó y verificó los resultados en SSMS y puede explicar su parte. (Enzo lo declaró en su manifiesto.)

**61. Hay cosas repetidas o borradas en el historial (`sql/tecnico/`). ¿Por qué?**
Al principio había versiones duplicadas de algunos objetos; se unificaron en `docs/etapa-05/` para
que cada objeto exista una sola vez.

**62. ¿Qué mejorarían?**
Respuesta honesta y concreta: probar el aislamiento con dos sesiones, agregar devoluciones y notas de
crédito, costo de envío, índices sobre las FK más consultadas y vistas de solo lectura para reportes.

**63. ¿Es un sistema que funciona para un e-commerce real?**
Cubre el circuito principal (catálogo, clientes, pedido, pago, factura, envío, compras, auditoría).
Quedan fuera del alcance las devoluciones y las integraciones externas (pasarela de pago y ARCA).
