# Proyecto 2: Taller Mecánico con Persistencia y Acceso Aleatorio

Programación 2 · 2026-C · Evolución del Proyecto 1 (los datos ahora viven en archivos binarios).

Todo el código está en **un solo archivo: `taller.cpp`**, dividido en 4 partes: constantes y estructuras, **capa de persistencia**, **capa de lógica** y **capa de presentación**.

---

## 1. Compilación y ejecución

```bash
g++ -std=c++17 -Wall -o taller taller.cpp
./taller            # uso normal
./taller --eco      # igual, pero repite en pantalla lo que se lee de un archivo (para las pruebas)
```

* Se necesita **C++17** (se usa `<filesystem>` solo para crear carpetas).
* El programa trabaja con la carpeta `datos/` que está **junto a donde se ejecuta**. Si no existe, la crea.
* Los menús usan caracteres de cuadro (`╔ ═ ║`). En Windows, antes de ejecutar: `chcp 65001`.
* **Primer arranque:** si `datos/taller.bin` no existe, el programa pide los datos del taller. En los siguientes arranques solo lo lee.
* Para volver a correr las pruebas: `bash pruebas/ejecutar_pruebas.sh` (ver sección 9).

---

## 2. Tamaño de las estructuras (`sizeof`) y fórmula de posición

Medidos con g++ 13 en Linux de 64 bits (`time_t` = 8 bytes). En otro compilador pueden variar unos bytes por el relleno (*padding*), pero el programa usa siempre `sizeof`, nunca números fijos.

| Estructura | `sizeof` (bytes) | Archivo |
|---|---:|---|
| `ArchivoHeader` | 16 | (inicio de cada archivo) |
| `Taller` | 360 | `taller.bin` (sin header) |
| `Vehiculo` | 288 | `vehiculos.bin` |
| `Mecanico` | 176 | `mecanicos.bin` |
| `Repuesto` | 208 | `repuestos.bin` |
| `LineaDetalle` | 12 | (dentro de la orden) |
| `OrdenServicio` | 520 | `ordenes.bin` |

**Fórmula de acceso aleatorio** (el registro con índice físico `i` = 0, 1, 2…):

```
posición = sizeof(ArchivoHeader) + i * sizeof(Estructura)
```

Ejemplo real (salida del caso de uso 2): el vehículo ID 5 está en el byte `16 + 4 * 288 = 1168`.

---

## 3. Relación entre ID e índice físico

* Los IDs se asignan en orden de inserción empezando en 1 (`proximoID` del header).
* Los registros **siempre se agregan al final**, **nunca se mueven** y **nunca se borran físicamente**.
* Por eso: **`índice = id - 1`**. En el código está en una sola función: `posicionDeID(tamRegistro, id)`.
* Con esto, buscar por ID es un cálculo + un `seekg` + un `read`; **no se recorre el archivo**.

**¿Qué cambio en el sistema dejaría inválida esa relación?**

1. **Borrar físicamente** un registro y "tapar el hueco" moviendo los siguientes: todos los registros de después cambian de índice y el ID 5 ya no estaría en la posición 4.
2. **Reordenar** el archivo (por ejemplo ordenarlo por placa o por nombre).
3. **Insertar** un registro en el medio, o reusar el ID de un registro eliminado.
4. IDs que no sean consecutivos (por ejemplo IDs aleatorios o con saltos).

(Las búsquedas por otros campos —placa, código, nombre— sí recorren el archivo, con un solo registro en memoria a la vez.)

---

## 4. Diseño del detalle de la orden (sección 3 del enunciado)

### Estructura elegida: arreglo fijo dentro de la orden

```cpp
const int MAX_LINEAS = 20;

struct LineaDetalle {          // sizeof = 12 bytes
    int   idRepuesto;
    int   cantidad;
    float precioUnitario;      // precio histórico
};

struct OrdenServicio {         // sizeof = 520 bytes
    ... campos de la orden ...
    int          numLineas;            // cuántas líneas están en uso
    LineaDetalle lineas[MAX_LINEAS];   // solo las primeras numLineas valen
    ...
};
```

Cómo cumple cada requisito:

