package cl.directa.directa_gg_app

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.RecoverableSecurityException
import android.content.ContentUris
import android.content.Context
import android.content.pm.PackageManager
import android.content.ContentValues
import android.content.Intent
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Guarda los PDF y Excel de DIRECTA en una carpeta propia y visible:
 *   Documentos/Directa Gerente General/<Memorias | Informes | Indicadores | ...>
 * También lista, comparte y elimina esos archivos, y mueve los antiguos de Descargas/DIRECTA.
 */
// FlutterFragmentActivity: la necesita local_auth (huella / rostro).
class MainActivity : FlutterFragmentActivity() {
    private val channelName = "directa/downloads"
    private val raiz = "Documents/Directa Gerente General"
    private val legado = "Download/DIRECTA"
    private val canalNotif = "directa_progreso"

    // ------------------------------------------------------------------ notificaciones
    private fun gestorNotif(): NotificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    private fun asegurarCanal() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val canal = NotificationChannel(canalNotif, "Progreso de DIRECTA", NotificationManager.IMPORTANCE_LOW)
            canal.description = "Indexación, análisis y generación de documentos"
            gestorNotif().createNotificationChannel(canal)
        }
    }

    private fun pedirPermisoNotif() {
        if (Build.VERSION.SDK_INT >= 33 &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 4071)
        }
    }

    @Suppress("DEPRECATION")
    private fun notificar(id: Int, titulo: String, texto: String, valor: Int, enCurso: Boolean) {
        asegurarCanal()
        val abrir = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pi = if (abrir != null) PendingIntent.getActivity(
            this, id, abrir, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE) else null
        val b = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) Notification.Builder(this, canalNotif) else Notification.Builder(this)
        b.setSmallIcon(applicationInfo.icon)
            .setContentTitle(titulo)
            .setContentText(texto)
            .setOnlyAlertOnce(true)
            .setOngoing(enCurso)
            .setAutoCancel(!enCurso)
        if (pi != null) b.setContentIntent(pi)
        if (enCurso) b.setProgress(100, valor.coerceIn(0, 100), valor < 0)
        try {
            gestorNotif().notify(id, b.build())
        } catch (_: SecurityException) {
            // Sin permiso de notificaciones: la app sigue mostrando el progreso dentro de la pantalla.
        }
    }

    private fun coleccion(): Uri = MediaStore.Files.getContentUri("external_primary")

    private fun subcarpeta(nombre: String): String {
        val n = nombre.lowercase()
        return when {
            n.startsWith("memoria") -> "Memorias"
            n.contains("indicadores") -> "Indicadores"
            n.contains("comparacion") -> "Comparaciones"
            n.contains("dashboard") || n.contains("plan_de_accion") -> "Dashboard"
            n.contains("reunion") -> "Reuniones"
            n.contains("informe") -> "Informes"
            else -> "Otros"
        }
    }

    private fun limpiarCarpeta(c: String?): String {
        val limpio = (c ?: "").replace(Regex("[^A-Za-z0-9 _\\-áéíóúÁÉÍÓÚñÑ]"), "").trim()
        return if (limpio.isEmpty()) "Otros" else limpio
    }

    @Suppress("DEPRECATION")
    private fun rutaDe(uri: Uri): String? = try {
        contentResolver.query(uri, arrayOf(MediaStore.MediaColumns.DATA), null, null, null)?.use {
            if (it.moveToFirst()) it.getString(0) else null
        }
    } catch (_: Exception) {
        null
    }

    /** Avisa al escáner del archivo concreto (no de toda la carpeta) para que el administrador de archivos lo actualice. */
    private fun refrescar(ruta: String?, mime: String? = null) {
        try {
            contentResolver.notifyChange(coleccion(), null)
            if (ruta != null) MediaScannerConnection.scanFile(this, arrayOf(ruta), if (mime != null) arrayOf(mime) else null, null)
        } catch (_: Exception) {
        }
    }

    /** Ejecuta el trabajo fuera del hilo principal para no congelar la app. */
    private fun segundoPlano(result: MethodChannel.Result, codigo: String, trabajo: () -> Any?) {
        Thread {
            try {
                val r = trabajo()
                runOnUiThread { result.success(r) }
            } catch (e: Exception) {
                runOnUiThread { result.error(codigo, e.message ?: "Operación fallida", null) }
            }
        }.start()
    }

    private fun guardar(nombre: String, mime: String, bytes: ByteArray, carpeta: String): Uri {
        val ruta = "$raiz/$carpeta/"
        // Si ya existe un archivo con ese nombre en la carpeta, se reemplaza (evita "(1)", "(2)"...).
        try {
            contentResolver.query(
                coleccion(), arrayOf(MediaStore.MediaColumns._ID),
                "${MediaStore.MediaColumns.DISPLAY_NAME} = ? AND ${MediaStore.MediaColumns.RELATIVE_PATH} = ?",
                arrayOf(nombre, ruta), null
            )?.use {
                while (it.moveToNext()) {
                    contentResolver.delete(ContentUris.withAppendedId(coleccion(), it.getLong(0)), null, null)
                }
            }
        } catch (_: Exception) {
        }
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, nombre)
            put(MediaStore.MediaColumns.MIME_TYPE, mime)
            put(MediaStore.MediaColumns.RELATIVE_PATH, ruta)
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val uri = contentResolver.insert(coleccion(), values)
            ?: throw IllegalStateException("No se pudo crear el archivo en Documentos")
        contentResolver.openOutputStream(uri)?.use { it.write(bytes) }
            ?: throw IllegalStateException("No se pudo escribir el archivo")
        val listo = ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) }
        contentResolver.update(uri, listo, null, null)
        return uri
    }

    // ------------------------------------------------------------------ borrado con permiso del sistema
    // Un archivo que la app no creó (por ejemplo, de antes de reinstalarla) solo se puede borrar si la
    // persona lo autoriza: Android muestra su propio diálogo "¿Permitir que DIRECTA elimine…?".
    private val reqBorrar = 4201
    private var borradoPendiente: MethodChannel.Result? = null
    private var urisPendientes: List<Uri> = emptyList()

    private fun borrarDirecto(uri: Uri): Boolean {
        val ruta = rutaDe(uri)
        val n = contentResolver.delete(uri, null, null)
        try { if (ruta != null) java.io.File(ruta).takeIf { it.exists() }?.delete() } catch (_: Exception) {}
        refrescar(ruta)
        return n > 0
    }

    private fun borrarConPermiso(uris: List<Uri>, result: MethodChannel.Result) {
        Thread {
            val sinPermiso = mutableListOf<Uri>()
            var intentoQ: android.content.IntentSender? = null
            for (u in uris) {
                try {
                    borrarDirecto(u)
                } catch (e: SecurityException) {
                    sinPermiso.add(u)
                    if (Build.VERSION.SDK_INT == Build.VERSION_CODES.Q && e is RecoverableSecurityException && intentoQ == null) {
                        intentoQ = e.userAction.actionIntent.intentSender
                    }
                } catch (_: Exception) {
                }
            }
            runOnUiThread {
                if (sinPermiso.isEmpty()) {
                    result.success(null)
                    return@runOnUiThread
                }
                try {
                    val sender = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R)
                        MediaStore.createDeleteRequest(contentResolver, sinPermiso).intentSender
                    else intentoQ
                    if (sender == null) {
                        result.error("DELETE_FAILED", "Android no permitió eliminar el archivo", null)
                        return@runOnUiThread
                    }
                    borradoPendiente = result
                    urisPendientes = sinPermiso
                    startIntentSenderForResult(sender, reqBorrar, null, 0, 0, 0)
                } catch (e: Exception) {
                    result.error("DELETE_FAILED", e.message ?: "No se pudo pedir permiso para eliminar", null)
                }
            }
        }.start()
    }

    @Deprecated("Usado por startIntentSenderForResult")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != reqBorrar) return
        val r = borradoPendiente ?: return
        borradoPendiente = null
        if (resultCode != RESULT_OK) {
            r.error("DELETE_CANCELLED", "No se autorizó eliminar el archivo", null)
            return
        }
        val pendientes = urisPendientes
        Thread {
            // En Android 11+ el sistema ya los borró; en Android 10 hay que borrarlos tras el permiso.
            if (Build.VERSION.SDK_INT == Build.VERSION_CODES.Q) {
                for (u in pendientes) try { borrarDirecto(u) } catch (_: Exception) {}
            } else {
                refrescar(null)
            }
            runOnUiThread { r.success(null) }
        }.start()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "directa/notif").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "permiso" -> { pedirPermisoNotif(); result.success(null) }
                    "progreso" -> {
                        notificar(call.argument<Int>("id") ?: 1, call.argument<String>("titulo") ?: "DIRECTA",
                            call.argument<String>("texto") ?: "", call.argument<Int>("valor") ?: -1, true)
                        result.success(null)
                    }
                    "listo" -> {
                        notificar(call.argument<Int>("id") ?: 1, call.argument<String>("titulo") ?: "DIRECTA",
                            call.argument<String>("texto") ?: "", 100, false)
                        result.success(null)
                    }
                    "cerrar" -> { gestorNotif().cancel(call.argument<Int>("id") ?: 1); result.success(null) }
                    "permisoArchivos" -> {
                        // Android 10 a 12: leer archivos guardados antes de reinstalar la app.
                        if (Build.VERSION.SDK_INT in 29..32 &&
                            checkSelfPermission(Manifest.permission.READ_EXTERNAL_STORAGE) != PackageManager.PERMISSION_GRANTED) {
                            requestPermissions(arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE), 4072)
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("NOTIF", e.message, null)
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "list" -> {
                    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
                        result.success(emptyList<Map<String, Any>>())
                        return@setMethodCallHandler
                    }
                    try {
                        val rows = mutableListOf<Map<String, Any>>()
                        val projection = arrayOf(
                            MediaStore.MediaColumns._ID,
                            MediaStore.MediaColumns.DISPLAY_NAME,
                            MediaStore.MediaColumns.SIZE,
                            MediaStore.MediaColumns.DATE_MODIFIED,
                            MediaStore.MediaColumns.MIME_TYPE,
                            MediaStore.MediaColumns.RELATIVE_PATH,
                        )
                        val cursor = contentResolver.query(
                            coleccion(),
                            projection,
                            "${MediaStore.MediaColumns.RELATIVE_PATH} LIKE ? OR ${MediaStore.MediaColumns.RELATIVE_PATH} LIKE ?",
                            arrayOf("$raiz%", "$legado%"),
                            "${MediaStore.MediaColumns.DATE_MODIFIED} DESC",
                        ) ?: throw IllegalStateException("No se pudieron consultar los archivos")
                        cursor.use {
                            val idCol = it.getColumnIndexOrThrow(MediaStore.MediaColumns._ID)
                            val nameCol = it.getColumnIndexOrThrow(MediaStore.MediaColumns.DISPLAY_NAME)
                            val sizeCol = it.getColumnIndexOrThrow(MediaStore.MediaColumns.SIZE)
                            val dateCol = it.getColumnIndexOrThrow(MediaStore.MediaColumns.DATE_MODIFIED)
                            val mimeCol = it.getColumnIndexOrThrow(MediaStore.MediaColumns.MIME_TYPE)
                            val pathCol = it.getColumnIndexOrThrow(MediaStore.MediaColumns.RELATIVE_PATH)
                            while (it.moveToNext()) {
                                val id = it.getLong(idCol)
                                val rel = it.getString(pathCol) ?: ""
                                val carpeta = if (rel.startsWith(raiz)) rel.removePrefix(raiz).trim('/').ifEmpty { "Otros" } else "Descargas (antiguo)"
                                rows.add(mapOf(
                                    "uri" to ContentUris.withAppendedId(coleccion(), id).toString(),
                                    "nombre" to (it.getString(nameCol) ?: "Archivo"),
                                    "bytes" to it.getLong(sizeCol),
                                    "modificado" to it.getLong(dateCol) * 1000,
                                    "mime" to (it.getString(mimeCol) ?: "application/octet-stream"),
                                    "carpeta" to carpeta,
                                ))
                            }
                        }
                        result.success(rows)
                    } catch (e: Exception) {
                        result.error("LIST_FAILED", e.message ?: "No se pudieron leer los archivos", null)
                    }
                }
                "open", "share" -> {
                    try {
                        val uri = Uri.parse(call.argument<String>("uri") ?: throw IllegalArgumentException("Falta la ruta"))
                        val mime = call.argument<String>("mime") ?: "*/*"
                        val action = if (call.method == "open") Intent.ACTION_VIEW else Intent.ACTION_SEND
                        val intent = Intent(action).apply {
                            if (action == Intent.ACTION_VIEW) setDataAndType(uri, mime) else type = mime
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            if (action == Intent.ACTION_SEND) putExtra(Intent.EXTRA_STREAM, uri)
                        }
                        startActivity(Intent.createChooser(intent, if (action == Intent.ACTION_VIEW) "Abrir archivo" else "Compartir archivo"))
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("OPEN_FAILED", e.message ?: "No se pudo abrir el archivo", null)
                    }
                }
                "read" -> {
                    val uri = Uri.parse(call.argument<String>("uri") ?: "")
                    segundoPlano(result, "READ_FAILED") {
                        contentResolver.openInputStream(uri)?.use { it.readBytes() }
                            ?: throw IllegalStateException("No se pudo leer el archivo")
                    }
                }
                "delete", "deleteMany" -> {
                    val uris = if (call.method == "delete") listOf(call.argument<String>("uri") ?: "")
                               else (call.argument<List<String>>("uris") ?: emptyList())
                    borrarConPermiso(uris.filter { it.isNotEmpty() }.map { Uri.parse(it) }, result)
                }
                "save" -> {
                    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
                        result.error("UNAVAILABLE", "Guardar en Documentos requiere Android 10 o superior", null)
                        return@setMethodCallHandler
                    }
                    val name = call.argument<String>("name") ?: "documento"
                    val mime = call.argument<String>("mime") ?: "application/octet-stream"
                    val bytes = call.argument<ByteArray>("bytes")
                    val carpeta = limpiarCarpeta(call.argument<String>("carpeta") ?: subcarpeta(name))
                    segundoPlano(result, "SAVE_FAILED") {
                        val datos = bytes ?: throw IllegalArgumentException("Faltan datos del archivo")
                        val uri = guardar(name, mime, datos, carpeta)
                        refrescar(rutaDe(uri), mime)
                        mapOf("uri" to uri.toString(), "carpeta" to carpeta)
                    }
                }
                "migrate" -> {
                    // Mueve lo que quedó en Descargas/DIRECTA a Documentos/Directa Gerente General/<tipo>.
                    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
                        result.success(0)
                        return@setMethodCallHandler
                    }
                    try {
                        var movidos = 0
                        val pendientes = mutableListOf<Triple<Long, String, String>>()
                        contentResolver.query(
                            coleccion(),
                            arrayOf(MediaStore.MediaColumns._ID, MediaStore.MediaColumns.DISPLAY_NAME, MediaStore.MediaColumns.MIME_TYPE),
                            "${MediaStore.MediaColumns.RELATIVE_PATH} LIKE ?", arrayOf("$legado%"), null
                        )?.use {
                            while (it.moveToNext()) {
                                pendientes.add(Triple(it.getLong(0), it.getString(1) ?: "archivo", it.getString(2) ?: "application/octet-stream"))
                            }
                        }
                        for ((id, nombre, mime) in pendientes) {
                            val origen = ContentUris.withAppendedId(coleccion(), id)
                            try {
                                val datos = contentResolver.openInputStream(origen)?.use { s -> s.readBytes() } ?: continue
                                guardar(nombre, mime, datos, subcarpeta(nombre))
                                contentResolver.delete(origen, null, null)
                                movidos += 1
                            } catch (_: Exception) {
                            }
                        }
                        if (movidos > 0) refrescar(null)
                        result.success(movidos)
                    } catch (e: Exception) {
                        result.error("MIGRATE_FAILED", e.message ?: "No se pudieron mover los archivos", null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
