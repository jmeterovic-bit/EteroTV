package com.jmeterovic.eterotv

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Opens videos in VLC and hands back where the user stopped.
 *
 * VLC for Android (also on Google TV and Fire TV) accepts the action
 * org.videolan.vlc.player.result: it starts at "position" (ms) and, when the
 * user leaves the player, returns extra_position and extra_duration (ms).
 */
class MainActivity : FlutterActivity() {
    private val vlcRequest = 4242
    private var pending: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "eterotv/vlc")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isInstalled" -> result.success(vlcInstalled())
                    "play" -> play(
                        call.argument<String>("url")!!,
                        call.argument<String>("title") ?: "",
                        (call.argument<Number>("positionMs") ?: 0).toLong(),
                        result,
                    )
                    else -> result.notImplemented()
                }
            }
    }

    /** Asks Android who can open the VLC "result" intent, instead of
     *  looking the package up by name (that failed on Jose's phone). */
    private fun vlcInstalled(): Boolean = try {
        val probe = Intent("org.videolan.vlc.player.result").apply {
            setPackage("org.videolan.vlc")
            setDataAndType(Uri.parse("http://example.com/v.ts"), "video/*")
        }
        packageManager.queryIntentActivities(probe, 0).isNotEmpty() ||
            packageManager.getLaunchIntentForPackage("org.videolan.vlc") != null
    } catch (_: Exception) {
        true // unknown: try to open it anyway
    }

    private fun play(url: String, title: String, positionMs: Long, result: MethodChannel.Result) {
        // A previous launch that never came back: close it with no data.
        pending?.success(null)
        pending = null
        val intent = Intent("org.videolan.vlc.player.result").apply {
            setPackage("org.videolan.vlc")
            setDataAndTypeAndNormalize(Uri.parse(url), "video/*")
            putExtra("title", title)
            if (positionMs > 0) putExtra("position", positionMs)
            // Our position wins over VLC's own "resume" prompt.
            putExtra("from_start", positionMs <= 0)
        }
        try {
            pending = result
            startActivityForResult(intent, vlcRequest)
        } catch (e: ActivityNotFoundException) {
            // Plain "open with VLC" as a second try (no position comes back).
            try {
                startActivityForResult(
                    Intent(Intent.ACTION_VIEW).apply {
                        setPackage("org.videolan.vlc")
                        setDataAndTypeAndNormalize(Uri.parse(url), "video/*")
                    },
                    vlcRequest,
                )
            } catch (e2: ActivityNotFoundException) {
                pending = null
                result.error("no_vlc", "VLC is not installed", null)
            }
        }
    }

    @Suppress("DEPRECATION")
    @Deprecated("startActivityForResult is enough here")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != vlcRequest) return
        val result = pending ?: return
        pending = null
        if (data == null) {
            result.success(null)
            return
        }
        // Read as any number: some VLC versions send Int, others Long.
        val extras = data.extras
        fun num(key: String): Long = (extras?.get(key) as? Number)?.toLong() ?: -1L
        result.success(
            mapOf(
                "positionMs" to num("extra_position"),
                "durationMs" to num("extra_duration"),
            )
        )
    }
}
