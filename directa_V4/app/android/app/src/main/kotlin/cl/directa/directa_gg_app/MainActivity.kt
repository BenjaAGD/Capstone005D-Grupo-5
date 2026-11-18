package cl.directa.directa_gg_app

import android.content.ContentUris
import android.content.ContentValues
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "directa/downloads"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
                        )
                        val cursor = contentResolver.query(
                            MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                            projection,
                            "${MediaStore.MediaColumns.RELATIVE_PATH} = ?",
                            arrayOf("Download/DIRECTA/"),
                            "${MediaStore.MediaColumns.DATE_MODIFIED} DESC",
                        ) ?: throw IllegalStateException("No se pudieron consultar las descargas")
                        cursor.use {
                            val idCol = it.getColumnIndexOrThrow(MediaStore.MediaColumns._ID)
                            val nameCol = it.getColumnIndexOrThrow(MediaStore.MediaColumns.DISPLAY_NAME)
                            val sizeCol = it.getColumnIndexOrThrow(MediaStore.MediaColumns.SIZE)
                            val dateCol = it.getColumnIndexOrThrow(MediaStore.MediaColumns.DATE_MODIFIED)
                            val mimeCol = it.getColumnIndexOrThrow(MediaStore.MediaColumns.MIME_TYPE)
                            while (it.moveToNext()) {
                                val id = it.getLong(idCol)
                                rows.add(mapOf(
                                    "uri" to ContentUris.withAppendedId(MediaStore.Downloads.EXTERNAL_CONTENT_URI, id).toString(),
                                    "nombre" to it.getString(nameCol),
                                    "bytes" to it.getLong(sizeCol),
                                    "modificado" to it.getLong(dateCol) * 1000,
                                    "mime" to (it.getString(mimeCol) ?: "application/octet-stream"),
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
                            setDataAndType(uri, mime)
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            if (action == Intent.ACTION_SEND) putExtra(Intent.EXTRA_STREAM, uri)
                        }
                        startActivity(Intent.createChooser(intent, if (action == Intent.ACTION_VIEW) "Abrir archivo" else "Compartir archivo"))
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("OPEN_FAILED", e.message ?: "No se pudo abrir el archivo", null)
                    }
                }
                "delete" -> {
                    try {
                        val uri = Uri.parse(call.argument<String>("uri") ?: throw IllegalArgumentException("Falta la ruta"))
                        val deleted = contentResolver.delete(uri, null, null)
                        if (deleted == 0) throw IllegalStateException("El archivo no existe")
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("DELETE_FAILED", e.message ?: "No se pudo eliminar el archivo", null)
                    }
                }
                "save" -> {
                    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
                        result.error("UNAVAILABLE", "Descargas directas requieren Android 10 o superior", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val name = call.argument<String>("name") ?: "documento"
                        val mime = call.argument<String>("mime") ?: "application/octet-stream"
                        val bytes = call.argument<ByteArray>("bytes") ?: throw IllegalArgumentException("Faltan datos del archivo")
                        val values = ContentValues().apply {
                            put(MediaStore.MediaColumns.DISPLAY_NAME, name)
                            put(MediaStore.MediaColumns.MIME_TYPE, mime)
                            put(MediaStore.MediaColumns.RELATIVE_PATH, "Download/DIRECTA")
                            put(MediaStore.MediaColumns.IS_PENDING, 1)
                        }
                        val uri = contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                            ?: throw IllegalStateException("No se pudo crear el archivo en Descargas")
                        contentResolver.openOutputStream(uri)?.use { it.write(bytes) }
                            ?: throw IllegalStateException("No se pudo escribir el archivo")
                        val ready = ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) }
                        contentResolver.update(uri, ready, null, null)
                        result.success(uri.toString())
                    } catch (e: Exception) {
                        result.error("SAVE_FAILED", e.message ?: "No se pudo guardar el archivo", null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
