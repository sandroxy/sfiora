package com.sandrox.sfiora;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

/** Private destination for explicitly opted-in foreground dispatch. Never reads a tag. */
public final class NfcForegroundReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context context, Intent intent) {
        // Explicit read/write calls remain the only source of business results.
    }
}