| # | Requisito | Cómo se cumple |
|---|---|---|
| 1 | La orden conserva sus líneas entre ejecuciones, con repuesto, cantidad y **precio histórico** | Las líneas son parte del registro y se guardan en `ordenes.bin`. `precioUnitario` se copia al agregar el repuesto. |
| 2 | Admite **al menos 15 líneas** | `MAX_LINEAS = 20`. (Probado con 15 en el caso 4 y con el límite de 20 en el caso 10.) |
| 3 | Todos los registros del archivo miden lo mismo | Siempre `sizeof(OrdenServicio)` = 520 bytes, tenga 0 o 20 líneas. |
| 4 | Consultar las líneas de una orden **no** carga las demás | Un solo `seekg` + `read` trae la orden **con** todas sus líneas. |
| 5 | Se mantienen las reglas del Proyecto 1 | Acumular unidades, quitar la línea completa devolviendo stock, precio histórico (ver abajo). |

### Cuántos bytes ocupa en disco

Como es un arreglo fijo, **ocupa lo mismo siempre**:

| Orden | Bytes en disco | Bytes de líneas usados | Bytes desperdiciados |
|---|---:|---:|---:|
| 1 línea | 520 | 12 | 228 (19 líneas vacías × 12) |
| 15 líneas | 520 | 180 | 60 (5 líneas vacías × 12) |
| 20 líneas (lleno) | 520 | 240 | 0 |

El desperdicio máximo por orden es 240 bytes (cuando no tiene ninguna línea). Para un taller con pocos miles de órdenes es poco; es el precio de mantener el acceso por cálculo.

### Alternativa que consideramos y descartamos

**Un archivo aparte `detalle.bin`** con un registro por línea (`idOrden`, `idRepuesto`, `cantidad`, `precioUnitario`), con su propio header.

Lo descartamos porque:

* Para ver las líneas de una orden habría que **recorrer todo `detalle.bin`** buscando `idOrden` (o armar una lista enlazada con un campo `siguiente`, que complica mucho el código).
* **Quitar una línea** dejaría un hueco en medio del archivo (no se pueden mover registros) o habría que marcarla como eliminada y que el archivo crezca sin parar.
* Hay **un archivo más** que mantener coherente: cada operación sobre la orden escribiría en 3 archivos (órdenes, detalle y repuestos) y aumenta lo que puede quedar mal si el programa se interrumpe. También habría que incluirlo en el backup y en la verificación de integridad.

El arreglo fijo es más simple y más seguro, y su costo (espacio desperdiciado) es pequeño y conocido.

### Cómo resolvemos "quitar una línea"

Función `quitarRepuestoDeOrden` (en la lógica):

1. Se lee la orden (que trae sus líneas) y el repuesto. Se valida que la orden esté ABIERTA y que la línea exista.
2. Se **devuelve el stock** de la línea completa y se guarda el repuesto.
3. Se **corren hacia arriba** las líneas siguientes (`lineas[i] = lineas[i+1]`) para tapar el hueco, se pone en cero la última línea y se hace `numLineas--`.
4. Se guarda la orden completa en su misma posición.

Las líneas quedan siempre juntas al principio del arreglo y la orden no cambia de tamaño ni de posición en el archivo.

---

## 5. Firmas de las funciones

### 5.1 Capa de persistencia (no usa `cin`/`cout` ni reglas de negocio)

Devuelven un `enum Resultado`: `OK` si salió bien, o el **motivo** del fallo.

| Función | Retorno | Qué informa |
|---|---|---|
| `bool inicializarArchivo(const char* ruta)` | `bool` | `true` = archivo listo (existía o se creó con su header). Solo hay una causa de fallo, no se necesita más detalle. |
| `bool leerHeader(const char* ruta, ArchivoHeader &h)` | `bool` | `true` = leído. |
| `bool escribirHeader(const char* ruta, const ArchivoHeader &h)` | `bool` | `true` = escrito. |
| `Resultado guardarX(X &x)` | `Resultado` | `OK` (en `x.id` queda el ID asignado), `ERR_ARCHIVO`, `ERR_ARCHIVO_CORRUPTO` (el header no cuadra con los IDs). |
| `Resultado leerXPorID(int id, X &x)` | `Resultado` | `OK` (entrega el registro **activo o eliminado**), `ERR_NO_EXISTE`, `ERR_ARCHIVO`. |
| `Resultado sobrescribirX(X &x)` | `Resultado` | `OK`, `ERR_NO_EXISTE`, `ERR_ARCHIVO`. Actualiza `fechaUltimaModificacion`. |
| `Resultado marcarXEliminado(int id)` | `Resultado` | `OK`, `ERR_NO_EXISTE`, `ERR_ELIMINADO` (ya estaba eliminado; así no se resta dos veces del header), `ERR_ARCHIVO`. |
| `Resultado contarXActivos(int &cantidad)` | `Resultado` | `OK` o `ERR_ARCHIVO`. Lee solo el header. |

