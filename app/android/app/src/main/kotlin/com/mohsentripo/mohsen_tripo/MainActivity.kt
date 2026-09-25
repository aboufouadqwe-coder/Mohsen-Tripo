package com.mohsentripo.mohsen_tripo

import android.content.ContentValues
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val mediaChannel = "com.mohsentripo.mohsen_tripo/media"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            mediaChannel,
        ).setMethodCallHandler { call, result ->
            if (call.method != "saveImage" && call.method != "saveModel") {
                result.notImplemented()
                return@setMethodCallHandler
            }

            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
                result.error(
                    "unsupported_android",
                    "Saving generated files requires Android 10 or newer.",
                    null,
                )
                return@setMethodCallHandler
            }

            val bytes = call.argument<ByteArray>("bytes")
            val fileName = call.argument<String>("fileName")
            val mimeType = call.argument<String>("mimeType")

            if (bytes == null || bytes.isEmpty() ||
                fileName.isNullOrBlank() || mimeType.isNullOrBlank()
            ) {
                result.error("invalid_file", "Generated file data is invalid.", null)
                return@setMethodCallHandler
            }

            try {
                val isModel = call.method == "saveModel"
                val collection = if (isModel) {
                    MediaStore.Downloads.EXTERNAL_CONTENT_URI
                } else {
                    MediaStore.Images.Media.EXTERNAL_CONTENT_URI
                }
                val relativePath = if (isModel) {
                    Environment.DIRECTORY_DOWNLOADS + "/Mohsen-Tripo"
                } else {
                    Environment.DIRECTORY_PICTURES + "/Mohsen-Tripo"
                }

                val values = ContentValues().apply {
                    put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
                    put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
                    put(MediaStore.MediaColumns.RELATIVE_PATH, relativePath)
                    put(MediaStore.MediaColumns.IS_PENDING, 1)
                }

                val uri = contentResolver.insert(
                    collection,
                    values,
                ) ?: throw IllegalStateException("MediaStore insert failed.")

                try {
                    contentResolver.openOutputStream(uri)?.use { stream ->
                        stream.write(bytes)
                        stream.flush()
                    } ?: throw IllegalStateException("Unable to open MediaStore output.")
                } catch (error: Throwable) {
                    contentResolver.delete(uri, null, null)
                    throw error
                }

                values.clear()
                values.put(MediaStore.MediaColumns.IS_PENDING, 0)
                contentResolver.update(uri, values, null, null)
                result.success(uri.toString())
            } catch (error: Throwable) {
                result.error(
                    "save_failed",
                    error.message ?: "Unable to save generated file.",
                    null,
                )
            }
        }
    }
}
