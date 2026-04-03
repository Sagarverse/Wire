package dev.sagarm.wire

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.ClipboardManager

class ClipboardSyncReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == "dev.sagarm.wire.SYNC_CLIPBOARD") {
            // Android 10+ allows background clipboard reading if it's triggered from an explicit user interaction.
            // When the user taps the button on the notification, it fires this intent, which is a direct interaction 
            // allowing us to briefly read the clipboard. But the easiest way to send it to the background isolate 
            // is to bring a minimal transparent activity to the front, or just fetch the text here and send it via Intent.
            // However, the cleanest way to do this without waking up the app is to let the background isolate 
            // handle the regular poll, but the platform channel is isolated. 
            // Let's create an invisible activity to do the read specifically to avoid permission issues.
            val syncIntent = Intent(context, SyncActivity::class.java)
            syncIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_MULTIPLE_TASK)
            context.startActivity(syncIntent)
        }
    }
}