`X` = `Vehiculo`, `Mecanico`, `Repuesto` u `OrdenServicio` (`guardarVehiculo`, `leerMecanicoPorID`, `contarOrdenesActivas`…). Las 5 operaciones están escritas una vez por entidad, como pide el enunciado.

**Por qué `Resultado` y no `bool`:** con un `bool` la presentación no puede saber *por qué* falló (¿no existe? ¿no se pudo abrir el archivo?). Con `Resultado` sí.

**Por qué ninguna función devuelve un puntero:** los datos se entregan **por referencia** (`X &x`): la función llena una copia que el llamador ya tiene. No hay arreglo del sistema en RAM al que apuntar.

### 5.2 Capa de lógica

Patrón: `Resultado nombre(parámetros..., InfoError &info)`. Si falla, `info` trae datos para el mensaje (nombre, placa, ID, cantidades…). Ejemplo: `ERR_STOCK_INSUFICIENTE` deja en `info` el nombre del repuesto, el stock disponible y la cantidad pedida.

**Vehículos**

| Función | Justificación |
|---|---|
| `Resultado agregarVehiculo(Vehiculo &datos, InfoError &info)` | `OK` + `datos.id`; si no: `ERR_PLACA_INVALIDA`, `ERR_PLACA_DUPLICADA`, `ERR_ANIO_INVALIDO`, `ERR_KM_INVALIDO`, `ERR_CEDULA_INVALIDA`, `ERR_CAMPO_VACIO`, `ERR_ARCHIVO`. |
| `Resultado obtenerVehiculoPorID(int id, Vehiculo &v, InfoError &info)` | `OK` solo si está activo; `ERR_VEHICULO_ELIMINADO` (con `v` lleno) para poder decir "fue eliminado" y no "no existe"; `ERR_VEHICULO_NO_EXISTE`. |
| `Resultado obtenerVehiculoPorPlaca(const char* placa, Vehiculo &v, InfoError &info)` | `OK` o `ERR_VEHICULO_NO_EXISTE`. |
| `Resultado buscarVehiculosPorPropietario(const char* sub, Vehiculo res[], int &cantidad, bool &hayMas, InfoError &info)` | Entrega como máximo `MAX_RESULTADOS` (50) en el arreglo que da el llamador; `hayMas = true` avisa que había más. |
| `Resultado listarVehiculos(Vehiculo res[], int &cantidad, bool &hayMas, InfoError &info)` | Igual que la anterior, sin filtro. |
| `Resultado actualizarVehiculo(int id, const Vehiculo &datos, InfoError &info)` | `OK` o los errores de validación / `ERR_VEHICULO_NO_EXISTE` / `ERR_VEHICULO_ELIMINADO`. |
| `Resultado eliminarVehiculo(int id, InfoError &info)` | `ERR_VEHICULO_CON_ORDENES` (con la cantidad de órdenes) distingue el motivo del rechazo. |

**Mecánicos**

| Función | Justificación |
|---|---|
| `Resultado registrarMecanico(Mecanico &datos, InfoError &info)` | `ERR_CEDULA_DUPLICADA`, `ERR_CEDULA_INVALIDA`, `ERR_ESPECIALIDAD_INVALIDA`, `ERR_FECHA_INVALIDA`, `ERR_CAMPO_VACIO`. |
| `Resultado obtenerMecanicoPorID(int id, Mecanico &m, InfoError &info)` | Devuelve `OK` también para un mecánico dado de baja; se distingue con `m.eliminado` (así una orden cerrada puede mostrar su nombre). |
| `Resultado listarMecanicos(MecanicoVista res[], int &cantidad, bool &hayMas, InfoError &info)` | Activos y de baja, cada uno con su cantidad de órdenes ABIERTAS (`MecanicoVista`). |
| `Resultado darDeBajaMecanico(int id, InfoError &info)` | `ERR_MECANICO_CON_ABIERTAS` (con la cantidad), `ERR_MECANICO_ELIMINADO` si ya estaba de baja. |

