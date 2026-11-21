package com.jmeterovic.eterotv

import android.app.UiModeManager
import android.content.ActivityNotFoundException
import android.content.ComponentName
import android.content.Intent
import android.os.SystemClock
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.net.Uri
import android.app.PictureInPictureParams
import android.os.Build
import android.util.Rational
import android.media.MediaMetadata
import android.media.session.MediaSession
import android.media.session.PlaybackState
import androidx.annotation.RequiresApi
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

    // Picture in picture (2.3.0): the own player allows it while a video plays.
    private var pipChannel: MethodChannel? = null
    private var pipAllowed = false
    private var pipRatio = Rational(16, 9)
    private var resumed = false
    private var stopped = false
    private var leftPip = false

    // Headphones' play/pause (2.5.0): they reach a media session, not the screen.
    private var mediaChannel: MethodChannel? = null
    private var session: MediaSession? = null

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
        mediaChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "eterotv/media").apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "update" -> {
                        updateSession(
                            call.argument<Boolean>("open") == true,
                            call.argument<Boolean>("playing") == true,
                            call.argument<String>("title") ?: "",
                        )
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
        pipChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "eterotv/pip").apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "allow" -> {
                        pipAllowed = call.argument<Boolean>("on") == true
                        pipRatio = pipShape(
                            (call.argument<Number>("width") ?: 16).toInt(),
                            (call.argument<Number>("height") ?: 9).toInt(),
                        )
                        applyAutoPip()
                        result.success(pipSupported())
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    /** While the own player is open: a media session that takes the
     *  headphones' buttons (play/pause, the single button of wired ones). */
    private fun updateSession(open: Boolean, playing: Boolean, title: String) {
        if (!open) {
            session?.let {
                it.isActive = false
                it.release()
            }
            session = null
            return
        }
        try {
            val s = session ?: MediaSession(this, "EteroTV").also {
                it.setCallback(object : MediaSession.Callback() {
                    override fun onPlay() { mediaChannel?.invokeMethod("action", "play") }
                    override fun onPause() { mediaChannel?.invokeMethod("action", "pause") }
                    override fun onStop() { mediaChannel?.invokeMethod("action", "pause") }
                })
                session = it
            }
            s.setPlaybackState(
                PlaybackState.Builder()
                    .setActions(
                        PlaybackState.ACTION_PLAY or PlaybackState.ACTION_PAUSE or
                            PlaybackState.ACTION_PLAY_PAUSE or PlaybackState.ACTION_STOP
                    )
                    .setState(
                        if (playing) PlaybackState.STATE_PLAYING else PlaybackState.STATE_PAUSED,
                        PlaybackState.PLAYBACK_POSITION_UNKNOWN,
                        1f,
                    )
                    .build()
            )
            s.setMetadata(MediaMetadata.Builder().putString(MediaMetadata.METADATA_KEY_TITLE, title).build())
            s.isActive = true
        } catch (_: Exception) {
        }
    }

    override fun onDestroy() {
        session?.release()
        session = null
        super.onDestroy()
    }

    private fun pipSupported(): Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)

    /** Android takes shapes between 1:2.39 and 2.39:1 only. */
    private fun pipShape(w: Int, h: Int): Rational {
        if (w <= 0 || h <= 0) return Rational(16, 9)
        val r = w.toDouble() / h
        return when {
            r > 2.39 -> Rational(239, 100)
            r < 1 / 2.39 -> Rational(100, 239)
            else -> Rational(w, h)
        }
    }

    /**
     * Android 12+: the system itself shrinks the video when leaving the app
     * by any way (Home, and also the recent apps button or gesture, which
     * does not call onUserLeaveHint; 2.5.0, Jose).
     */
    private fun applyAutoPip() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S || !pipSupported()) return
        try {
            setPictureInPictureParams(
                PictureInPictureParams.Builder()
                    .setAspectRatio(pipRatio)
                    .setAutoEnterEnabled(pipAllowed && pending == null)
                    .build()
            )
        } catch (_: Exception) {
        }
    }

    /** Home or another app while a video plays: keep it in a small window. */
    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (!pipAllowed || pending != null || !pipSupported()) return
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        // Android 12+ phones shrink it by themselves (auto-enter); doing it
        // here too would run the animation twice. TVs keep doing it here.
        if (isInPictureInPictureMode) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !isTv()) return
        try {
            enterPictureInPictureMode(PictureInPictureParams.Builder().setAspectRatio(pipRatio).build())
        } catch (_: Exception) {
            // Some TVs say they can and then refuse: the video keeps playing behind.
        }
    }

    @RequiresApi(Build.VERSION_CODES.O)
    override fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean, newConfig: Configuration) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        pipChannel?.invokeMethod("changed", isInPictureInPictureMode)
        if (isInPictureInPictureMode || resumed) return
        // Out of the small window without coming back to the app: it was
        // closed. Android may stop the activity before or after telling.
        if (stopped) pipChannel?.invokeMethod("closed", null) else leftPip = true
    }

    override fun onResume() {
        super.onResume()
        resumed = true
        leftPip = false
    }

    override fun onPause() {
        super.onPause()
        resumed = false
    }

    override fun onStart() {
        super.onStart()
        stopped = false
    }

    override fun onStop() {
        super.onStop()
        stopped = true
        if (leftPip) {
            leftPip = false
            pipChannel?.invokeMethod("closed", null)
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
