package com.ollagitana.music

import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "com.ollagitana.music/intents"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Abrir una URL en una app concreta (p. ej. la app de Songsterr).
        // Devuelve true si se lanzó; false si no está instalada o no acepta el enlace.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openInApp" -> {
                        val url = call.argument<String>("url")
                        val targetPackage = call.argument<String>("package")
                        if (url.isNullOrEmpty() || targetPackage.isNullOrEmpty()) {
                            result.success("none")
                            return@setMethodCallHandler
                        }

                        // 1) Probar la URL de la web en varias formas: la app puede
                        //    declarar el host sin "www" (los intent filters no
                        //    casan www.songsterr.com con songsterr.com).
                        val parsed = Uri.parse(url)
                        val candidates = mutableListOf(parsed)
                        val host = parsed.host
                        if (host != null && host.startsWith("www.")) {
                            candidates.add(
                                parsed.buildUpon()
                                    .authority(host.removePrefix("www."))
                                    .build()
                            )
                        }
                        val songId = parsed.getQueryParameter("id")
                        if (!songId.isNullOrEmpty()) {
                            candidates.add(Uri.parse("songsterr://song?id=$songId"))
                            candidates.add(Uri.parse("songsterr://song/$songId"))
                        }

                        for (uri in candidates) {
                            try {
                                val intent = Intent(Intent.ACTION_VIEW, uri).apply {
                                    setPackage(targetPackage)
                                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                }
                                startActivity(intent)
                                result.success("song")
                                return@setMethodCallHandler
                            } catch (_: Exception) {
                                // probar la siguiente variante
                            }
                        }

                        // 2) La app no acepta enlaces: abrirla igualmente.
                        //    Dart copia el título al portapapeles para buscarlo.
                        val launch = packageManager.getLaunchIntentForPackage(targetPackage)
                        if (launch != null) {
                            try {
                                launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                startActivity(launch)
                                result.success("app")
                                return@setMethodCallHandler
                            } catch (_: Exception) {
                                // sin app
                            }
                        }

                        result.success("none")
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