**Repuestos**

| Función | Justificación |
|---|---|
| `Resultado registrarRepuesto(Repuesto &datos, InfoError &info)` | `ERR_CODIGO_DUPLICADO`, `ERR_PRECIO_INVALIDO`, `ERR_STOCK_INVALIDO`, `ERR_STOCK_MINIMO_INVALIDO`, `ERR_CAMPO_VACIO`. |
| `obtenerRepuestoPorID`, `obtenerRepuestoPorCodigo` | `OK`, `ERR_REPUESTO_NO_EXISTE`, `ERR_REPUESTO_ELIMINADO`. |
| `buscarRepuestosPorNombre`, `listarRepuestos` | Igual patrón que los vehículos (máximo fijo + `hayMas`). La marca BAJO STOCK la calcula la presentación con `stock <= stockMinimo`. |
| `Resultado registrarEntradaMercancia(int id, int cantidad, Repuesto &rep, InfoError &info)` | `ERR_CANTIDAD_INVALIDA`; en `rep` queda el repuesto actualizado para mostrar el nuevo stock. |
| `Resultado cambiarPrecioRepuesto(int id, float precio, Repuesto &rep, InfoError &info)` | `ERR_PRECIO_INVALIDO`. No toca las órdenes (guardan su precio histórico). |
| `Resultado eliminarRepuesto(int id, InfoError &info)` | `ERR_REPUESTO_EN_USO` (en `info` el número de la orden donde aparece). |

**Órdenes de servicio**

| Función | Justificación |
|---|---|
| `Resultado abrirOrden(int idVeh, int idMec, const char* falla, int km, OrdenServicio &creada, InfoError &info)` | `OK` + la orden creada (con su ID). Errores: `ERR_VEHICULO_NO_EXISTE/ELIMINADO`, `ERR_MECANICO_NO_EXISTE/ELIMINADO`, `ERR_KM_MENOR`, `ERR_VEHICULO_YA_TIENE_ABIERTA` (con el número de la orden), `ERR_MECANICO_LLENO`. |
| `Resultado agregarRepuestoAOrden(int idOrden, int idRep, int cantidad, InfoError &info)` | `ERR_ESTADO_INCORRECTO` (con el estado actual), `ERR_STOCK_INSUFICIENTE`, `ERR_LIMITE_LINEAS`, `ERR_CANTIDAD_INVALIDA`, etc. |
| `Resultado quitarRepuestoDeOrden(int idOrden, int idRep, InfoError &info)` | `ERR_LINEA_NO_EXISTE`, `ERR_ESTADO_INCORRECTO`. |
| `Resultado cerrarOrden(int idOrden, float manoObra, InfoError &info)` | `ERR_MANO_OBRA_INVALIDA`, `ERR_ORDEN_VACIA` (sin líneas y sin mano de obra), `ERR_ESTADO_INCORRECTO`. |
| `Resultado anularOrden(int idOrden, InfoError &info)` | `ERR_ESTADO_INCORRECTO` si ya está ANULADA. |
| `float calcularTotalOrden(const OrdenServicio &o)` | Devuelve el número directo: no puede fallar (mano de obra + Σ cantidad × precio histórico). El total **no se guarda**. |
| `Resultado obtenerDetalleOrden(int id, OrdenVista &vista, LineaVista lineas[], InfoError &info)` | La lógica arma `OrdenVista`/`LineaVista` con los **nombres** del vehículo, del mecánico y de cada repuesto, para que la presentación no tenga que abrir archivos. |
| `Resultado listarOrdenes(const char* estado, int idVehiculo, OrdenVista res[], int &cantidad, bool &hayMas, InfoError &info)` | Un solo listado con dos filtros opcionales (`""` = todos los estados, `0` = todos los vehículos): sirve para "listar", "por estado" e "historial de vehículo". |

