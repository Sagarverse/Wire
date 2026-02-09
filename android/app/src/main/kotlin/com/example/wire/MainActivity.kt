package com.example.wire

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Intent
import android.content.pm.PackageManager
import android.database.ContentObserver
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.CallLog
import android.provider.OpenableColumns
import android.provider.Settings
import android.media.AudioManager
import android.telecom.TelecomManager
import android.telephony.PhoneStateListener
import android.telephony.TelephonyManager
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
	private var sharedFilesSink: EventChannel.EventSink? = null
	private var callEventsSink: EventChannel.EventSink? = null
	private var callStateSink: EventChannel.EventSink? = null
	private var clipboardSink: EventChannel.EventSink? = null
	private var clipboardListener: ClipboardManager.OnPrimaryClipChangedListener? = null
	private var callObserver: ContentObserver? = null
	private var phoneStateListener: PhoneStateListener? = null
	private var telephonyManager: TelephonyManager? = null
	private var lastCallState: Int? = null

	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)

		MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "wire/platform")
			.setMethodCallHandler { call, result ->
				when (call.method) {
					"getClipboardText" -> {
						val clipboard = getSystemService(CLIPBOARD_SERVICE) as ClipboardManager
						val text = clipboard.primaryClip?.getItemAt(0)?.coerceToText(this)?.toString()
						result.success(text)
					}
					"setClipboardText" -> {
						val text = call.argument<String>("text") ?: ""
						val clipboard = getSystemService(CLIPBOARD_SERVICE) as ClipboardManager
						clipboard.setPrimaryClip(ClipData.newPlainText("wire", text))
						result.success(true)
					}
					"startDial" -> {
						val number = call.argument<String>("number") ?: ""
						if (number.isNotEmpty()) {
							val intent = Intent(Intent.ACTION_DIAL)
							intent.data = Uri.parse("tel:$number")
							intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
							startActivity(intent)
						}
						result.success(true)
					}
					"answerCall" -> {
						answerCall(result)
					}
					"setPhoneMute" -> {
						val mute = call.argument<Boolean>("mute") ?: false
						setPhoneMute(mute, result)
					}
					"declineCall" -> {
						declineCall(result)
					}
					"isAccessibilityEnabled" -> {
						result.success(isAccessibilityEnabled())
					}
					"openAccessibilitySettings" -> {
						val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
						intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
						startActivity(intent)
						result.success(true)
					}
					"inputText" -> {
						val text = call.argument<String>("text") ?: ""
						val service = WireInputService.instance
						result.success(service?.inputText(text) == true)
					}
					"openDownloadsFolder" -> {
						openDownloadsFolder()
						result.success(true)
					}
					else -> result.notImplemented()
				}
			}

		EventChannel(flutterEngine.dartExecutor.binaryMessenger, "wire/shared_files")
			.setStreamHandler(object : EventChannel.StreamHandler {
				override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
					sharedFilesSink = events
				}

				override fun onCancel(arguments: Any?) {
					sharedFilesSink = null
				}
			})

		EventChannel(flutterEngine.dartExecutor.binaryMessenger, "wire/call_events")
			.setStreamHandler(object : EventChannel.StreamHandler {
				override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
					callEventsSink = events
					startCallObserver()
				}

				override fun onCancel(arguments: Any?) {
					callEventsSink = null
					stopCallObserver()
				}
			})

		EventChannel(flutterEngine.dartExecutor.binaryMessenger, "wire/call_state")
			.setStreamHandler(object : EventChannel.StreamHandler {
				override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
					callStateSink = events
					startCallStateListener()
				}

				override fun onCancel(arguments: Any?) {
					callStateSink = null
					stopCallStateListener()
				}
			})

		EventChannel(flutterEngine.dartExecutor.binaryMessenger, "wire/clipboard_events")
			.setStreamHandler(object : EventChannel.StreamHandler {
				override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
					clipboardSink = events
					startClipboardListener()
				}

				override fun onCancel(arguments: Any?) {
					clipboardSink = null
					stopClipboardListener()
				}
			})
	}

	override fun onCreate(savedInstanceState: android.os.Bundle?) {
		super.onCreate(savedInstanceState)
		handleShareIntent(intent)
	}

	override fun onNewIntent(intent: Intent) {
		super.onNewIntent(intent)
		handleShareIntent(intent)
	}

	private fun handleShareIntent(intent: Intent?) {
		if (intent == null) return
		val action = intent.action ?: return
		if (action == Intent.ACTION_SEND) {
			val uri = intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
			uri?.let { emitSharedFiles(listOf(copyUriToCache(it))) }
		} else if (action == Intent.ACTION_SEND_MULTIPLE) {
			val uris = intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
			if (!uris.isNullOrEmpty()) {
				val paths = uris.map { copyUriToCache(it) }
				emitSharedFiles(paths)
			}
		}
	}

	private fun emitSharedFiles(paths: List<String>) {
		if (paths.isEmpty()) return
		sharedFilesSink?.success(paths)
	}

	private fun copyUriToCache(uri: Uri): String {
		val name = getFileName(uri)
		val outFile = File(cacheDir, name)
		contentResolver.openInputStream(uri)?.use { input ->
			FileOutputStream(outFile).use { output ->
				input.copyTo(output)
			}
		}
		return outFile.absolutePath
	}

	private fun getFileName(uri: Uri): String {
		var name = "shared_${System.currentTimeMillis()}"
		contentResolver.query(uri, null, null, null, null)?.use { cursor ->
			val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
			if (nameIndex >= 0 && cursor.moveToFirst()) {
				name = cursor.getString(nameIndex)
			}
		}
		return name
	}

	private fun startCallObserver() {
		if (callObserver != null) return
		if (ContextCompat.checkSelfPermission(this, android.Manifest.permission.READ_CALL_LOG) != PackageManager.PERMISSION_GRANTED) {
			return
		}
		callObserver = object : ContentObserver(Handler(Looper.getMainLooper())) {
			override fun onChange(selfChange: Boolean) {
				emitLatestCall()
			}
		}
		contentResolver.registerContentObserver(CallLog.Calls.CONTENT_URI, true, callObserver!!)
		emitLatestCall()
	}

	private fun startCallStateListener() {
		if (phoneStateListener != null) return
		if (ContextCompat.checkSelfPermission(this, android.Manifest.permission.READ_PHONE_STATE) != PackageManager.PERMISSION_GRANTED) {
			return
		}
		telephonyManager = getSystemService(TELEPHONY_SERVICE) as TelephonyManager
		phoneStateListener = object : PhoneStateListener() {
			override fun onCallStateChanged(state: Int, incomingNumber: String?) {
				if (state == lastCallState) return
				lastCallState = state
				val stateLabel = when (state) {
					TelephonyManager.CALL_STATE_RINGING -> "ringing"
					TelephonyManager.CALL_STATE_OFFHOOK -> "offhook"
					TelephonyManager.CALL_STATE_IDLE -> "idle"
					else -> "unknown"
				}
				callStateSink?.success(
					mapOf(
						"state" to stateLabel,
						"number" to (incomingNumber ?: ""),
						"timestamp" to System.currentTimeMillis()
					)
				)
			}
		}
		telephonyManager?.listen(phoneStateListener, PhoneStateListener.LISTEN_CALL_STATE)
	}

	private fun startClipboardListener() {
		if (clipboardListener != null) return
		val clipboard = getSystemService(CLIPBOARD_SERVICE) as ClipboardManager
		clipboardListener = ClipboardManager.OnPrimaryClipChangedListener {
			val text = clipboard.primaryClip?.getItemAt(0)?.coerceToText(this)?.toString() ?: ""
			if (text.isNotEmpty()) {
				clipboardSink?.success(text)
			}
		}
		clipboard.addPrimaryClipChangedListener(clipboardListener!!)
	}

	private fun stopClipboardListener() {
		val clipboard = getSystemService(CLIPBOARD_SERVICE) as ClipboardManager
		clipboardListener?.let { clipboard.removePrimaryClipChangedListener(it) }
		clipboardListener = null
	}

	private fun stopCallStateListener() {
		telephonyManager?.listen(phoneStateListener, PhoneStateListener.LISTEN_NONE)
		phoneStateListener = null
		telephonyManager = null
		lastCallState = null
	}

	private fun stopCallObserver() {
		callObserver?.let { contentResolver.unregisterContentObserver(it) }
		callObserver = null
	}

	private fun emitLatestCall() {
		if (ContextCompat.checkSelfPermission(this, android.Manifest.permission.READ_CALL_LOG) != PackageManager.PERMISSION_GRANTED) {
			return
		}
		val cursor = contentResolver.query(
			CallLog.Calls.CONTENT_URI,
			arrayOf(CallLog.Calls.NUMBER, CallLog.Calls.CACHED_NAME, CallLog.Calls.TYPE, CallLog.Calls.DATE),
			null,
			null,
			CallLog.Calls.DATE + " DESC"
		) ?: return
		cursor.use {
			if (it.moveToFirst()) {
				val number = it.getString(0) ?: ""
				val name = it.getString(1) ?: ""
				val typeInt = it.getInt(2)
				val date = it.getLong(3)
				val type = when (typeInt) {
					CallLog.Calls.INCOMING_TYPE -> "incoming"
					CallLog.Calls.OUTGOING_TYPE -> "outgoing"
					CallLog.Calls.MISSED_TYPE -> "missed"
					else -> "unknown"
				}
				callEventsSink?.success(
					mapOf(
						"number" to number,
						"name" to name,
						"type" to type,
						"timestamp" to date
					)
				)
			}
		}
	}

	private fun answerCall(result: MethodChannel.Result) {
		if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
			result.success(false)
			return
		}
		if (ContextCompat.checkSelfPermission(this, android.Manifest.permission.ANSWER_PHONE_CALLS) != PackageManager.PERMISSION_GRANTED) {
			result.error("PERMISSION", "ANSWER_PHONE_CALLS not granted", null)
			return
		}
		val telecomManager = getSystemService(TELECOM_SERVICE) as TelecomManager
		telecomManager.acceptRingingCall()
		result.success(true)
	}

	private fun setPhoneMute(mute: Boolean, result: MethodChannel.Result) {
		val audioManager = getSystemService(AUDIO_SERVICE) as AudioManager
		audioManager.isMicrophoneMute = mute
		result.success(true)
	}

	private fun declineCall(result: MethodChannel.Result) {
		if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
			result.success(false)
			return
		}
		val telecomManager = getSystemService(TELECOM_SERVICE) as TelecomManager
		try {
			val method = telecomManager.javaClass.getMethod("endCall")
			val ended = method.invoke(telecomManager) as? Boolean ?: false
			result.success(ended)
		} catch (_: Exception) {
			result.success(false)
		}
	}

	private fun openDownloadsFolder() {
		try {
			val uri = Uri.parse("content://com.android.externalstorage.documents/document/primary:Download")
			val intent = Intent(Intent.ACTION_VIEW)
			intent.setDataAndType(uri, "vnd.android.document/directory")
			intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
			startActivity(intent)
		} catch (_: Exception) {
			val intent = Intent(Intent.ACTION_VIEW)
			intent.setDataAndType(Uri.parse("file:///storage/emulated/0/Download"), "resource/folder")
			intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
			startActivity(intent)
		}
	}

	private fun isAccessibilityEnabled(): Boolean {
		val serviceId = "$packageName/${WireInputService::class.java.name}"
		val enabledServices = Settings.Secure.getString(contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES)
		return enabledServices?.contains(serviceId) == true
	}
}
