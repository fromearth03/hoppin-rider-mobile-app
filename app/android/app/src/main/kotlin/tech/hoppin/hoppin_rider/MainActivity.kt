package tech.hoppin.hoppin_rider

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioDeviceInfo
import android.telecom.CallAudioState
import com.hiennv.flutter_callkit_incoming.CallkitConnection
import android.media.AudioManager
import android.media.Ringtone
import android.media.RingtoneManager
import android.media.ToneGenerator
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
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
    private var ringtone: Ringtone? = null
    private var vibrator: Vibrator? = null

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
                    "ring" -> { ring(); result.success(null) }
                    "speaker" -> {
                        setSpeaker(call.argument<String>("callId"), call.argument<Boolean>("on") ?: false)
                        result.success(null)
                    }
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

    // An incoming call while the app is open: the phone's own ringtone and a
    // ring-like vibration, started the moment the call arrives. Silent mode
    // is respected (no sound, no vibration); vibrate mode only vibrates.
    private fun ring() {
        stopTones()
        val audio = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val mode = audio.ringerMode
        if (mode == AudioManager.RINGER_MODE_SILENT) return
        if (mode == AudioManager.RINGER_MODE_NORMAL) {
            try {
                val uri = RingtoneManager.getActualDefaultRingtoneUri(this, RingtoneManager.TYPE_RINGTONE)
                    ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
                ringtone = RingtoneManager.getRingtone(this, uri)?.apply {
                    audioAttributes = AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) isLooping = true
                    play()
                }
            } catch (e: RuntimeException) {
                ringtone = null
            }
        }
        vibrator = (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            (getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager).defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        }).also {
            val pattern = longArrayOf(0L, 1000L, 1000L)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                it.vibrate(VibrationEffect.createWaveform(pattern, 0))
            } else {
                @Suppress("DEPRECATION")
                it.vibrate(pattern, 0)
            }
        }
    }

    // Loudspeaker on or off for the live call. A call answered from the
    // phone's call notification is handed to Android's Telecom as a
    // self-managed call, and from then on Telecom owns the audio route: the
    // AudioManager calls LiveKit makes are overridden, so the Speaker button
    // did nothing. Such a call has to be asked through its Connection.
    // Otherwise (a call placed or answered inside the app) the route is set
    // on the AudioManager directly.
    private fun setSpeaker(callId: String?, on: Boolean) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && callId != null) {
            val conn = CallkitConnection.find(callId)
            if (conn != null) {
                @Suppress("DEPRECATION")
                conn.setAudioRoute(if (on) CallAudioState.ROUTE_SPEAKER else CallAudioState.ROUTE_WIRED_OR_EARPIECE)
                return
            }
        }
        val audio = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                if (on) {
                    audio.availableCommunicationDevices
                        .firstOrNull { it.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER }
                        ?.let { audio.setCommunicationDevice(it) }
                } else {
                    audio.clearCommunicationDevice()
                }
            } else {
                @Suppress("DEPRECATION")
                audio.isSpeakerphoneOn = on
            }
        } catch (e: RuntimeException) {
            // Routing refused: the call carries on where it is.
        }
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
        ringtone?.stop()
        ringtone = null
        vibrator?.cancel()
        vibrator = null
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
