package dev.kinemium.engine;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.os.Build;
import android.os.Bundle;

import org.libsdl.app.SDLActivity;

public class PlaytestActivity extends SDLActivity {
    public static final String EXTRA_ARGS = "dev.kinemium.engine.PLAYTEST_ARGS";

    private BroadcastReceiver stopReceiver;

    @Override
    protected String[] getArguments() {
        Intent intent = getIntent();
        String joined = intent != null ? intent.getStringExtra(EXTRA_ARGS) : null;
        if (joined == null || joined.isEmpty()) {
            return new String[0];
        }
        return joined.split("\n");
    }

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        stopReceiver = new BroadcastReceiver() {
            @Override
            public void onReceive(Context context, Intent intent) {
                if (EditorActivity.ACTION_STOP_PLAYTEST.equals(intent.getAction())) {
                    finish();
                }
            }
        };

        IntentFilter filter = new IntentFilter(EditorActivity.ACTION_STOP_PLAYTEST);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(stopReceiver, filter, Context.RECEIVER_NOT_EXPORTED);
        } else {
            registerReceiver(stopReceiver, filter);
        }
    }

    @Override
    protected void onDestroy() {
        if (stopReceiver != null) {
            try {
                unregisterReceiver(stopReceiver);
            } catch (IllegalArgumentException ignored) {
                // The receiver was never registered; nothing to do.
            }
            stopReceiver = null;
        }
        super.onDestroy();
    }
}
