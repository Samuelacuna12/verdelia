# Verdélia: funciones y automatizaciones para iPhone

Investigación del 1 de noviembre de 2026. Fuentes oficiales Apple y WebKit. Es una propuesta de implementación: no se han instalado atajos ni activado notificaciones en el teléfono.

## Qué conviene incluir en la primera versión

| Función | Uso en Verdélia | Condición real |
|---|---|---|
| App en pantalla de inicio | Abrir el panel con logo y apariencia independiente de Safari | Publicación HTTPS, manifest e iconos. El usuario añade la web a Inicio. |
| Accesos rápidos | Abrir Nueva venta, Gastos, Ventas de hoy, Cierre o Reposición | Enlaces estables que abren la pantalla correcta después de iniciar sesión. |
| Compartir | Compartir el Link de venta y exportar un comprobante | Acción expresa del usuario; botón Compartir con alternativa Copiar/Descargar. |
| Adjuntar foto | Guardar soporte de compra o gasto desde cámara/galería | Selector de archivo, subida privada con autorización y posibilidad de revisar/eliminar antes de guardar. |
| Comprobante imprimible | Imprimir desde Safari o guardar/compartir el documento | Vista con estilos de impresión; AirPrint si la impresora lo admite. |
| Centro de alertas | Pedidos nuevos, poco inventario, agotados y vencimientos | Funciona dentro de la web sin permisos de iOS. |