**Mantenimiento y reportes**

| Función | Justificación |
|---|---|
| `Resultado verificarIntegridad(ReporteIntegridad &rep)` | Llena un resumen con los problemas encontrados (a–e del enunciado) y los contadores de registros verificados. |
| `Resultado crearBackup(char rutaBackup[], int tam)` | Devuelve en `rutaBackup` la carpeta creada para que la presentación la informe. |
| `reporteHistorialVehiculo`, `reporteRepuestosMasUsados`, `reporteFacturacionMecanicos` | Devuelven los datos ya calculados en estructuras (`OrdenVista`, `RepuestoUso`, `FacturacionMecanico`). Los reportes leen los archivos registro por registro; no los cargan completos. |

**Decisiones de reglas que el enunciado no precisaba**

* La cédula de un mecánico es única **entre los activos** (igual que la placa y el código).
* Las búsquedas y listados devuelven máximo `MAX_RESULTADOS = 50`; si hay más, la presentación avisa.
* `MAX_LINEAS = 20` líneas por orden.

---

## 6. Operaciones compuestas: validar todo primero, escribir después

En cada operación que toca más de un archivo (`abrirOrden`, `agregarRepuestoAOrden`, `quitarRepuestoDeOrden`, `cerrarOrden`, `anularOrden`) el código tiene **dos bloques claros**: (1) leer y validar todo; (2) recién entonces escribir. Si algo falla en el bloque 1, **no se escribe nada**.

Orden de las escrituras (bloque 2):

| Operación | 1ª escritura | 2ª escritura |
|---|---|---|
| Abrir orden | `ordenes.bin` (la orden) | `vehiculos.bin` (kilometraje) |
| Agregar repuesto | `ordenes.bin` (la línea) | `repuestos.bin` (stock) |
| Quitar repuesto | `repuestos.bin` (devuelve stock) | `ordenes.bin` (borra la línea) |
| Cerrar orden | `ordenes.bin` | — |
| Anular orden | `ordenes.bin` (estado ANULADA) | `repuestos.bin` (stock de cada línea) |

El criterio: **la orden nunca debe perder la evidencia de lo que se hizo antes de que el efecto esté aplicado**. Esto se explica mejor en la pregunta 2.

---

## 7. Preguntas de análisis

### Pregunta 1
*Escriban con `write` una `OrdenServicio` del Proyecto 1 tal cual (con su `DetalleOrden*`), cierren el programa, vuelvan a ejecutarlo y lean ese registro. ¿Qué observaron al intentar acceder a sus líneas? ¿Por qué ocurre?*

Hicimos el experimento con dos ejecuciones de un programa pequeño (la orden del Proyecto 1 con `DetalleOrden* detalles`):

```cpp
struct DetalleOrden { int idRepuesto; int cantidad; float precioUnitario; };
struct OrdenServicio {
    int id; char estado[12];
    DetalleOrden* detalles; int numDetalles; int capacidadDetalles;
};
// Ejecución 1 ("escribir"): o.detalles = new DetalleOrden[2]; ... f.write((char*)&o, sizeof(o));
// Ejecución 2 ("leer"):     f.read((char*)&o, sizeof(o)); cout << o.detalles[0].cantidad;
```

Resultado real:

```
Escribiendo: detalles apunta a 0x55f1703b02b0 y detalles[0].cantidad = 3
Leido: id=1 estado=ABIERTA numDetalles=1
Leido: detalles apunta a 0x55f1703b02b0
Intentando leer detalles[0].cantidad ...
Segmentation fault      (código de salida 139)
```

**Qué observamos:** los campos simples (`id`, `estado`, `numDetalles`) se recuperan bien, pero al acceder a `detalles[0]` el programa **se cae** (*segmentation fault*).

**Por qué:** `write` copia los bytes de la estructura tal cual. Lo que se guardó en `detalles` es solo **una dirección de memoria** (un número, 8 bytes), no las líneas. Esa dirección pertenecía a la memoria de la ejecución anterior; el sistema operativo la liberó al cerrar el programa. En la nueva ejecución esa dirección no apunta a nada nuestro, así que leerla es acceder a memoria inválida (o, con mala suerte, a basura). Los datos de las líneas nunca llegaron al archivo. Por eso las estructuras en disco no pueden tener punteros, `std::string` ni arreglos dinámicos: deben contener los datos **dentro** de sí mismas, con tamaño fijo.

