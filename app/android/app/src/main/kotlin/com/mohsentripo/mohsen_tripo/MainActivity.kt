package com.mohsentripo.mohsen_tripo

import android.content.ContentValues
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.net.HttpURLConnection
import java.net.URL

class MainActivity : FlutterActivity() {
    private val mediaChannel = "com.mohsentripo.mohsen_tripo/media"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            mediaChannel,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "saveImage" -> saveImage(call, result)
                "saveModelFromUrl" -> saveModelFromUrl(call, result)
                else -> result.notImplemented()
            }
        }
    }

    private fun saveImage(
        call: io.flutter.plugin.common.MethodCall,
        result: MethodChannel.Result,
    ) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            result.error(
                "unsupported_android",
                "Saving generated images requires Android 10 or newer.",
                null,
            )
            return
        }

        val bytes = call.argument<ByteArray>("bytes")
        val fileName = call.argument<String>("fileName")
        val mimeType = call.argument<String>("mimeType")

        if (bytes == null || bytes.isEmpty() ||
            fileName.isNullOrBlank() || mimeType.isNullOrBlank()
        ) {
            result.error("invalid_file", "Generated image data is invalid.", null)
            return
        }

        try {
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
                put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
                put(
                    MediaStore.MediaColumns.RELATIVE_PATH,
                    Environment.DIRECTORY_PICTURES + "/Mohsen-Tripo",
                )
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }

            val uri = contentResolver.insert(
                MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
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
                error.message ?: "Unable to save generated image.",
                null,
            )
        }
    }

    private fun saveModelFromUrl(
        call: io.flutter.plugin.common.MethodCall,
        result: MethodChannel.Result,
    ) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            result.error(
                "unsupported_android",
                "Saving generated models requires Android 10 or newer.",
                null,
            )
            return
        }

        val sourceUrl = call.argument<String>("url")
        val fileName = call.argument<String>("fileName")
        val mimeType = call.argument<String>("mimeType")

        if (sourceUrl.isNullOrBlank() ||
            fileName.isNullOrBlank() || mimeType.isNullOrBlank()
        ) {
            result.error("invalid_file", "Generated model URL is invalid.", null)
            return
        }

        Thread {
            var connection: HttpURLConnection? = null
            try {
                connection = URL(sourceUrl).openConnection() as HttpURLConnection
                connection.instanceFollowRedirects = true
                connection.connectTimeout = 15_000
                connection.readTimeout = 120_000
                connection.requestMethod = "GET"
                connection.connect()

                val responseCode = connection.responseCode
                if (responseCode !in 200..299) {
                    throw IllegalStateException(
                        "Model download failed with HTTP $responseCode.",
                    )
                }

                val values = ContentValues().apply {
                    put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
                    put(MediaStore.MediaColumns.MIME_TYPE, "application/octet-stream")
                    put(
                        MediaStore.MediaColumns.RELATIVE_PATH,
                        Environment.DIRECTORY_DOWNLOADS + "/Mohsen-Tripo",
                    )
                    put(MediaStore.MediaColumns.IS_PENDING, 1)
                }

                val uri = contentResolver.insert(
                    MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                    values,
                ) ?: throw IllegalStateException("MediaStore insert failed.")

                try {
                    connection.inputStream.use { input ->
                        contentResolver.openOutputStream(uri)?.use { output ->
                            input.copyTo(output, bufferSize = 128 * 1024)
                            output.flush()
                        } ?: throw IllegalStateException(
                            "Unable to open MediaStore output.",
                        )
                    }
                } catch (error: Throwable) {
                    contentResolver.delete(uri, null, null)
                    throw error
                }

                values.clear()
                values.put(MediaStore.MediaColumns.IS_PENDING, 0)
                contentResolver.update(uri, values, null, null)

                runOnUiThread {
                    result.success(uri.toString())
                }
            } catch (error: Throwable) {
                runOnUiThread {
                    result.error(
                        "save_failed",
                        error.message ?: "Unable to save generated model.",
                        null,
                    )
                }
            } finally {
                connection?.disconnect()
            }
        }.start()
    }
}
