package tech.hoppin.hoppin_rider

import android.media.AudioManager
import android.media.ToneGenerator
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// FlutterFragmentActivity, not FlutterActivity: the Stripe SDK hosts its
// card UI in fragments and refuses to attach to a plain Activity.
class MainActivity : FlutterFragmentActivity() {
    private var tones: ToneGenerator? = null
    private val handler = Handler(Looper.getMainLooper())
    private var cadence: Runnable? = null

    // Call-progress tones for in-app calls: the ringback a caller hears while
    // the other phone rings, and the busy beeps when nobody picks up. Played on
    // the voice-call stream, so they follow the call's audio (earpiece, or the
    // speaker when the call is on speaker).
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "tech.hoppin/call_tones")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "ringback" -> { ringback(); result.success(null) }
                    "busy" -> { busy(); result.success(null) }
                    "stop" -> { stopTones(); result.success(null) }
                    else -> result.notImplemented()
                }
            }
    }

    // UK ringback, "brr-brr ... brr-brr": two 0.4 s bursts 0.2 s apart, then
    // 2 s of silence, repeated until stopped. Android's own ringing tone is
    // 1 s on / 4 s off, which a caller whose call is answered within a few
    // seconds barely hears at all.
    private fun ringback() {
        stopTones()
        val gen = newGenerator() ?: return
        val steps = longArrayOf(400, 200, 400, 2000) // on, off, on, off
        var i = 0
        val step = object : Runnable {
            override fun run() {
                if (tones !== gen) return
                if (i % 2 == 0) gen.startTone(ToneGenerator.TONE_SUP_DIAL, steps[i].toInt())
                val wait = steps[i]
                i = (i + 1) % steps.size
                handler.postDelayed(this, wait)
            }
        }
        cadence = step
        handler.post(step)
    }

    private fun busy() {
        stopTones()
        val gen = newGenerator() ?: return
        gen.startTone(ToneGenerator.TONE_SUP_BUSY, 1500)
        handler.postDelayed({ if (tones === gen) stopTones() }, 1600L)
    }

    private fun newGenerator(): ToneGenerator? {
        val gen = try {
            ToneGenerator(AudioManager.STREAM_VOICE_CALL, ToneGenerator.MAX_VOLUME)
        } catch (e: RuntimeException) {
            null // no tone beats a crashed call
        }
        tones = gen
        return gen
    }

    private fun stopTones() {
        cadence?.let { handler.removeCallbacks(it) }
        cadence = null
        tones?.stopTone()
        tones?.release()
        tones = null
    }

    override fun onDestroy() {
        stopTones()
        super.onDestroy()
    }
}
