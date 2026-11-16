# Guion de defensa: 5 a 7 minutos por tema

> Un guion por tema técnico, para leerlo en voz alta y ensayarlo con el reloj.
> Cada uno tiene entre 550 y 750 palabras: unos 5 minutos hablando, y 6 o 7 con lo que se muestra en pantalla.
> Estructura fija: **apertura → concepto → aplicación al proyecto → demostración → límites y cierre**.
> Los textos entre corchetes `[ ]` son acciones: qué mostrar en pantalla mientras hablás.
> Las líneas son las del repo del proyecto (`main`).

**Cómo ensayar:** leelo una vez entero, después decilo mirando solo los títulos de cada bloque.
Si te pasás de 7 minutos, recortá la demostración, nunca el concepto.

---

## Tema 1 — Procedimientos y funciones almacenadas

### Apertura (20 s)
"Voy a presentar procedimientos y funciones almacenadas, y cómo los usamos en SmartHome Store para
que la venta, el cálculo de precios y el ABM de productos cumplan las reglas de negocio desde la
propia base de datos."

### Concepto (1 min 30 s)
"Los dos son bloques de código T-SQL que quedan guardados en la base y se reutilizan. La diferencia
está en qué pueden hacer.

Una **función** siempre devuelve algo: un valor, si es escalar, o un conjunto de filas, si es una
función de tabla. Se usa dentro de una consulta, por ejemplo en el SELECT o en el WHERE, y **no puede
modificar datos**: no admite INSERT, UPDATE ni transacciones.

Un **procedimiento** se ejecuta con EXEC. Puede modificar datos, abrir y cerrar transacciones, manejar
errores con TRY y CATCH, y devolver valores con parámetros de salida, OUTPUT.

¿Por qué usarlos? Por tres razones. Primero, la regla de negocio queda en un solo lugar: si cambia el
cálculo del precio, se cambia una función y todas las consultas quedan al día. Segundo, rendimiento,
porque el plan de ejecución se compila y se reutiliza. Y tercero, seguridad: se puede dar permiso para
ejecutar un procedimiento sin dar permiso sobre las tablas."

### Aplicación al proyecto (2 min)
"[Mostrar `procedimientos_funciones/scripts.sql`.]

Para el precio hicimos tres funciones encadenadas. `fn_descuento_vigente`, en la línea 32, busca entre
las promociones vigentes de un producto en una fecha la de **mayor descuento**, como pide la RN.24, y
si no hay ninguna devuelve cero gracias a ISNULL. `fn_precio_final`, en la línea 56, toma el precio de
lista, que es neto, le suma el IVA de su alícuota y le aplica ese descuento. Y `fn_total_pedido`, en la
84, calcula el total de un pedido sumando sus renglones, porque por la RN.10 el total no se guarda.

El objeto central es el procedimiento `sp_registrar_venta_completa`, en la línea 119. Recibe el
cliente, el método de pago, la referencia del pago y la lista de productos en un **tipo tabla**, que
definimos en la línea 18; así la venta entera entra en una sola llamada. Devuelve el código del pedido
por un parámetro OUTPUT.

Por dentro hace cinco pasos: valida los datos, con errores propios del 50001 al 50007; controla el
stock bloqueando las filas con UPDLOCK y HOLDLOCK, para que dos ventas no tomen la misma unidad; crea el
pedido copiando la dirección del cliente; inserta el detalle **congelando** el precio y la alícuota, por
la RN.03; y descuenta el stock. Todo dentro de una transacción. Para obtener el código del pedido usa
SCOPE_IDENTITY y no @@IDENTITY, porque el trigger de auditoría inserta en otra tabla y @@IDENTITY
devolvería ese código.

Además hay un ABM de productos: insertar y modificar validan categoría y alícuota antes de tocar la
tabla, y eliminar decide solo: si el producto nunca se vendió ni se compró lo borra, y si tiene
historial hace una baja lógica, poniendo activo en cero."

