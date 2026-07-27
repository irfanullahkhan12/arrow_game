package com.example.arowgame

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.util.Base64
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Home-screen widget: the live game board on top (rendered to a bitmap by the
 * Flutter side) with a slim control row underneath. The game is playable
 * right inside the widget: tapping the board (or ▶) fires the next free arrow
 * via a background Dart isolate — no app launch. ⛶ opens the full app on the
 * exact same saved game.
 */
class ArrowWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        for (widgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.arrow_widget)

            // Board snapshot pushed by the Flutter side.
            val encoded = widgetData.getString("board_png_b64", null)
            if (encoded != null) {
                try {
                    val raw = Base64.decode(encoded, Base64.DEFAULT)
                    val options = BitmapFactory.Options()
                    var bitmap = BitmapFactory.decodeByteArray(raw, 0, raw.size, options)
                    // Stay well under the RemoteViews bitmap budget.
                    if (bitmap != null && bitmap.width > 600) {
                        val scale = 600f / bitmap.width
                        bitmap = Bitmap.createScaledBitmap(
                            bitmap,
                            600,
                            (bitmap.height * scale).toInt(),
                            true
                        )
                    }
                    if (bitmap != null) {
                        views.setImageViewBitmap(R.id.widget_board, bitmap)
                    }
                } catch (_: Exception) {
                    // Keep whatever the widget showed before.
                }
            }

            views.setTextViewText(
                R.id.widget_status,
                widgetData.getString("widget_status", "Arrow Escape")
            )

            // Board tap → play a move right here in the widget (background
            // Dart callback, no app launch).
            views.setOnClickPendingIntent(
                R.id.widget_board,
                HomeWidgetBackgroundIntent.getBroadcast(
                    context, Uri.parse("arrowgame://play")
                )
            )

            // Control row → background Dart callbacks (no app launch).
            views.setOnClickPendingIntent(
                R.id.widget_play,
                HomeWidgetBackgroundIntent.getBroadcast(
                    context, Uri.parse("arrowgame://play")
                )
            )
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
}
