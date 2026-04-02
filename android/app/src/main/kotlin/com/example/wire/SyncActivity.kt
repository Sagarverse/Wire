package com.example.wire

import android.app.Activity
import android.content.ClipboardManager
import android.content.Context
import android.os.Bundle
import androidx.localbroadcastmanager.content.LocalBroadcastManager
import android.content.Intent
import android.graphics.Color
import android.graphics.drawable.ColorDrawable

class SyncActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        // Make the window fully transparent
        window.setBackgroundDrawable(ColorDrawable(Color.TRANSPARENT))
        
        val clipboardManager = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        val clipData = clipboardManager.primaryClip
        
        if (clipData != null && clipData.itemCount > 0) {
            val text = clipData.getItemAt(0).text?.toString() ?: ""
            // Send to background service via SharedPreferences
            val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            prefs.edit().putString("flutter.background_clipboard", text).apply()
        }
        
        // Finish immediately so the user doesn't see anything
        finish()
    }
}