### Demostración (1 min 30 s)
"[Ejecutar la prueba A1, línea 237.] Acá uso las funciones dentro de un SELECT sobre todos los
productos al 20 de septiembre. La Funda Notebook tenía una promoción del 35 %: su precio de lista neto es
6611,57, con IVA da 8000 y con el descuento queda en 5200. El resto no tenía promoción.

[Ejecutar B1, línea 277.] Ahora una venta de dos auriculares y una funda, dentro de una transacción que
revierto al final para no dejar datos. Se crea el pedido con dos renglones y el stock baja. Y con la
prueba B2, si pido seis lavarropas y hay cinco, el procedimiento lanza el error 50005 y no queda nada a
medias.

[Mostrar la sección 6 de la investigación.] También comparamos eficiencia: insertar 2000 productos con
el procedimiento fue unas 2,8 veces más lento que el INSERT directo, por el costo de cada llamada y de
las validaciones. Es el precio de tener las reglas garantizadas."

### Límites y cierre (40 s)
"Como límite, la comparación de eficiencia se hizo en una sola PC y con pocos datos, y uno de los
resultados fue al revés de la teoría: la función escalar fue más rápida que la subconsulta, algo que
puede deberse a una optimización de SQL Server que no verificamos en el plan.

En resumen: las funciones calculan precio y total de la misma forma en todo el sistema, y el
procedimiento de venta garantiza que un pedido nunca quede incompleto ni venda sin stock."

---

## Tema 2 — Manejo de transacciones

### Apertura (20 s)
"Voy a presentar el manejo de transacciones y cómo garantiza en SmartHome Store que una venta o una
cancelación se hagan completas o no se hagan."

### Concepto (1 min 30 s)
"Una transacción es un grupo de operaciones que se trata como una sola unidad. Cumple las propiedades
**ACID**. Atomicidad: todo o nada. Consistencia: al terminar se cumplen todas las reglas, como el stock
no negativo. Aislamiento: una transacción no ve los cambios a medias de otra. Y durabilidad: después del
COMMIT el cambio queda guardado aunque se caiga el servidor, porque SQL Server lo escribe antes en el
log.

En T-SQL se abre con BEGIN TRANSACTION, se confirma con COMMIT y se deshace con ROLLBACK. Para deshacer
solo una parte existe SAVE TRANSACTION, que marca un punto de guardado. El patrón que usamos siempre es
TRY y CATCH: si algo falla dentro del TRY, el CATCH hace ROLLBACK.

Hay tres variables de control: @@TRANCOUNT, que dice cuántas transacciones hay abiertas; XACT_STATE,
que vale 1 si se puede confirmar, 0 si no hay transacción y menos 1 si quedó condenada; y @@ROWCOUNT,
las filas que afectó la última sentencia."

### Aplicación al proyecto (2 min)
"[Mostrar `transacciones/scripts.sql`.]

En el negocio, la operación crítica es la venta: crear el pedido, sus renglones y bajar el stock. Si
fallara a mitad de camino, quedaría un pedido sin productos o se vendería sin descontar stock.

Las pruebas T1 a T5 lo muestran con el procedimiento de venta: un COMMIT exitoso, un ROLLBACK por stock
insuficiente, la atomicidad cuando falla un renglón, un punto de guardado y una venta dentro de una
transacción que abrió quien la llama.

Después agregamos la **cancelación de pedidos**, el procedimiento `sp_cancelar_pedido` de la línea 257,
por la RN.30. Bloquea el pedido, controla que exista, que no esté ya cancelado, que no tenga factura y
que no esté despachado, cada caso con su error, del 50008 al 50011. Si el pedido estaba confirmado,
devuelve las unidades al stock, y después lo marca como cancelado. Las dos cosas van en la misma
transacción: si fallara la segunda, no queda stock de más.

Las pruebas T7 a T10 escriben la misma venta a mano, sin procedimiento, y T10 hace el contraste: el
mismo error **sin transacción** deja un pedido huérfano, sin renglones."

