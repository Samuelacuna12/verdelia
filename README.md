# Verdélia

Aplicación de ventas, inventario y control financiero interno para fruver y minimarket. Interfaz en español, pesos colombianos y fechas de Colombia. Funciona en PC y como web/app instalada en iPhone.

- Panel en GitHub Pages: https://samuelacuna12.github.io/verdelia/#resumen
- Catálogo para clientes: https://samuelacuna12.github.io/verdelia/#tienda
- Estado: publicado en GitHub Pages. El enlace anterior de Sites redirige a la nueva dirección.
- Código: https://github.com/Samuelacuna12/verdelia

## Uso

1. Activa tu cuenta con el enlace privado entregado al administrador. Usuario: `verdelia`. Define una contraseña y guarda el código de recuperación.
2. En Inventario crea tus productos, categoría, Precio costo, Precio venta, Kilos disponibles (u otra medida) y nivel mínimo. Precio venta sugerido ofrece aumentos de 30%, 40%, 50% o un porcentaje personalizado sobre el costo, siempre con edición manual. Puedes ingresar costo y venta por kilo, libra o gramo; el servidor los convierte. Editar permite corregir costos y cantidades con motivo e historial, sin reescribir ventas anteriores. Las compras posteriores actualizan el costo promedio. La medida base se puede corregir antes de tener operaciones o recetas; después se conserva para proteger los movimientos históricos.
3. En Combos crea recetas con ingredientes del inventario: combos de frutas, jugos, salpicón, empanadas u otras preparaciones.
4. Registra ventas cobradas. Cada operación guarda su precio y costo históricos, descuenta existencias y registra el dinero recibido.
5. Los clientes crean pedidos desde el Link de venta y pueden enviar el resumen por WhatsApp. Un pedido pendiente no está pagado ni reserva mercancía. Confirmarlo reserva ingredientes; cobrar y entregar registra la venta y descuenta el inventario.
6. Usa Caja para gastos, aportes, retiros y cierre. Calendario permite abrir un día y consultar ventas, gastos, ganancias, movimientos de dinero e inventario, con sus horas.

El selector muestra frutas, verduras, minimarket, lácteos, limpieza, golosinas, panadería, arepas y empanadas, jugos, salpicón, bebidas, abarrotes, congelados y otras. Crear otra categoría permite añadir una propia. El catálogo muestra también categorías sin productos publicados y explica su estado vacío. Una libra equivale inicialmente a 500 gramos; es configurable.

## Incluido

Ventas por día, canal y medio de pago; recibos para imprimir/PDF y compartir; exportación CSV; devoluciones totales; compras y costo promedio; pérdidas; mínimos y presupuesto de reposición; lotes y avisos de vencimiento; reservas de pedidos; calendario financiero; historial de cambios; íconos, favicon, manifest y accesos rápidos.

En iPhone: instalación desde Safari, enlaces para Atajos/Siri/NFC y archivo de recordatorio diario de cierre. Estos accesos se configuran en el teléfono. Las notificaciones push de pedidos nuevos y niveles bajos o agotados ya tienen servicio de envío. Activa cada dispositivo desde Ajustes → Notificaciones. En iPhone: iOS 16.4+, instalada en pantalla de inicio y permiso aceptado. Prueba con Enviar prueba. No se puede aceptar el permiso a distancia; los modos de concentración y conexión del teléfono afectan la entrega. Los vencimientos siguen siendo alertas dentro del panel.

## Límites claros

- Necesita internet para guardar operaciones; no guarda ventas sin conexión.
- No procesa pagos en línea ni envía WhatsApp automáticamente: el cliente pulsa Enviar en WhatsApp.
- Control contable interno, sin crédito/fiado. Los comprobantes no son factura electrónica.
- Devolución completa por venta; no hay devoluciones parciales en esta versión.
- Las fotos se cargan mediante enlaces HTTPS.
- Recuperación con código privado, sin correos automáticos.
- Los informes consultan hasta un año por rango. Exportar período conserva el rango consultado. Los respaldos automáticos completos son independientes de ese filtro y se descargan desde Ajustes → Respaldos automáticos.

## Estructura y despliegue

`dist/` es el sitio estático, sin compilación ni dependencias de JavaScript externas. `supabase/schema.sql` contiene inventario y contabilidad; `supabase/auth.sql` contiene el acceso independiente. Ejecutar **schema.sql y luego auth.sql**, en ese orden. El segundo archivo repone los permisos de las funciones de acceso después de los permisos restrictivos del primero. La activación inicial se aprovisiona por un administrador de la base de datos, nunca desde el cliente.

La base de datos está en `invicto-ops`, exclusivamente en `verdelia_private`, con funciones públicas de prefijo `verdelia_` que verifican la sesión o restringen su ejecución al servidor. No usa ni modifica usuarios, perfiles, disparadores ni tablas de Invicto. Las tablas privadas tienen RLS y no conceden lectura directa a roles de API. Cada función administrativa verifica una sesión aleatoria cuya huella se guarda en la base. Los precios, costos, reservas y descuentos de existencias se validan en el servidor dentro de una transacción.

El navegador contiene únicamente la clave publicable de Supabase. No incluir claves de servicio, tokens de sesión, códigos de recuperación ni enlaces de activación en el repositorio. El acceso del administrador se guarda en el navegador por siete días o hasta cerrar sesión. El service worker almacena solo los archivos de la interfaz, nunca respuestas financieras.