### Pregunta 2
*Al agregar un repuesto a una orden se escriben el detalle y el stock. Si el programa se interrumpe entre esas dos escrituras, ¿qué inconsistencia queda según el orden que eligieron? ¿Qué orden de escritura deja el daño más fácil de detectar o corregir, y por qué?*

Hay dos órdenes posibles:

| Orden | Si se interrumpe entre las dos escrituras queda… |
|---|---|
| **A) Primero el stock, luego la línea** | El stock ya bajó, pero la orden **no tiene la línea**. Las unidades desaparecieron del inventario y **no hay ningún registro que diga dónde fueron**. |
| **B) Primero la línea, luego el stock** *(el que elegimos)* | La orden **sí tiene la línea**, pero el stock **no se descontó**. El inventario muestra unidades de más. |

**Elegimos B** porque el daño es más fácil de detectar y de corregir: la orden conserva la evidencia (se ve en su detalle que usó ese repuesto y cuántas unidades), así que alguien puede revisar la orden y ajustar el stock a mano (por ejemplo, con una entrada o salida de mercancía). En A el repuesto simplemente "se pierde": el stock está bajo y ninguna orden explica por qué, y ni siquiera se sabe que hubo una interrupción.

Aplicamos el mismo criterio ("no borrar la evidencia antes de aplicar el efecto") en las demás operaciones:

* **Quitar línea:** primero se devuelve el stock y después se borra la línea. Si se corta en medio, la línea sigue visible (evidencia) y solo sobra stock; al revés, se perderían unidades y también la línea que las explicaba.
* **Anular:** primero queda la orden como ANULADA (sus líneas se conservan), después se devuelve el stock de cada línea. Si se corta, hay una orden anulada con sus líneas a la vista y se puede ver qué stock falta devolver.

Aun así, **ninguna combinación es perfecta**: no hay forma de que dos archivos se escriban "a la vez". La solución completa (que no implementamos) sería llevar un registro de operaciones pendientes (*journal*) o una marca "operación en curso" para repetir o deshacer lo que quedó a medias. Lo que sí hacemos es **validar todo antes de la primera escritura**, para que un error normal (stock insuficiente, orden cerrada, etc.) nunca deje nada a medias, y tener `verificarIntegridad()` para detectar los daños que sí son detectables (headers que no cuadran, líneas con repuestos inexistentes, stock negativo).

### Pregunta 3
*En el Proyecto 1 no se podía eliminar un mecánico con órdenes. ¿Qué habría pasado con el historial si se hubiera permitido la eliminación física? ¿Por qué la baja lógica lo resuelve?*

Con eliminación física las órdenes quedarían con un `idMecanico` que **ya no existe**: ¿quién hizo ese trabajo? El historial perdería el nombre del responsable (el reporte de facturación por mecánico no podría mostrarlo y `verificarIntegridad` marcaría la orden como rota). Peor aún: en este proyecto la eliminación física implica **mover los registros siguientes**, y eso rompe la relación `índice = id - 1` (sección 3), así que **otros** mecánicos quedarían con el ID equivocado y todas las órdenes que los referencian apuntarían a la persona incorrecta.

La **baja lógica** (`eliminado = true`) deja el registro en su lugar con todos sus datos. El mecánico dado de baja no puede recibir órdenes nuevas (`ERR_MECANICO_ELIMINADO`), pero sus órdenes CERRADAS y ANULADAS siguen mostrando su nombre (la persistencia entrega también los registros eliminados y la lógica decide qué hacer con ellos). Además se rechaza la baja si tiene órdenes ABIERTAS, para no dejar trabajo sin responsable. Se comprobó en el caso de uso 6.

---

## 8. Estructura de la entrega

```
taller.cpp                     Todo el código fuente (persistencia + lógica + presentación)
README_V2.md                   Este archivo
datos/                         Archivos .bin ya pre-poblados
    taller.bin  vehiculos.bin  mecanicos.bin  repuestos.bin  ordenes.bin
pruebas/                       Entradas y salidas de los casos de uso
    entrada_Na.txt / salida_Na.txt   (una pareja por cada ejecución)
    poblar_datos_entrada.txt   Entrada con la que se generó datos/ usando el propio programa
    ejecutar_pruebas.sh        Script que corre todos los casos
```

