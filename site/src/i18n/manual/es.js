// Manual de uso (español). El texto sigue el de la propia app (Localization/strings.json).
export default {
  title: 'Manual de uso',
  description: 'Cómo usar Channel Timeline Viewer: añadir un canal, ordenar, marcar vistos, reanudar, notas y Pro, tanto en iPhone como en Android.',
  lede: 'Channel Timeline Viewer ordena las subidas de un canal de las más antiguas a las más recientes para que las veas por orden sin perder de vista hasta dónde llegaste. Aquí se explica cada función paso a paso.',
  platformNote: 'Usa los botones de arriba para cambiar entre la versión de iPhone y la de Android. Casi todos los pasos son iguales: solo cambian los que difieren.',
  badges: { ios: 'iPhone', android: 'Android' },
  pickerLabel: 'Elige tu dispositivo',
  // Google Play で公開されたら（config.js の PLAY_STORE_URL が入ったら）、
  // 1章の Google Play の項目をこちらに差し替える。
  androidStorePublished: { title: 'Instalar desde Google Play', body: 'Busca «Channel Timeline Viewer» en Google Play o usa el botón de Google Play de este sitio.' },
  tocTitle: 'Contenido',
  sections: [
    {
      id: 'install',
      title: '1. Conseguir la app',
      body: 'La app es gratuita. No hay que crear cuenta ni iniciar sesión.',
      steps: [
        { title: 'Instalar desde el App Store', body: 'Requiere iOS 17 o posterior. Busca «Channel Timeline Viewer» en el App Store o usa el botón del App Store de este sitio.', only: 'ios' },
        { title: 'Próximamente en Google Play', body: 'La versión para Android está enviada a Google Play y a la espera de revisión. En cuanto se publique aparecerá el enlace en este sitio.', only: 'android', id: 'store-android' },
        { title: 'No hace falta cuenta de YouTube', body: 'Nunca inicias sesión. La app solo lee información pública de los vídeos mediante la API oficial de YouTube.' },
      ],
    },
    {
      id: 'add',
      title: '2. Añadir un canal',
      body: 'Hay dos maneras de añadir un canal y ambas llevan al mismo sitio.',
      steps: [
        { title: 'Pegar una URL', body: 'En la primera pantalla, escribe la URL del canal (por ejemplo youtube.com/@handle o youtube.com/channel/UC…) en el campo «URL del canal» y toca «Obtener vídeos». También sirve la URL de un vídeo: la app localiza el canal que lo publicó.' },
        { title: 'Los canales grandes tardan', body: 'La primera carga recupera todas las subidas, así que cuantos más vídeos tenga el canal, más tardará. Espera mientras se muestre «Cargando vídeos...».' },
        { title: 'Compartir desde YouTube', body: 'Toca el botón de compartir en la app de YouTube o en Safari y elige «Abrir en Channel Timeline». iOS no permite que una hoja para compartir abra una app directamente, así que permite las notificaciones y toca la que aparece justo después de compartir. Si prefieres no hacerlo, abre la app y toca «Abrir el enlace compartido».', only: 'ios' },
        { title: 'Ponerlo al principio de la hoja para compartir', body: 'El orden lo decide iOS, no la app. Desliza la fila de apps hasta el final → «Más» → «Editar» → toca el «+» junto a «Abrir en Channel Timeline» → arrástralo arriba del todo → «OK».', only: 'ios' },
        { title: 'Compartir desde YouTube', body: 'Toca el botón de compartir en la app de YouTube o en el navegador y elige «Abrir en Channel Timeline»: la lista de vídeos del canal se abre directamente, sin permiso de notificaciones.', only: 'android' },
        { title: 'Los canales se conservan', body: 'Los canales que has abierto aparecen en «Canales recientes». La próxima vez se abren al instante y las novedades se comprueban después.' },
      ],
    },
    {
      id: 'list',
      title: '3. Usar la lista de vídeos',
      body: 'El progreso está en la parte superior de la lista. Es el centro de todo.',
      steps: [
        { title: 'Progreso y «siguiente»', body: 'Arriba se ve «Progreso» con los vídeos vistos, el total y el porcentaje. La fila de debajo es el siguiente vídeo: «Continuar: n.º N» si dejaste uno a medias, o «Siguiente: n.º N». Tócala para empezar ahí.' },
        { title: 'Ordenar', body: 'Con el icono de arriba a la derecha → «Ordenar» → «Más antiguos primero» o «Más recientes primero». Por defecto, más antiguos primero.' },
        { title: 'Filtrar', body: 'En el mismo menú, «Mostrar» permite elegir «Todos», «Solo no vistos» o «Solo vistos». Al filtrar aparece «N mostrados / N en total».' },
        { title: 'Traer novedades', body: 'El mismo menú incluye «Buscar vídeos nuevos», que trae solo lo nuevo. Si algo se ve mal, «Recargar todo» vuelve a obtener la lista completa.' },
        { title: 'Marcar visto u omitido', body: 'En cada fila puedes alternar «Visto», «Marcar como no visto», «Omitir» y «No omitir». Los vídeos omitidos se saltan en la reproducción automática, pero se abren con normalidad desde el botón «Siguiente».' },
      ],
    },
    {
      id: 'play',
      title: '4. Reproducir',
      body: 'La reproducción usa el reproductor incrustado oficial de YouTube. Los controles están debajo.',
      steps: [
        { title: 'Reproducción automática (desactivada por defecto)', body: 'Se controla con el interruptor de la pantalla del reproductor. Activada, muestra «Reproducción automática activada: sigue con el siguiente vídeo» y solo reproduce el siguiente vídeo de la lista abierta; nunca te lleva a vídeos relacionados ni a otro canal. Desactivada, la reproducción se detiene y aparece el botón «Reproducir siguiente».' },
        { title: 'Reproducir solo no vistos', body: 'Es el interruptor de debajo. Activado, también se saltan los vídeos ya vistos y solo se reproducen los pendientes.' },
        { title: 'Repetir', body: 'La insignia de arriba a la derecha alterna «Desactivado → Uno → Todos». «Uno» repite el mismo vídeo independientemente de la reproducción automática. «Todos» vuelve al primero al terminar el último (con la reproducción automática activada).' },
        { title: 'Desplazarse', body: 'Cinco botones: «Primero», «Anterior», «Deshacer», «Siguiente» y «Último». «Deshacer» revierte el último salto y te devuelve al vídeo y la posición donde estabas, útil si te equivocas de botón.' },
        { title: 'Reanudar', body: 'Al reabrir un vídeo que dejaste a medias, continúa en el segundo exacto y se indica «Reanudando desde (0:00)». Para verlo desde el principio, toca «Reiniciar» al lado.' },
      ],
    },
    {
      id: 'tools',
      title: '5. Notas y ajustes de reproducción',
      steps: [
        { title: 'Escribir notas', body: 'Bajo el reproductor hay un campo «Notas (para series y estudio)» que se guarda solo mientras escribes. Toca fuera o «OK» para terminar. Las notas se guardan por vídeo.' },
        { title: 'Velocidad y subtítulos', body: 'El icono del control deslizante, arriba a la derecha, abre los ajustes de reproducción para cambiar velocidad y subtítulos. Los subtítulos empiezan desactivados. La lista de subtítulos solo se prepara al iniciar la reproducción: si está vacía, empieza el vídeo y vuelve a abrirla.' },
        { title: 'Sobre la calidad', body: 'YouTube ajusta la calidad automáticamente según la conexión y el reproductor oficial no permite que la app la fije. Para elegirla tú, empieza la reproducción y usa el botón de pantalla completa abajo a la derecha → rueda dentada → Calidad.' },
        { title: 'Abrir en YouTube', body: '«Abrir en YouTube» abre el vídeo en la app o el sitio de YouTube. Úsalo con los vídeos cuyo autor ha bloqueado la reproducción fuera de YouTube.' },
      ],
    },
    {
      id: 'fullscreen',
      title: '6. Ver a pantalla completa',
      steps: [
        { title: 'Pasar a pantalla completa', body: 'Toca el botón de pantalla completa abajo a la derecha del reproductor. Gira el teléfono para ocupar toda la pantalla.', only: 'ios' },
        { title: 'Seguir a pantalla completa entre vídeos', body: 'Desde la versión 1.1, con la reproducción automática activada, el siguiente vídeo continúa a pantalla completa. Para conseguirlo, la app cambia unos 0,5 segundos antes de que termine el vídeo.', only: 'ios' },
        { title: 'Pasar a pantalla completa', body: 'Toca el botón de pantalla completa abajo a la derecha del reproductor. La pantalla gira sola y ocupa todo el espacio.', only: 'android' },
        { title: 'Seguir a pantalla completa entre vídeos', body: 'Con la reproducción automática activada, el siguiente vídeo continúa a pantalla completa. Para conseguirlo, la app cambia unos 0,5 segundos antes de que termine el vídeo.', only: 'android' },
        { title: 'Salir de la pantalla completa', body: 'Pulsa Atrás para cerrar solo la pantalla completa: la pantalla del reproductor sigue abierta.', only: 'android' },
      ],
    },
    {
      id: 'pro',
      title: '7. Canales guardados y Pro',
      body: 'La app es gratuita y guarda un canal. Dentro de ese canal no se recorta nada.',
      steps: [
        { title: 'Qué incluye la versión gratuita', body: 'Orden del más antiguo o del más reciente, control de vistos, reanudar, botones de salto, notas, progreso y reproducción en el reproductor oficial, todo sin límites.' },
        { title: 'Al añadir un segundo canal', body: 'Aparece una confirmación. Si eliges «Sustituir», se borran el historial, el progreso y las notas del canal guardado, y no se puede deshacer. Para conservar ambos, valora Pro.' },
        { title: 'Pro (compra única)', body: 'No es una suscripción: se paga una vez. Guarda varios canales y conserva el historial, el progreso y las notas de cada uno. El precio es el que muestre la tienda.' },
        { title: 'Restaurar la compra', body: 'Tras reinstalar o cambiar de dispositivo, abre la pantalla de Pro y toca «Restaurar compra». Si has iniciado sesión con la misma cuenta de Apple, se recupera. Es un pago único, así que nunca se cobra dos veces.', only: 'ios' },
        { title: 'Restaurar la compra', body: 'Tras reinstalar o cambiar de dispositivo, abre la pantalla de Pro y toca «Restaurar compra». Si has iniciado sesión con la misma cuenta de Google, se recupera. Es un pago único, así que nunca se cobra dos veces.', only: 'android' },
        { title: 'Quitar un canal', body: 'Desliza hacia la izquierda una fila de «Canales recientes» para eliminarla. Al hacerlo también se borran el historial, el progreso y las notas de ese canal.', only: 'ios' },
        { title: 'Quitar un canal', body: 'Usa el botón de la papelera en «Canales recientes». Al quitarlo también se borran el historial, el progreso y las notas de ese canal.', only: 'android' },
      ],
    },
    {
      id: 'trouble',
      title: '8. Si algo no funciona',
      steps: [
        { title: 'No acepta la URL del canal', body: 'Usa la URL de la página del canal (youtube.com/@handle, youtube.com/channel/UC…). También sirve la de un vídeo.' },
        { title: 'La lista se detiene o da error', body: 'Los canales muy grandes tardan en la primera carga. Si el error menciona la cuota, inténtalo más tarde: la API de YouTube tiene un límite diario.' },
        { title: 'Un vídeo no se reproduce', body: 'Algunos vídeos tienen restringida la reproducción fuera de YouTube por su autor. En esos casos usa «Abrir en YouTube».' },
        { title: 'Compartir no abre la app', body: 'iOS no permite que una hoja para compartir abra una app directamente. Permite las notificaciones y toca la que aparece justo después de compartir, o abre la app y usa «Abrir el enlace compartido».', only: 'ios' },
        { title: 'El volumen cambia de un vídeo a otro', body: 'Viene del nivel de grabación de los propios vídeos y la app no puede igualarlo. El «Volumen estable» de YouTube no está disponible en reproductores incrustados, así que usa «Abrir en YouTube» cuando te moleste.' },
        { title: 'He perdido mi progreso', body: 'El historial, el progreso y las notas se guardan solo en tu dispositivo. Se borran al eliminar la app o al borrar o sustituir un canal, y no se pueden recuperar.' },
      ],
    },
    {
      id: 'limits',
      title: '9. Lo que la app no hace a propósito',
      body: 'Para respetar los términos de servicio de YouTube, la app nunca hace lo siguiente.',
      steps: [
        { title: 'No descarga ni guarda sin conexión', body: 'No existe forma de almacenar un vídeo en el dispositivo.' },
        { title: 'No usa un reproductor propio', body: 'La reproducción siempre ocurre en el reproductor incrustado oficial de YouTube.' },
        { title: 'No bloquea anuncios ni elude restricciones', body: 'No oculta la publicidad ni evita ninguna restricción de reproducción.' },
        { title: 'No reproduce en segundo plano', body: 'La reproducción se detiene al salir de la app. Mientras se reproduce, la pantalla solo se mantiene encendida.' },
        { title: 'Nada sale de tu dispositivo', body: 'Historial, progreso, notas y posiciones de reproducción se guardan solo en tu dispositivo y nunca se envían a nuestros servidores.' },
      ],
    },
  ],
};
