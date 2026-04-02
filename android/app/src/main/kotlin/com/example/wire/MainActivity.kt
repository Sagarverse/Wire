package com.example.wire

import android.content.BroadcastReceiver
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
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
import android.provider.Telephony
import android.telephony.SmsManager
import android.media.AudioManager
import android.media.AudioAttributes
import android.media.Ringtone
import android.media.RingtoneManager
import android.app.NotificationManager
import android.telephony.PhoneStateListener
import android.telecom.TelecomManager
import android.telephony.TelephonyManager
import android.view.KeyEvent
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import androidx.localbroadcastmanager.content.LocalBroadcastManager

class MainActivity : FlutterActivity() {
	private var sharedFilesSink: EventChannel.EventSink? = null
	private var callEventsSink: EventChannel.EventSink? = null
	private var callStateSink: EventChannel.EventSink? = null
	private var clipboardSink: EventChannel.EventSink? = null
	private var notificationSink: EventChannel.EventSink? = null
	private var backgroundClipboardSink: EventChannel.EventSink? = null
	private var clipboardListener: ClipboardManager.OnPrimaryClipChangedListener? = null
	private var callObserver: ContentObserver? = null
	private var phoneStateListener: PhoneStateListener? = null
	private var telephonyManager: TelephonyManager? = null
	private var lastCallState: Int? = null
	private var currentRingtone: Ringtone? = null
	private val floatingDockHandler = FloatingDockHandler()

	private val notificationReceiver = object : BroadcastReceiver() {
		override fun onReceive(context: Context?, intent: Intent?) {
			if (intent?.action == "WireNotificationEvent") {
				val title = intent.getStringExtra("title") ?: ""
				val body = intent.getStringExtra("body") ?: ""
				val packageName = intent.getStringExtra("packageName") ?: ""
				notificationSink?.success(mapOf(
					"title" to title,
					"body" to body,
					"packageName" to packageName
				))
			}
		}
	}