Para abrir localmente: `python3 -m http.server 8766 --directory dist`. GitHub Pages publica únicamente el contenido de `dist/`, copiado a la raíz de la rama `gh-pages`, con el archivo `.nojekyll`. En Settings → Pages se selecciona `gh-pages` y `/ (root)`. Las rutas, íconos y accesos rápidos son relativos a `/verdelia/`. El alojamiento anterior de Sites conserva únicamente una redirección. No se publican tablas ni datos de Supabase en la web. El repositorio es público por autorización del propietario para habilitar Pages; los permisos de acceso a la base de datos siguen siendo independientes. Al actualizar la aplicación, sincronizar la rama `gh-pages` con `dist/` después de ejecutar las verificaciones.

## Verificación

- `node --check dist/app.js`
- `node tests/frontend.cjs`
- `node tests/hosting.cjs`
- `tests/database.sql` y `tests/auth.sql`: pruebas transaccionales con rollback. Ejecutarlas en una copia de pruebas; el script financiero aísla temporalmente las tablas de Verdélia mientras dura la transacción.
- Revisión visual en PC y ancho de iPhone: producto, venta por libras, gasto, calendario diario, catálogo y pedido.

Las comprobaciones no envían mensajes de WhatsApp ni cargan datos de ejemplo en la aplicación publicada.


## Automatizaciones publicadas

- `supabase/automation.sql`: tablas privadas, cola de notificaciones, funciones y dos trabajos de Cron exclusivos de Verdélia.
- `supabase/functions/verdelia-automation/index.ts`: envío Web Push con VAPID, respaldo comprimido y descarga autenticada. Dependencias con versiones exactas.
- `supabase/product-edit.sql`: actualización de la función administrativa para instalaciones existentes, preservando permisos y cuentas.
- `supabase/restore-backup.sql`: recuperación en un esquema nuevo para inspección. Solo accesible al propietario de la base.
- Instalar en una base nueva: schema.sql → auth.sql → automation.sql → restore-backup.sql; desplegar la función. No volver a aplicar schema.sql solo: revoca los permisos privados que auth.sql y automation.sql restauran.

### Respaldos

Diariamente a las **02:00 America/Bogota (07:00 UTC)** se crea una copia JSON comprimida en el bucket privado `verdelia-backups`. Incluye los 13 conjuntos de datos del negocio y sus contadores, sin filtros de fecha. Excluye contraseñas, recuperación, sesiones y credenciales push. El código y los esquemas están versionados en GitHub; las fotos por URL no se descargan.

Cada copia se descarga de nuevo y se verifican SHA-256, descompresión y cantidades de filas antes de marcarla completa. Hay tres intentos con reintento a los cinco minutos. Se eliminan copias de más de 30 días únicamente después de verificar una nueva. Una copia no puede exceder 50 MB comprimidos. No es un respaldo independiente de la cuenta/proyecto Supabase: para cubrir su eliminación, descarga otra copia fuera del proveedor. El programador necesita el proyecto activo. No se contrató almacenamiento externo ni un plan nuevo.

Para recuperar: descargar una copia desde el panel, descomprimirla y revisar su versión. Un administrador de base de datos carga el JSON mediante parámetros y ejecuta `verdelia_private.restore_backup_to_schema(payload, 'verdelia_restore_revision')`. La función crea un esquema privado nuevo, conserva identificadores, verifica tipos, restricciones, relaciones y conteos, y repone contadores. Revisar el resultado antes de decidir sustituir datos actuales. Nunca modifica Invicto ni restaura cuentas o sesiones; el reemplazo de datos actuales debe autorizarse por separado. La prueba de recuperación crea este esquema dentro de una transacción con rollback.

### Notificaciones

Pedidos: evento transaccional después de guardar el pedido. Inventario: revisión cada minuto, aviso al pasar al mínimo o a cero, incluyendo existencias reservadas. Reposición normal permite una nueva alerta si vuelve a bajar. No se envía un aviso cada minuto por el mismo estado. Las preferencias del panel controlan ambos canales.

Cada dispositivo requiere autorización explícita. El servidor registra sus claves públicas de suscripción y usa una clave VAPID privada en Vault. El secreto del programador también vive en Vault. La función HTTP valida ese secreto en el servidor; su descarga valida la sesión de Verdélia. No hay secretos en el navegador o repositorio. Se permiten solo endpoints de Apple, Google y Mozilla, sin redirecciones a destinos proporcionados por el usuario.

Los envíos tienen cola, bloqueo temporal, hasta cinco intentos y vencen a las 24 horas. HTTP 404/410 desactiva suscripciones vencidas. El navegador muestra siempre una notificación visible; al pulsarla abre Pedidos o Reposición dentro de `/verdelia/`. Cerrar sesión desactiva los avisos de ese dispositivo cuando hay conexión. No se envían mensajes de WhatsApp automáticamente.

Pruebas adicionales: `node tests/push-worker.cjs` y `tests/product-automation.sql` (fixtures propias con rollback, sin vaciar tablas reales). La visualización móvil se comprueba con datos locales de prueba; no sustituye una prueba de recepción en un iPhone autorizado.
