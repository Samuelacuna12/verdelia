# Verdélia

Aplicación de ventas, inventario y control financiero interno para fruver y minimarket. Interfaz en español, pesos colombianos y fechas de Colombia. Funciona en PC y como web/app instalada en iPhone.

- Panel: https://verdelia-gestion.universoinvicto.chatgpt.site/#resumen
- Catálogo para clientes: https://verdelia-gestion.universoinvicto.chatgpt.site/#tienda
- Código privado: https://github.com/Samuelacuna12/verdelia

## Uso

1. Activa tu cuenta con el enlace privado entregado al administrador. Usuario: `verdelia`. Define una contraseña y guarda el código de recuperación.
2. En Inventario crea tus productos, categoría, costo, precio, existencias y nivel mínimo. Las compras posteriores actualizan el costo promedio.
3. En Combos crea recetas con ingredientes del inventario: combos de frutas, jugos, salpicón, empanadas u otras preparaciones.
4. Registra ventas cobradas. Cada operación guarda su precio y costo históricos, descuenta existencias y registra el dinero recibido.
5. Los clientes crean pedidos desde el Link de venta y pueden enviar el resumen por WhatsApp. Un pedido pendiente no está pagado ni reserva mercancía. Confirmarlo reserva ingredientes; cobrar y entregar registra la venta y descuenta el inventario.
6. Usa Caja para gastos, aportes, retiros y cierre. Calendario permite abrir un día y consultar ventas, gastos, ganancias, movimientos de dinero e inventario, con sus horas.

Las categorías incluyen frutas, verduras, lácteos, limpieza, golosinas, panadería, arepas y empanadas, jugos, salpicón, bebidas, abarrotes y otras. Se pueden escribir categorías adicionales. Una libra equivale inicialmente a 500 gramos; es configurable.

## Incluido

Ventas por día, canal y medio de pago; recibos para imprimir/PDF y compartir; exportación CSV; devoluciones totales; compras y costo promedio; pérdidas; mínimos y presupuesto de reposición; lotes y avisos de vencimiento; reservas de pedidos; calendario financiero; historial de cambios; íconos, favicon, manifest y accesos rápidos.

En iPhone: instalación desde Safari, enlaces para Atajos/Siri/NFC y archivo de recordatorio diario de cierre. Estos accesos se configuran en el teléfono. Las alertas de inventario y pedidos son dentro del panel. El envío de notificaciones push con la aplicación cerrada todavía requiere integración y permiso del dispositivo.

## Límites claros

- Necesita internet para guardar operaciones; no guarda ventas sin conexión.
- No procesa pagos en línea ni envía WhatsApp automáticamente: el cliente pulsa Enviar en WhatsApp.
- Control contable interno, sin crédito/fiado. Los comprobantes no son factura electrónica.
- Devolución completa por venta; no hay devoluciones parciales en esta versión.
- Las fotos se cargan mediante enlaces HTTPS.
- Recuperación con código privado, sin correos automáticos.
- Los informes consultan hasta un año por rango. La descarga de datos corresponde al período consultado; no sustituye un respaldo integral de la base de datos.

## Estructura y despliegue

`dist/` es el sitio estático, sin compilación ni dependencias de JavaScript externas. `supabase/schema.sql` contiene inventario y contabilidad; `supabase/auth.sql` contiene el acceso independiente. Ejecutar **schema.sql y luego auth.sql**, en ese orden. El segundo archivo repone los permisos de las funciones de acceso después de los permisos restrictivos del primero. La activación inicial se aprovisiona por un administrador de la base de datos, nunca desde el cliente.

La base de datos está en `invicto-ops`, exclusivamente en `verdelia_private`, con cuatro funciones públicas de prefijo `verdelia_`. No usa ni modifica usuarios, perfiles, disparadores ni tablas de Invicto. Las tablas privadas tienen RLS y no conceden lectura directa a roles de API. Cada función administrativa verifica una sesión aleatoria cuya huella se guarda en la base. Los precios, costos, reservas y descuentos de existencias se validan en el servidor dentro de una transacción.

El navegador contiene únicamente la clave publicable de Supabase. No incluir claves de servicio, tokens de sesión, códigos de recuperación ni enlaces de activación en el repositorio. El acceso del administrador se guarda en el navegador por siete días o hasta cerrar sesión. El service worker almacena solo los archivos de la interfaz, nunca respuestas financieras.

Para abrir localmente: `python3 -m http.server 8766 --directory dist`. El sitio se publica con Sites usando `.openai/hosting.json`. GitHub conserva el código privado; no se usa GitHub Pages porque el plan actual no permite Pages para este repositorio privado.

## Verificación

- `node --check dist/app.js`
- `node tests/frontend.cjs`
- `tests/database.sql` y `tests/auth.sql`: pruebas transaccionales con rollback. Ejecutarlas en una copia de pruebas; el script financiero aísla temporalmente las tablas de Verdélia mientras dura la transacción.
- Revisión visual en PC y ancho de iPhone: producto, venta por libras, gasto, calendario diario, catálogo y pedido.

Las comprobaciones no envían mensajes de WhatsApp ni cargan datos de ejemplo en la aplicación publicada.
