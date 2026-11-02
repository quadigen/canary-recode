package dev.kinemium.engine;

import android.content.Context;
import android.content.Intent;

import org.libsdl.app.SDLActivity;

public class EditorActivity extends SDLActivity {
    public static final String ACTION_STOP_PLAYTEST = "dev.kinemium.engine.STOP_PLAYTEST";

    public static void launchPlaytest(Context context, String joinedArgs) {
        Intent intent = new Intent(context, PlaytestActivity.class);
        intent.putExtra(PlaytestActivity.EXTRA_ARGS, joinedArgs);
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_DOCUMENT | Intent.FLAG_ACTIVITY_MULTIPLE_TASK);
        context.startActivity(intent);
    }

    // stopPlaytest asks any running playtest window to close itself.
    public static void stopPlaytest(Context context) {
        Intent intent = new Intent(ACTION_STOP_PLAYTEST);
        intent.setPackage(context.getPackageName());
        context.sendBroadcast(intent);
    }
}
