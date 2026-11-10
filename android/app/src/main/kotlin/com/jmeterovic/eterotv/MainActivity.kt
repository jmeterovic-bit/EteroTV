package com.jmeterovic.eterotv

import android.app.UiModeManager
import android.content.ActivityNotFoundException
import android.content.ComponentName
import android.content.Intent
import android.os.SystemClock
import android.content.pm.PackageManager
import android.content.res.Configuration
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
                    "isTv" -> result.success(isTv())
                    "deviceName" -> result.success(
                        android.provider.Settings.Global.getString(contentResolver, "device_name")
                            ?: android.os.Build.MODEL
                    )
                    "play" -> play(
                        call.argument<String>("url")!!,
                        call.argument<String>("title") ?: "",
                        (call.argument<Number>("positionMs") ?: 0).toLong(),
                        call.argument<String>("player") ?: "vlc",
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

    /** Google TV, Android TV and Fire TV: sign in to Google with a code. */
    private fun isTv(): Boolean {
        val ui = getSystemService(UI_MODE_SERVICE) as? UiModeManager
        return ui?.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION ||
            packageManager.hasSystemFeature(PackageManager.FEATURE_LEANBACK) ||
            packageManager.hasSystemFeature("amazon.hardware.fire_tv")
    }

    private fun play(url: String, title: String, positionMs: Long, player: String, result: MethodChannel.Result) {
        // A previous launch that never came back: close it with no data.
        pending?.success(null)
        pending = null
        tried.clear()
        playerFailed = false
        val uri = Uri.parse(url)
        fun MutableList<Pair<String, Intent>>.attempt(name: String, build: Intent.() -> Unit) =
            add(name to Intent().apply(build).apply {
                setDataAndTypeAndNormalize(uri, "video/*")
                putExtra("title", title)
                if (positionMs > 0) putExtra("position", positionMs)
                // Our position wins over VLC's own "resume" memory.
                putExtra("from_start", positionMs <= 0)
            })
        // 1. Straight to VLC's player: only that screen hands the position
        //    back. Going through VLC's start screen returns at once, empty.
        // 2. The documented "result" action. 3. Plain "open with VLC".
        val tries = mutableListOf<Pair<String, Intent>>()
        if (player != "vlc") {
            // Just Player and MX Player: the "MX Player" interface. They start
            // at "position" (ms, an Int) and, with return_result, hand back
            // "position" and "duration" (ms) when the user leaves.
            val packages = if (player == "mx") {
                listOf("com.mxtech.videoplayer.pro", "com.mxtech.videoplayer.ad")
            } else {
                listOf("com.brouken.player")
            }
            for (pkg in packages) {
                tries.add(pkg to Intent(Intent.ACTION_VIEW).apply {
                    setPackage(pkg)
                    setDataAndTypeAndNormalize(uri, "video/*")
                    putExtra("title", title)
                    putExtra("return_result", true)
                    if (positionMs > 0) putExtra("position", positionMs.toInt())
                })
            }
            queue = tries
            pending = result
            if (!launchNext()) {
                pending = null
                result.error("no_vlc", "player is not installed", null)
            }
            return
        }
        tries.attempt("player") {
            action = Intent.ACTION_VIEW
            component = ComponentName("org.videolan.vlc", "org.videolan.vlc.gui.video.VideoPlayerActivity")
        }
        tries.attempt("result") {
            action = "org.videolan.vlc.player.result"
            setPackage("org.videolan.vlc")
        }
        tries.attempt("view") {
            action = Intent.ACTION_VIEW
            setPackage("org.videolan.vlc")
        }
        // On a device where VLC's player already closed at once, skip it.
        if (prefs.getBoolean("skipPlayer", false)) tries.removeAt(0)
        queue = tries
        pending = result
        if (!launchNext()) {
            pending = null
            result.error("no_vlc", "VLC is not installed", null)
        }
    }

    /** The ways still left to try for the current video. */
    private var queue = mutableListOf<Pair<String, Intent>>()
    private var launchedAt = 0L
    private val prefs by lazy { getSharedPreferences("eterotv_vlc", MODE_PRIVATE) }
    private val tried = mutableListOf<String>()
    private var playerFailed = false

    private fun launchNext(): Boolean {
        while (queue.isNotEmpty()) {
            val (name, intent) = queue.removeAt(0)
            try {
                tried.add(name)
                launchedAt = SystemClock.elapsedRealtime()
                startActivityForResult(intent, vlcRequest)
                return true
            } catch (e: ActivityNotFoundException) {
            } catch (e: SecurityException) {
            }
        }
        return false
    }

    @Suppress("DEPRECATION")
    @Deprecated("startActivityForResult is enough here")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != vlcRequest) return
        val result = pending ?: return
        // Some VLC versions (seen on a Sony Google TV) close the player at
        // once, with nothing: then try the next way to open it, and remember.
        // (VLC can take a while to give up on a stream, so 15 s.)
        val quick = SystemClock.elapsedRealtime() - launchedAt < 15000
        val other = tried.lastOrNull()?.contains('.') == true // Just Player / MX Player
        val failed = data == null && quick && !other
        if (failed && tried.lastOrNull() == "player") playerFailed = true
        // The player failed and another way worked: skip the player from now on
        // on this device (not when the stream itself fails everywhere).
        if (!failed && playerFailed && tried.lastOrNull() != "player") {
            prefs.edit().putBoolean("skipPlayer", true).apply()
        }
        if (failed && launchNext()) return
        pending = null
        // Read as any number: some VLC versions send Int, others Long.
        val extras = data?.extras
        fun num(key: String): Long = (extras?.get(key) as? Number)?.toLong() ?: -1L
        var position = num("extra_position")
        var duration = num("extra_duration")
        if (other) {
            duration = num("duration")
            // Watched to the end: MX-style players say so instead of a position.
            position = if (extras?.getString("end_by") == "playback_completion" && duration > 0) {
                duration
            } else {
                num("position")
            }
        }
        result.success(
            mapOf(
                "positionMs" to position,
                "durationMs" to duration,
                // Only for the "VLC did not say" message: never values (the URL has the password).
                "info" to "${tried.joinToString("→")}, código $resultCode, " +
                    (if (data == null) "sin datos" else "datos: " + (extras?.keySet()?.sorted()?.joinToString() ?: "ninguno")),
            )
        )
    }
}