### Demostración (1 min 30 s)
"[Ejecutar T11, línea 735, y mostrar la pestaña Mensajes.] Un punto que suele confundir es el
anidamiento. SQL Server no tiene transacciones anidadas reales. Abro una transacción externa y el
contador queda en 1; abro una interna y pasa a 2; hago COMMIT de la interna y baja a 1, **pero no
confirmó nada**; hago ROLLBACK de la externa y el insert desaparece. Y en T12 se ve que un ROLLBACK
dentro de la interna deshace todo y deja el contador en cero.

[Ejecutar T13.] Para deshacer solo una parte se usa SAVE TRANSACTION: inserto A, marco un punto, inserto
B, vuelvo al punto y confirmo. Queda solo A.

[Mostrar `06_cancelacion_pedido.png`.] Y en la cancelación, el stock del producto pasa de 40 a 39 con la
venta y vuelve a 40 al cancelar."

### Límites y cierre (40 s)
"El límite principal es que el **aislamiento no lo probamos con dos sesiones simultáneas**. El diseño lo
cubre: el procedimiento bloquea las filas del producto con UPDLOCK y HOLDLOCK, y el CHECK de stock no
negativo es la última barrera.

En resumen: las transacciones hacen que cada operación del negocio deje la base en un estado válido,
y conocer el anidamiento permite combinar procedimientos sin perder ese control."

---

## Tema 3 — Triggers de auditoría

### Apertura (20 s)
"Voy a presentar los triggers de auditoría, que registran automáticamente cada cambio sensible en
SmartHome Store, como pide la regla de negocio 14."

### Concepto (1 min 30 s)
"Un trigger es código que el motor ejecuta solo cuando ocurre un INSERT, un UPDATE o un DELETE sobre una
tabla. Nadie lo llama: se dispara.

Hay dos momentos. **AFTER** se ejecuta después de la sentencia y dentro de su misma transacción.
**INSTEAD OF** se ejecuta en lugar de la sentencia, que entonces no ocurre.

Dentro del trigger existen dos tablas virtuales: **inserted**, con las filas nuevas, y **deleted**, con
las viejas. Un INSERT solo tiene inserted; un DELETE solo deleted; un UPDATE tiene las dos, el antes y
el después.

Algo clave: el trigger se dispara **una vez por sentencia**, no por fila. Si un UPDATE cambia mil
productos, el trigger recibe mil filas, así que hay que escribirlo por conjuntos."

### Aplicación al proyecto (2 min)
"[Mostrar `triggers_auditoria/scripts.sql`.]

La RN.14 dice que los cambios sobre precios, stock, pedidos, compras y facturación quedan registrados.
Creamos cuatro triggers AFTER: producto, pedido, compra y factura, en las líneas 16, 55, 94 y 131.
Todos escriben en la tabla `auditoria` la entidad, la operación, el código del registro, el valor
anterior, el valor nuevo y el usuario.

[Señalar el trigger de producto.] La técnica es un FULL OUTER JOIN entre inserted y deleted por la
clave. Si solo está en deleted fue un DELETE; si solo está en inserted, un INSERT; si está en las dos, un
UPDATE. Con CONCAT se arma el texto del antes y el después, y el WHERE hace que un UPDATE solo se
registre si cambió el precio o el stock.

¿Quién hizo el cambio? Guardamos dos datos. `cod_usuario` es el **empleado**, que la aplicación informa
con SESSION_CONTEXT; si no lo informa, se usa el usuario 1. Y `usuario_bd` es el **login** de SQL Server,
que se completa solo con un DEFAULT SUSER_SNAME().

Además, el trigger de la línea 168 es INSTEAD OF DELETE sobre factura: como una factura es un
comprobante fiscal, reemplaza el borrado por un error 50012 y la factura nunca se borra."

### Demostración (1 min 30 s)
"[Ejecutar A1, línea 200.] Fijo el empleado 3 en la sesión y bajo en uno el stock del producto 2. En la
auditoría aparece una fila UPDATE con 'stock=40' antes y 'stock=39' después, el empleado 3 y mi login.

[Mostrar A3 y A4.] Las pruebas más importantes son estas dos. En A3 hago una venta dentro de una
transacción y la revierto: la auditoría también desaparece, porque el trigger corre en la misma
transacción. En A4 fijo un empleado que no existe: falla la clave foránea de la auditoría y **el UPDATE
del stock tampoco se aplica**. No hay cambio sin auditoría.

