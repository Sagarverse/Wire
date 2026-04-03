package dev.sagarm.wire

import android.content.Intent
import android.service.quicksettings.TileService
import android.util.Log

class SyncTileService : TileService() {
    override fun onClick() {
        super.onClick()
        Log.d("Wire", "SyncTileService: onClick")
        val syncIntent = Intent(applicationContext, SyncActivity::class.java)
        syncIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_MULTIPLE_TASK)
        startActivityAndCollapse(syncIntent)
    }
}