WebKit documenta el modo de web/app con manifest y el acceso desde Inicio. La instalación es una acción del usuario, no una acción que la web pueda completar silenciosamente. [Web apps en Inicio](https://webkit.org/blog/13878/web-push-for-web-apps-on-ios-and-ipados/)

## Alertas push: útiles, pero requieren la integración completa

Las web/apps añadidas a Inicio pueden recibir Web Push en iOS 16.4 o posterior. El permiso debe solicitarse como consecuencia de una interacción directa, por ejemplo tocar «Activar avisos en este iPhone». Se pueden mostrar en la pantalla bloqueada y actualizar el contador del icono; el usuario controla permisos y modos de concentración. [WebKit: Web Push y badges](https://webkit.org/blog/13878/web-push-for-web-apps-on-ios-and-ipados/)

Propuesta técnica para Supabase: suscripción por dispositivo vinculada al administrador; claves de envío solo en servidor; función de envío; evento transaccional/outbox con clave de deduplicación; reintentos; eliminación de suscripciones caducadas; service worker que abre la pantalla del pedido. Un interruptor guardado en la base de datos no basta para afirmar que las notificaciones ya funcionan.

Avisos recomendados: pedido nuevo; stock que cruza el mínimo; agotado; vencimiento próximo; cierre de caja pendiente a una hora elegida. Enviar una alerta por transición o resumen, no una cada vez que se consulta el inventario. Mantener importes y datos de clientes fuera del texto visible en la pantalla bloqueada por defecto. El calendario del servidor debe usar `America/Bogota`, sin depender de que el iPhone permanezca abierto.

## Atajos que se configuran una vez en el iPhone

1. **«Venta Verdélia»**: abrir un enlace HTTPS de Nueva venta. Se abre el formulario; no se cobra nada automáticamente.
2. **«Gasto Verdélia»**: abrir Registrar gasto, con el soporte adjunto si se desarrolla un flujo seguro de carga.
3. **«Cómo va Verdélia»**: abrir Ventas de hoy. Una lectura en voz alta de cifras requeriría un endpoint protegido específico; no incluir claves administrativas en un atajo.
4. **«Cerrar Verdélia»**: abrir el cierre de caja. Se puede asociar a una automatización por hora, manteniendo el cierre sujeto al conteo y confirmación del dueño.
5. **«Comprar para Verdélia»**: abrir la lista de reposición y usar Compartir o una exportación para llevarla al proveedor.

Atajos dispone de la acción **Open URLs**, que abre enlaces en Safari. Por ello estos accesos deben funcionar también en Safari, y no se debe prometer que siempre abrirán la instancia instalada de la PWA. [Acciones para abrir URLs](https://support.apple.com/en-gb/guide/shortcuts/apdaf74d75a5/ios)

Una vez creado, un atajo se ejecuta diciendo su nombre a Siri; si abre una app y el equipo está bloqueado puede requerir desbloqueo. [Siri y Atajos](https://support.apple.com/guide/shortcuts/run-shortcuts-with-siri-apd07c25bb38/ios)

El botón Acción puede asignarse a un atajo en modelos compatibles. Para abrir el menú de acciones Verdélia, bastaría un atajo que abra su página de accesos rápidos. [Botón Acción](https://support.apple.com/en-gb/guide/shortcuts/apdfea15680b/ios)

Apple permite disparadores como hora, llegada, salida y NFC. Una etiqueta NFC junto a la caja podría abrir Nueva venta o Cierre, pero necesita configurar la automatización en ese dispositivo; no equivale a escanear etiquetas NFC arbitrarias desde la web. [Automatizaciones personales](https://support.apple.com/en-euro/guide/shortcuts/apdfbdbd7123/10.0/ios/27)

La URL `shortcuts://run-shortcut?name=...` solo ejecuta un atajo que ya existe en la colección del usuario. No instala una automatización. [URL scheme de Atajos](https://support.apple.com/en-ie/guide/shortcuts/apd624386f42/10.0/ios/27)

## Compartir, cámara e impresión

**Compartir desde Verdélia:** `navigator.share` para texto/enlaces y, cuando se admita, archivos; detectar compatibilidad y ofrecer Copiar/Descargar. Si la web está en un iframe de otro origen, el contenedor necesita permitir `web-share`. [Web Share](https://webkit.org/blog/13708/allowing-web-share-on-third-party-sites/)

**Compartir hacia Verdélia:** no prometer que una PWA aparecerá automáticamente como destino nativo en iPhone. La opción comprobada es un atajo con «Mostrar en hoja para compartir», configurado para recibir imágenes/PDFs. Requiere una integración de carga autenticada adicional si se desea guardar el soporte directamente. [Atajos desde otras apps](https://support.apple.com/en-gb/guide/shortcuts/apd163eb9f95/ios), [Tipos de entrada](https://support.apple.com/en-gb/guide/shortcuts/apd7644168e1/ios)

**Foto del soporte:** implementar un selector de imagen con opción de cámara y galería, mostrando vista previa. Safari documenta el flujo de tomar foto/video en una subida de archivos; probarlo en el iPhone real antes de afirmar compatibilidad completa. No añadir OCR contable automático sin revisión humana de monto, fecha y proveedor. [Notas de Safari 26.2](https://developer.apple.com/documentation/safari-release-notes/safari-26_2-release-notes)

**Impresión:** AirPrint necesita impresora compatible y conexión a la misma red que el iPhone. La interfaz de impresión requiere elegir impresora y confirmar. Una térmica Bluetooth genérica puede necesitar la app o integración del fabricante; no asumir impresión directa desde la PWA. [Apple: AirPrint](https://support.apple.com/es-es/109349)

## Cómo mostrarlo en Ajustes

Separar estados verificables: «Disponible en la web», «Requiere configurar este iPhone», «Permiso denegado» y «Integración pendiente». No mostrar «Activado» hasta comprobar suscripción push o configuración real. Botones recomendados: Abrir acceso, Copiar enlace, Ver instrucciones, Activar avisos y Enviar aviso de prueba. La prueba de push se limita al dispositivo del administrador y debe registrar el resultado.

La primera entrega puede ofrecer accesos rápidos, compartir, impresión y alertas dentro del panel. Push debe considerarse completo únicamente después de probar una notificación con la web cerrada en el iPhone; los atajos se instalan/configuran posteriormente con el usuario.
