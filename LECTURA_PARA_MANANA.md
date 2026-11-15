# Qué leer para mañana (en orden)

> Tildá cada ítem a medida que lo leas. Los tiempos están estimados a ritmo de estudio.
> Las rutas `docs/...` y `sql/...` son del repo del proyecto o de este repo (es el mismo contenido).
> Total: unas **4 horas** para la prioridad 1 y 2. La prioridad 3 es solo si sobra tiempo.

---

## PRIORIDAD 1 — Imprescindible (≈ 2 h)

Si solo tenés tiempo para esto, alcanza para defender los cinco temas.

### 1. Los cinco temas técnicos (≈ 50 min)
- [ ] `DEFENSA_TEMAS_TECNICOS.md` — **todo**. Leé en voz alta cada "Qué decir (2 minutos)".

### 2. La investigación de cada tema, solo las partes clave (≈ 40 min)
Leé las secciones **1 (definición)**, **5 (demostración y resultados)** y **Conclusiones**:
- [ ] `docs/etapa-05/procedimientos_funciones/investigacion.md` — secciones 1, 4 (reglas que cumple), 5 y 6 (eficiencia)
- [ ] `docs/etapa-05/transacciones/investigacion.md` — secciones 1, 3 (tabla de `@@TRANCOUNT` y `XACT_STATE`), 5, 6 y 7
- [ ] `docs/etapa-05/triggers_auditoria/investigacion.md` — secciones 1, 3, 5 y 6
- [ ] `docs/etapa-05/seguridad/investigacion.md` — secciones 1, 3, 5 y 6
- [ ] `docs/etapa-05/optimizacion_indices/investigacion.md` — **todo** (es corto y tiene la tabla de lecturas)

### 3. Tus aportes (≈ 15 min)
- [ ] Enzo: `APORTES_ENZO.md`
- [ ] Licha: `APORTES_LICHA.md`

### 4. Las preguntas difíciles (≈ 15 min)
- [ ] `PREGUNTAS_DEFENSA.md` — bloques **D a H** (los cinco temas) y **I** (equipo, IA, mejoras)

---

## PRIORIDAD 2 — Muy recomendable (≈ 1 h 30)

Para cuando pregunten por el proyecto en general o por las etapas anteriores.

### 5. Visión general (≈ 10 min)
- [ ] `README.md` del proyecto — estado, orden de ejecución y estructura
- [ ] `docs/etapa-01/descripcion-caso.md` — el caso (1 minuto)

### 6. Reglas de negocio (≈ 10 min)
- [ ] `docs/etapa-01/reglas-negocio.md` — mínimo las **RN.01, 03, 04, 09, 10, 11, 14, 17, 20, 29 y 30**

### 7. Diseño (≈ 20 min)
- [ ] `docs/etapa-02/decisiones-diseno.md` — decisiones **7, 8, 9, 12, 13, 16 y 17**
- [ ] `docs/etapa-02/normalizacion.md` — secciones **3, 4 y 5** (1FN, 2FN, 3FN) mirando los ejemplos
- [ ] Mirar el DER: `docs/etapa-02/DER/DER.png`

### 8. Implementación (≈ 15 min)
- [ ] `sql/ddl/crear_bd.sql` — recorrerlo con `GUIA_DEFENSA.md`, sección 1, Etapa III (tabla de líneas clave)
- [ ] `docs/etapa-03/pruebas-validacion.md` — solo mirar la tabla de los 52 casos (qué restricción frena cada uno)

### 9. Consultas (≈ 20 min)
- [ ] `GUIA_DEFENSA.md` — sección 1, **Etapa IV** (tabla de consultas y ejemplos de código)
- [ ] `docs/etapa-04/consulta-avanzada.md` — consultas **1, 2, 4, 9 y 11** (las más preguntables)

### 10. Preguntas de diseño (≈ 15 min)
- [ ] `PREGUNTAS_DEFENSA.md` — bloques **A, B y C**

---

## PRIORIDAD 3 — Si sobra tiempo

- [ ] `GUIA_DEFENSA.md` completa (repite lo anterior con más código)
- [ ] `docs/etapa-02/modelo-relacional.md` — tablas y reglas de mapeo
- [ ] `docs/etapa-03/restricciones-integridad.md` — restricciones por tabla
- [ ] `docs/etapa-04/factura-comprobante.md` y `reporte-agregado.md`
- [ ] El código comentado de este repo (`-- >`): `docs/etapa-05/*/scripts.sql`, `sql/tecnico/`

---

## Práctica en SSMS (≈ 30 min, mejor hoy que mañana)

- [ ] Crear y cargar la base: `crear_bd.sql` + `cargar_datos.sql` (controlar: 12 pedidos, stock del producto 2 = 40)
- [ ] Ejecutar los bloques de "Qué mostrar en vivo" de los cinco temas (`DEFENSA_TEMAS_TECNICOS.md`)
- [ ] Abrir los tres `.sqlplan` de índices y ubicar Table Scan, Clustered Index Seek e Index Seek
- [ ] Ejecutar `sql/tecnico/seguridad/99_limpieza_usuarios.sql` y `sql/tecnico/indices/03_limpieza.sql` al terminar

---

## Mañana, antes de entrar (10 min)

- [ ] Releer los cinco "Qué decir (2 minutos)"
- [ ] Repasar los números: **25.642 → 367 → 67** · errores **229/230** · **50005** (stock) · **50012** (factura) · **22 tablas** · **30 RN** · **52 pruebas**
- [ ] Tener SSMS abierto con la base cargada y los scripts a mano