[Mostrar A5.] Y en A5 un solo UPDATE sobre los diez productos genera diez filas: está escrito por
conjuntos."

### Límites y cierre (40 s)
"Como límite, alguien con permisos de administrador puede deshabilitar el trigger, y si la aplicación no
informa el empleado el registro queda a nombre del usuario 1; por eso agregamos el login real.

En resumen: la auditoría vive en la base, no depende de la aplicación, y es transaccional: lo que se
registra es exactamente lo que pasó."

---

## Tema 4 — Manejo de permisos a nivel de usuarios

### Apertura (20 s)
"Voy a presentar el manejo de permisos en SQL Server y cómo lo usamos para que cada usuario de SmartHome
Store haga solo lo que le corresponde."

### Concepto (1 min 30 s)
"En SQL Server hay dos niveles. El **login** es del servidor y permite conectarse. El **usuario** es de
cada base: se crea a partir de un login y es quien recibe los permisos. El servidor puede autenticar
solo con Windows o en **modo mixto**, que además acepta logins con usuario y contraseña de SQL Server.

Los permisos se manejan con tres instrucciones. **GRANT** da un permiso. **DENY** lo prohíbe y **gana
sobre cualquier GRANT**, aunque venga de un rol. **REVOKE** quita un permiso dado antes. Se pueden dar
sobre una tabla, sobre columnas puntuales o sobre un procedimiento.

Para no repetir permisos persona por persona se usan **roles**: se dan los permisos al rol y se agregan
usuarios. Hay roles fijos, como db_owner, que puede todo, o db_datareader, que solo lee. Todo esto aplica
el **principio de mínimo privilegio**.

Y hay un concepto clave: el **encadenamiento de propiedad**. Si un procedimiento y las tablas que usa
tienen el mismo dueño, SQL Server solo controla el permiso de ejecutar el procedimiento."

### Aplicación al proyecto (2 min)
"[Mostrar `02_usuarios_y_roles.sql`.]

Creamos cuatro logins con sus usuarios. smarthome_admin está en db_owner. smarthome_lectura está en
db_datareader y además tiene permiso de EXECUTE sobre el procedimiento de venta. Y para probar roles
propios, creamos rol_lectura_producto, que solo puede leer la tabla producto, con un usuario que lo tiene
y otro que no.

[Mostrar `01_permisos_estado_pedido.sql`, líneas 24 a 29.] El caso más interesante resuelve un problema
real del negocio. Si la aplicación pudiera hacer UPDATE pedido SET estado = cancelado, el pedido quedaría
cancelado sin devolver el stock. Entonces el rol de la aplicación puede leer los pedidos y actualizar
**solo las columnas del envío**, tiene un **DENY sobre la columna estado**, y para vender y cancelar
recibe EXECUTE sobre los dos procedimientos. Así está obligada a cancelar con sp_cancelar_pedido, que
repone el stock en la misma transacción."

### Demostración (1 min 30 s)
"[Ejecutar con EXECUTE AS LOGIN.] Para probar sin cambiar de conexión uso EXECUTE AS, que hace que la
sesión actúe con los permisos de otro usuario, y REVERT para volver.

Como smarthome_lectura puedo leer los 12 pedidos. Si intento un UPDATE sobre producto, obtengo el error
**229**, permiso denegado sobre el objeto. Pero si vendo con el procedimiento, **funciona**: se crea el
pedido y baja el stock, aunque no tengo permiso sobre esas tablas. Eso es el encadenamiento de propiedad,
y es a propósito: solo puede cambiar datos como el procedimiento lo permite, con sus validaciones.

[Ejecutar S1.] Como usuario de la aplicación, si intento cambiar el estado de un pedido obtengo el error
**230**, permiso denegado sobre una columna. Y con el rol propio, el usuario que lo tiene lee los diez
productos, el que no lo tiene recibe 229, y el que lo tiene tampoco puede leer pedidos, porque el permiso
es solo sobre producto."

