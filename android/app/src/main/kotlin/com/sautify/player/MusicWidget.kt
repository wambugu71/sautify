package com.sautify.player

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.BitmapFactory
import android.view.KeyEvent
import android.widget.RemoteViews
import com.sautify.player.sautifyv2.MainActivity
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import java.io.File

class MusicWidget : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.widget_music_player).apply {
                
                // Open App
                val pendingIntent = HomeWidgetLaunchIntent.getActivity(
                    context,
                    MainActivity::class.java
                )
                setOnClickPendingIntent(R.id.widget_album_art, pendingIntent)
                setOnClickPendingIntent(R.id.widget_title, pendingIntent)

                // Data
                val title = widgetData.getString("widget_title", "No Song")
                val artist = widgetData.getString("widget_artist", "Unknown Artist")
                val isPlaying = widgetData.getBoolean("widget_is_playing", false)
                val imagePath = widgetData.getString("widget_image_path", null)

                setTextViewText(R.id.widget_title, title)
                setTextViewText(R.id.widget_artist, artist)

                if (imagePath != null) {
                    val imageFile = File(imagePath)
                    if (imageFile.exists()) {
                        val bitmap = BitmapFactory.decodeFile(imageFile.absolutePath)
                        setImageViewBitmap(R.id.widget_album_art, bitmap)
                    } else {
                        setImageViewResource(R.id.widget_album_art, android.R.drawable.ic_menu_gallery)
                    }
                } else {
                    setImageViewResource(R.id.widget_album_art, android.R.drawable.ic_menu_gallery)
                }

                // Play/Pause Icon
                if (isPlaying) {
                    setImageViewResource(R.id.widget_play_pause, android.R.drawable.ic_media_pause)
                } else {
                    setImageViewResource(R.id.widget_play_pause, android.R.drawable.ic_media_play)
                }

                // Buttons
                setOnClickPendingIntent(R.id.widget_prev, getMediaButtonIntent(context, KeyEvent.KEYCODE_MEDIA_PREVIOUS))
                setOnClickPendingIntent(R.id.widget_play_pause, getMediaButtonIntent(context, KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE))
                setOnClickPendingIntent(R.id.widget_next, getMediaButtonIntent(context, KeyEvent.KEYCODE_MEDIA_NEXT))
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }

    private fun getMediaButtonIntent(context: Context, keyCode: Int): PendingIntent {
        val intent = Intent(Intent.ACTION_MEDIA_BUTTON).apply {
            component = ComponentName(context, "com.ryanheise.audioservice.MediaButtonReceiver")
            putExtra(Intent.EXTRA_KEY_EVENT, KeyEvent(KeyEvent.ACTION_DOWN, keyCode))
        }
        return PendingIntent.getBroadcast(
            context,
            keyCode, // Request code must be unique
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }
}