	private val backgroundClipboardReceiver = object : BroadcastReceiver() {
		override fun onReceive(context: Context?, intent: Intent?) {
			if (intent?.action == "dev.sagarm.wire.BACKGROUND_CLIPBOARD") {
				val text = intent.getStringExtra("text")
				if (text != null) {
					backgroundClipboardSink?.success(text)
				}
			}
		}
	}

	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)

		// Setup Floating Dock handler
		floatingDockHandler.setupChannels(flutterEngine, this)

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
					"dispatchTouch" -> {
						val nx = (call.argument<Double>("nx") ?: 0.0).toFloat()
						val ny = (call.argument<Double>("ny") ?: 0.0).toFloat()
						val action = call.argument<String>("action") ?: "down"
						val service = WireInputService.instance
						result.success(service?.dispatchTouch(nx, ny, action) == true)
					}
					"openDownloadsFolder" -> {
						openDownloadsFolder()
						result.success(true)
					}
					"revealInFinder" -> {
						openDownloadsFolder()
						result.success(true)
					}
					"setFocusMode" -> {
						val enabled = call.argument<Boolean>("enabled") ?: false
						setFocusMode(enabled, result)
					}
					"ringPhone" -> {
						ringPhone(result)
					}
					"stopRinging" -> {
						stopRinging(result)
					}
					"mediaPlayPause" -> {
						sendMediaButtonEvent(KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE)
						result.success(true)
					}
					"mediaNext" -> {
						sendMediaButtonEvent(KeyEvent.KEYCODE_MEDIA_NEXT)
						result.success(true)
					}
					"mediaPrevious" -> {
						sendMediaButtonEvent(KeyEvent.KEYCODE_MEDIA_PREVIOUS)
						result.success(true)
					}
					"volumeUp" -> {
						adjustVolume(AudioManager.ADJUST_RAISE)
						result.success(true)
					}
					"volumeDown" -> {
						adjustVolume(AudioManager.ADJUST_LOWER)
						result.success(true)
					}
					"volumeMute" -> {
						adjustVolume(AudioManager.ADJUST_TOGGLE_MUTE)
						result.success(true)
					}
					"isNotificationAccessGranted" -> {
						val componentName = android.content.ComponentName(this@MainActivity, WireNotificationListenerService::class.java)
						val listeners = Settings.Secure.getString(contentResolver, "enabled_notification_listeners")
						result.success(listeners != null && listeners.contains(componentName.flattenToString()))
					}
					"requestNotificationAccess" -> {
						val intent = Intent("android.settings.ACTION_NOTIFICATION_LISTENER_SETTINGS")
						intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
						startActivity(intent)
						result.success(true)
					}
					"getRecentSms" -> {
						getRecentSms(result)
					}
					"sendSms" -> {
						val number = call.argument<String>("number") ?: ""
						val message = call.argument<String>("message") ?: ""
						sendSms(number, message, result)
					}
					"activateApp" -> {
						activateApp()
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

		EventChannel(flutterEngine.dartExecutor.binaryMessenger, "wire/notifications")
			.setStreamHandler(object : EventChannel.StreamHandler {
				override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
					notificationSink = events
					LocalBroadcastManager.getInstance(this@MainActivity)
						.registerReceiver(notificationReceiver, android.content.IntentFilter("WireNotificationEvent"))
				}

				override fun onCancel(arguments: Any?) {
					notificationSink = null
					LocalBroadcastManager.getInstance(this@MainActivity)
						.unregisterReceiver(notificationReceiver)
				}
			})

		EventChannel(flutterEngine.dartExecutor.binaryMessenger, "wire/clipboard_sync")
			.setStreamHandler(object : EventChannel.StreamHandler {
				override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
					backgroundClipboardSink = events
					LocalBroadcastManager.getInstance(this@MainActivity)
						.registerReceiver(backgroundClipboardReceiver, android.content.IntentFilter("dev.sagarm.wire.BACKGROUND_CLIPBOARD"))
				}

				override fun onCancel(arguments: Any?) {
					backgroundClipboardSink = null
					LocalBroadcastManager.getInstance(this@MainActivity)
						.unregisterReceiver(backgroundClipboardReceiver)
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

	private fun getRecentSms(result: MethodChannel.Result) {
		if (ContextCompat.checkSelfPermission(this, android.Manifest.permission.READ_SMS) != PackageManager.PERMISSION_GRANTED) {
			result.error("PERMISSION_DENIED", "READ_SMS permission denied", null)
			return
		}

		val smsList = mutableListOf<Map<String, Any>>()
		val cursor = contentResolver.query(
			Telephony.Sms.CONTENT_URI,
			arrayOf(Telephony.Sms._ID, Telephony.Sms.ADDRESS, Telephony.Sms.BODY, Telephony.Sms.DATE, Telephony.Sms.TYPE),
			null,
			null,
			"${Telephony.Sms.DATE} DESC LIMIT 50"
		)

		cursor?.use {
			val idIndex = it.getColumnIndex(Telephony.Sms._ID)
			val addressIndex = it.getColumnIndex(Telephony.Sms.ADDRESS)
			val bodyIndex = it.getColumnIndex(Telephony.Sms.BODY)
			val dateIndex = it.getColumnIndex(Telephony.Sms.DATE)
			val typeIndex = it.getColumnIndex(Telephony.Sms.TYPE)

			while (it.moveToNext()) {
				val address = it.getString(addressIndex) ?: "Unknown"
				val body = it.getString(bodyIndex) ?: ""
				val date = it.getLong(dateIndex)
				val type = it.getInt(typeIndex) // 1: inbox, 2: sent
				
				// Attempt to resolve contact name
				var senderName = address
				try {
					val uri = Uri.withAppendedPath(android.provider.ContactsContract.PhoneLookup.CONTENT_FILTER_URI, Uri.encode(address))
					val contactCursor = contentResolver.query(uri, arrayOf(android.provider.ContactsContract.PhoneLookup.DISPLAY_NAME), null, null, null)
					contactCursor?.use { c ->
						if (c.moveToFirst()) {
							senderName = c.getString(c.getColumnIndexOrThrow(android.provider.ContactsContract.PhoneLookup.DISPLAY_NAME)) ?: address
						}
					}
				} catch (e: Exception) {
					// Ignore if READ_CONTACTS is missing
				}

				val smsMap = mapOf(
					"id" to it.getString(idIndex),
					"address" to address,
					"senderName" to senderName,
					"body" to body,
					"date" to date,
					"isSent" to (type == Telephony.Sms.MESSAGE_TYPE_SENT)
				)
				smsList.add(smsMap)
			}
		}
		result.success(smsList)
	}

	private fun sendSms(number: String, message: String, result: MethodChannel.Result) {
		if (ContextCompat.checkSelfPermission(this, android.Manifest.permission.SEND_SMS) != PackageManager.PERMISSION_GRANTED) {
			result.error("PERMISSION_DENIED", "SEND_SMS permission denied", null)
			return
		}
		if (number.isEmpty() || message.isEmpty()) {
			result.error("INVALID_ARGS", "Number or message is empty", null)
			return
		}

		try {
			val smsManager = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                getSystemService(SmsManager::class.java)
            } else {
                @Suppress("DEPRECATION")
                SmsManager.getDefault()
            }
			smsManager.sendTextMessage(number, null, message, null, null)
			result.success(true)
		} catch (e: Exception) {
			result.error("SMS_FAILED", e.message, null)
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
			val method = telecomManager::class.java.getMethod("endCall")
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

	private fun setFocusMode(enabled: Boolean, result: MethodChannel.Result) {
		val notificationManager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
		if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
			if (notificationManager.isNotificationPolicyAccessGranted) {
				val filter = if (enabled) NotificationManager.INTERRUPTION_FILTER_PRIORITY else NotificationManager.INTERRUPTION_FILTER_ALL
				notificationManager.setInterruptionFilter(filter)
				result.success(true)
			} else {
				// We don't have permission to change DND. Redirect to settings.
				try {
					val intent = Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS)
					intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
					startActivity(intent)
					result.success(false)
				} catch (e: Exception) {
					result.error("ERROR", "Could not open DND settings: ${e.message}", null)
				}
			}
		} else {
			// Older versions don't have granular DND via NotificationManager
			result.success(false)
		}
	}

	private fun isAccessibilityEnabled(): Boolean {
		val serviceId = "$packageName/${WireInputService::class.java.name}"
		val enabledServices = Settings.Secure.getString(contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES)
		return enabledServices?.contains(serviceId) == true
	}

	private fun ringPhone(result: MethodChannel.Result) {
		try {
			val audioManager = getSystemService(AUDIO_SERVICE) as AudioManager
			val maxVolume = audioManager.getStreamMaxVolume(AudioManager.STREAM_ALARM)
			audioManager.setStreamVolume(AudioManager.STREAM_ALARM, maxVolume, 0)
			var uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
			if (uri == null) {
				uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
			}
			if (uri != null) {
				currentRingtone?.stop()
				currentRingtone = RingtoneManager.getRingtone(applicationContext, uri)
				if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
					currentRingtone?.audioAttributes = AudioAttributes.Builder()
						.setUsage(AudioAttributes.USAGE_ALARM)
						.setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
						.build()
				} else {
					@Suppress("DEPRECATION")
					currentRingtone?.streamType = AudioManager.STREAM_ALARM
				}
				currentRingtone?.play()
				result.success(true)
			} else {
				result.success(false)
			}
		} catch (e: Exception) {
			result.error("ERROR", "Could not ring phone: ${e.message}", null)
		}
	}

	private fun stopRinging(result: MethodChannel.Result) {
		try {
			currentRingtone?.stop()
			currentRingtone = null
			result.success(true)
		} catch (e: Exception) {
			result.error("ERROR", "Could not stop ringing: ${e.message}", null)
		}
	}

	private fun sendMediaButtonEvent(keyCode: Int) {
		val audioManager = getSystemService(AUDIO_SERVICE) as AudioManager
		val eventDown = KeyEvent(KeyEvent.ACTION_DOWN, keyCode)
		audioManager.dispatchMediaKeyEvent(eventDown)
		val eventUp = KeyEvent(KeyEvent.ACTION_UP, keyCode)
		audioManager.dispatchMediaKeyEvent(eventUp)
	}

	private fun adjustVolume(direction: Int) {
		val audioManager = getSystemService(AUDIO_SERVICE) as AudioManager
		audioManager.adjustStreamVolume(AudioManager.STREAM_MUSIC, direction, AudioManager.FLAG_SHOW_UI)
	}

	private fun activateApp() {
		val intent = Intent(this, MainActivity::class.java)
		intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
		startActivity(intent)
	}
}