**Contenido de `datos/`:** 8 vehículos, 4 mecánicos (uno dado de baja), 12 repuestos (uno en BAJO STOCK) y 10 órdenes: 5 CERRADAS, 3 ABIERTAS y 2 ANULADAS. Las órdenes 1, 3 y 8 tienen 4 o más líneas (4, 5 y 4). Los datos se crearon **usando el propio programa** (`poblar_datos_entrada.txt`), así que el formato es exactamente el que escribe el código. Al ejecutar la verificación de integridad sobre ellos: `SISTEMA ÍNTEGRO`.

---

## 9. Pruebas (carpeta `pruebas/`)

Cada archivo `entrada_*.txt` es lo que se teclea; `salida_*.txt` es lo que muestra el programa (se ejecutó con `--eco` para que se vea lo tecleado). Cuando un caso reinicia el programa hay un archivo por ejecución (`a`, `b`, `c`).

| Caso de uso | Archivos | Datos de partida | Qué se comprueba |
|---|---|---|---|
| 1. Persistencia entre ejecuciones | `1a`, `1b` | `datos/` vacío | 3 vehículos, 2 mecánicos y 4 repuestos siguen ahí, con los mismos IDs, tras reiniciar. |
| 2. Acceso directo por ID | `2a` | `datos/` vacío | Mensaje `[DEBUG]` con el byte leído (ID 5 → byte 1168); el ID 3 eliminado se informa como "fue eliminado". |
| 3. La orden sobrevive con su detalle | `3a`, `3b`, `3c` | pre-poblados | 3 repuestos → reinicio → 4º repuesto + 2 unidades que se acumulan → quitar uno (su stock vuelve: 35 → 36) → cerrar → reinicio → detalle y total correctos (253.00). |
| 4. Orden con 15 líneas | `4a`, `4b` | pre-poblados | 15 repuestos distintos; tras reiniciar siguen las 15 líneas. |
| 5. Anulación con reversión en disco | `5a`, `5b` | pre-poblados | Se anula la orden CERRADA #3 (5 líneas); tras reiniciar el stock coincide con el de antes de la orden. |
| 6. Baja de mecánico e historial | `6a` | pre-poblados | Baja rechazada con órdenes abiertas → se cierran → baja aceptada → sus órdenes siguen mostrando su nombre → orden nueva rechazada. |
| 7. Integridad tras restauración parcial | `7a`, `7b` | pre-poblados | `7a`: integridad OK, backup, vehículo nuevo y orden #11. Entre `7a` y `7b` se reemplaza `datos/vehiculos.bin` por el del backup (lo hace el script). `7b`: `ROTO: Orden #11 apunta al vehiculo ID 9`. |
| 8. Reportes | `8a` | pre-poblados | Los tres reportes; las órdenes abiertas y anuladas no suman (p. ej. Carlos Rojas, que solo tiene órdenes abiertas y anuladas, aparece con 0 órdenes y 0.00). |
| Extra 9. Validaciones y errores | `9a` | pre-poblados | Placa repetida, 2ª orden abierta del vehículo, 4ª orden de un mecánico, km menor, stock insuficiente, modificar orden CERRADA, eliminar vehículo/repuesto en uso y cancelación con `CANCELAR`. |
| Extra 10. Límite de líneas | `10a` | pre-poblados | La línea 21 se rechaza con mensaje claro; la orden queda con 20 líneas. |

**Notas:**

* Las fechas de apertura/cierre y el nombre de la carpeta de backup usan la fecha y hora reales, por eso cambian si se vuelve a ejecutar.
* `bash pruebas/ejecutar_pruebas.sh` ejecuta cada caso en una carpeta de trabajo temporal, así que **no modifica** `datos/`. Si no se tiene `bash`, cada caso se puede correr a mano: copiar `datos/` a una carpeta vacía y ejecutar `./taller --eco < entrada_3a.txt > salida_3a.txt` desde ella (en el caso 7, copiar a mano el `vehiculos.bin` del backup entre `7a` y `7b`).
