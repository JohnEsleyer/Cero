package com.example.pocketdatabase

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class NotificationActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == SyncForegroundService.ACTION_STOP) {
            MainActivity.notifyFlutterToStopServer()
        }
    }
}