### Límites y cierre (40 s)
"Como límite, un DENY no alcanza al dueño de la base ni a un administrador del servidor, y las
contraseñas del script son solo de demostración: se borran con el script de limpieza.

En resumen: con roles, permisos por columna y procedimientos, cada usuario puede hacer exactamente lo
que su función necesita, y las reglas del negocio no se pueden saltear desde afuera."

---

## Tema 5 — Optimización de consultas a través de índices

### Apertura (20 s)
"Voy a presentar la optimización de consultas con índices, y una medición sobre un millón de ventas para
ver cuánto cambia una búsqueda según el índice que exista."

### Concepto (1 min 30 s)
"Un índice es una estructura ordenada, un árbol B, que permite llegar a las filas buscadas sin leer
toda la tabla, como el índice de un libro.

Una tabla sin índice agrupado se llama **heap**: sus filas no tienen orden, así que para buscar el motor
la recorre entera, un **Table Scan**.

El índice **agrupado** ordena la tabla misma por una columna; por eso hay uno solo por tabla, y la clave
primaria lo crea por defecto. El **no agrupado** es una estructura aparte, con la columna ordenada y un
puntero a la fila; puede haber varios. Con la cláusula **INCLUDE**, un no agrupado guarda columnas extra
en sus hojas; si tiene todas las que pide la consulta es **cubriente** y la responde sin ir a la tabla.

Cuando el motor usa un índice para ir directo al rango, el plan muestra un **Seek**; cuando recorre
todo, un **Scan**. Y los índices tienen un costo: ocupan espacio y cada INSERT, UPDATE o DELETE tiene que
actualizarlos."

### Aplicación al proyecto (2 min)
"[Mostrar `01_carga_masiva.sql`.]

Con los doce pedidos reales cualquier consulta es instantánea, así que para medir creamos una tabla
auxiliar, venta_historica, y le cargamos **un millón de ventas** de 2021 a 2026 con un generador de
números. Los datos salen del número de fila, así que la carga es siempre la misma y se puede repetir. No
usamos la tabla pedido porque ya tiene índice agrupado en su clave y su trigger generaría un millón de
filas de auditoría.

[Mostrar `02_pruebas_indices.sql`.] La consulta es siempre la misma: las ventas de enero de 2025, con un
rango de fecha mayor o igual y menor estricto, que devuelve 14.158 filas. Se ejecuta en tres escenarios:
sin índice, con un índice agrupado por fecha y con un no agrupado por fecha que incluye las columnas
del SELECT. Antes de cada uno se vacía la memoria con DROPCLEANBUFFERS para medir en frío.

Medimos **lecturas lógicas**, las páginas de 8 KB que lee el motor, porque son más confiables que el
tiempo, que depende del equipo."

### Demostración (1 min 30 s)
"[Abrir los tres `.sqlplan` o ejecutar con Ctrl+M y SET STATISTICS IO.]

Sin índice, el plan es un **Table Scan**: lee el millón de filas para devolver 14 mil, **25.642
lecturas**.

Con el índice agrupado por fecha, el plan es un **Clustered Index Seek**: las ventas de enero quedan
juntas y lee **367**, un 98,6 % menos.

Con el no agrupado cubriente, un **Index Seek**: lee **67**, un 99,7 % menos. Lee menos que el agrupado
porque sus hojas guardan solo tres columnas, no la fila entera con la observación larga, así que entran
muchas más filas por página.

Un detalle: la consigna pedía un índice agrupado con INCLUDE, pero SQL Server no lo permite, porque el
agrupado ya contiene todas las columnas. Por eso usamos el no agrupado."

### Límites y cierre (40 s)
"El índice cubriente tiene costos: ocupa unos 33 MB más y solo sirve para esta consulta; si se pide otra
columna, tiene que volver a la tabla por cada fila. Por eso no se indexa todo: se indexan las consultas
frecuentes.

En resumen: el mismo resultado puede costar 25 mil lecturas o 67, según el índice, y elegirlo bien es
la optimización más efectiva que tiene una base de datos."
