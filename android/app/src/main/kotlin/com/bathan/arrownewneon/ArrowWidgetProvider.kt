package com.bathan.arrownewneon

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.graphics.BitmapFactory
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import java.io.File

/**
 * Home-screen widget: the live game board with the level above it and a
 * control row underneath. The game is playable right inside the widget —
 * tapping the board (or FIRE) fires the next free arrow via a background Dart
 * isolate, with no app launch. ⛶ opens the full app on the same saved game.
 *
 * The board arrives as a **file path**, not as image bytes. It used to be a
 * base64 string in shared preferences, which meant a few hundred kilobytes of
 * text decoded on every widget refresh — and re-read by the app itself every
 * time it reloaded preferences. Now the Flutter side writes a PNG once and
 * this only ever reads the file.
 */
class ArrowWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        // The bitmap is the same for every instance of the widget, so it is
        // decoded once rather than once per widget.
        val board = decodeBoard(widgetData.getString("board_png_path", null))
        val level = widgetData.getString("widget_level", "LEVEL 1")
        val status = widgetData.getString("widget_status", "Arrow Escape")

        for (widgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.arrow_widget)

            if (board != null) {
                views.setImageViewBitmap(R.id.widget_board, board)
            }
            views.setTextViewText(R.id.widget_level, level)
            views.setTextViewText(R.id.widget_status, status)

            // Board and FIRE both play a move here, in a background Dart
            // isolate — the app never opens.
            val play = HomeWidgetBackgroundIntent.getBroadcast(
                context, Uri.parse("arrowgame://play")
            )
            views.setOnClickPendingIntent(R.id.widget_board, play)
            views.setOnClickPendingIntent(R.id.widget_play, play)

            views.setOnClickPendingIntent(
                R.id.widget_new,
                HomeWidgetBackgroundIntent.getBroadcast(
                    context, Uri.parse("arrowgame://new")
                )
            )
            views.setOnClickPendingIntent(
                R.id.widget_open,
                HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java)
            )

            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }

    /**
     * Reads the board PNG off disk. Returns null on anything unexpected, in
     * which case the widget simply keeps the picture it already had.
     */
    private fun decodeBoard(path: String?): android.graphics.Bitmap? {
        if (path.isNullOrEmpty()) return null
        return try {
            val file = File(path)
            if (!file.exists()) return null
            // The Flutter side already renders at widget size, so there is
            // nothing left to scale here.
            BitmapFactory.decodeFile(file.absolutePath)
        } catch (_: Exception) {
            null
        }
    }
}
