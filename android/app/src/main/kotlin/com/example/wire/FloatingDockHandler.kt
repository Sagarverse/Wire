package com.example.wire

import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.PixelFormat
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.Settings
import android.view.Gravity
import android.view.LayoutInflater
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.Button
import android.widget.ImageButton
import android.widget.LinearLayout
import androidx.core.view.isVisible
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class FloatingDockHandler {
    private var windowManager: WindowManager? = null
    private var dockView: LinearLayout? = null
    private var isExpanded = false
    private var eventSink: EventChannel.EventSink? = null
    private var lastEventTime = 0L

    fun setupChannels(flutterEngine: FlutterEngine, context: Context) {
        windowManager = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.example.wire/floating-dock")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "show" -> {
                        showDock(context)
                        result.success(true)
                    }
                    "hide" -> {
                        hideDock()
                        result.success(true)
                    }
                    "setExpanded" -> {
                        val expanded = call.argument<Boolean>("expanded") ?: false
                        setExpanded(expanded)
                        result.success(true)
                    }
                    "setPosition" -> {
                        val x = call.argument<Double>("x")?.toInt() ?: 0
                        val y = call.argument<Double>("y")?.toInt() ?: 0
                        setPosition(x, y)
                        result.success(true)
                    }
                    "setOrientation" -> {
                        val orientation = call.argument<String>("orientation") ?: "horizontal"
                        setOrientation(orientation)
                        result.success(true)
                    }
                    "setOpacity" -> {
                        val opacity = (call.argument<Double>("opacity") ?: 0.9).toFloat()
                        setOpacity(opacity)
                        result.success(true)
                    }
                    "getStatus" -> {
                        result.success(mapOf(
                            "visible" to (dockView?.isVisible ?: false),
                            "expanded" to isExpanded
                        ))
                    }
                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "com.example.wire/floating-dock-events")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            })
    }

    private fun showDock(context: Context) {
        if (dockView != null && dockView?.isVisible == true) return

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(context)) {
            emitEvent(
                "error",
                mapOf("message" to "Overlay permission is required for Floating Dock. Enable 'Display over other apps' in Android settings.")
            )
            return
        }

        dockView = createDockView(context)
        
        val params = WindowManager.LayoutParams().apply {
            type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            } else {
                @Suppress("DEPRECATION")
                WindowManager.LayoutParams.TYPE_PHONE
            }
            format = PixelFormat.TRANSLUCENT
            flags = WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_WATCH_OUTSIDE_TOUCH or
                    WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED
            width = WindowManager.LayoutParams.WRAP_CONTENT
            height = WindowManager.LayoutParams.WRAP_CONTENT
            gravity = Gravity.BOTTOM or Gravity.END
            x = 20
            y = 100
        }

        try {
            windowManager?.addView(dockView, params)
            emitEvent("dock_shown", mapOf("visible" to true))
        } catch (e: Exception) {
            dockView = null
            emitEvent("error", mapOf("message" to "Unable to show floating dock: ${e.message}"))
        }
    }

    private fun hideDock() {
        if (dockView != null && dockView?.isVisible == true) {
            windowManager?.removeView(dockView)
            dockView = null
            emitEvent("dock_hidden", mapOf("visible" to false))
        }
    }

    private fun setExpanded(expanded: Boolean) {
        isExpanded = expanded
        if (isExpanded) {
            expandDock()
        } else {
            collapseDock()
        }
        emitEvent("dock_expanded", mapOf("expanded" to expanded))
    }

    private fun expandDock() {
        // Show all buttons
        dockView?.let { dock ->
            for (i in 0 until dock.childCount) {
                dock.getChildAt(i).visibility = View.VISIBLE
            }
        }
    }

    private fun collapseDock() {
        // Show only main toggle button
        dockView?.let { dock ->
            for (i in 1 until dock.childCount) {
                dock.getChildAt(i).visibility = View.GONE
            }
        }
    }

    private fun setPosition(x: Int, y: Int) {
        dockView?.let { dock ->
            val params = dock.layoutParams as WindowManager.LayoutParams
            params.x = x
            params.y = y
            windowManager?.updateViewLayout(dock, params)
            emitEvent("position_changed", mapOf("x" to x, "y" to y))
        }
    }

    private fun setOrientation(orientation: String) {
        dockView?.let { dock ->
            dock.orientation = if (orientation == "vertical") {
                LinearLayout.VERTICAL
            } else {
                LinearLayout.HORIZONTAL
            }
        }
    }

    private fun setOpacity(opacity: Float) {
        dockView?.alpha = opacity
    }

    private fun createDockView(context: Context): LinearLayout {
        val dock = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            setBackgroundColor(android.graphics.Color.parseColor("#1a1a1a"))
            setPadding(8, 8, 8, 8)
        }

        val dockButtons = listOf(
            Pair("toggle", "☰"),
            Pair("keyboard", "⌨️"),
            Pair("camera", "📷"),
            Pair("clipboard", "📋"),
            Pair("files", "📁"),
            Pair("settings", "⚙️")
        )

        for ((id, symbol) in dockButtons) {
            val button = Button(context).apply {
                text = symbol
                textSize = 18f
                setPadding(12, 8, 12, 8)
                setBackgroundColor(
                    if (id == "toggle") {
                        android.graphics.Color.parseColor("#00A76F")
                    } else {
                        android.graphics.Color.parseColor("#333333")
                    }
                )
                setTextColor(android.graphics.Color.WHITE)
                
                setOnClickListener {
                    if (id == "toggle") {
                        setExpanded(!isExpanded)
                    } else {
                        emitEvent("action_tapped", mapOf("action" to id))
                    }
                }
                
                if (id != "toggle") {
                    visibility = View.GONE
                }
            }
            
            val params = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            )
            params.setMargins(4, 0, 4, 0)
            dock.addView(button, params)
        }

        // Make dock draggable
        var lastX = 0f
        var lastY = 0f
        dock.setOnTouchListener { v, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    lastX = event.rawX
                    lastY = event.rawY
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = (event.rawX - lastX).toInt()
                    val dy = (event.rawY - lastY).toInt()
                    
                    val params = v.layoutParams as WindowManager.LayoutParams
                    params.x += dx
                    params.y += dy
                    windowManager?.updateViewLayout(v, params)
                    
                    lastX = event.rawX
                    lastY = event.rawY
                }
            }
            false
        }

        return dock
    }

    private fun emitEvent(type: String, data: Map<String, Any?>) {
        if (System.currentTimeMillis() - lastEventTime < 100) {
            return // Rate limit events
        }
        lastEventTime = System.currentTimeMillis()
        
        Handler(Looper.getMainLooper()).post {
            eventSink?.success(mapOf(
                "type" to type,
                "data" to data,
                "timestamp" to System.currentTimeMillis()
            ))
        }
    }
}
