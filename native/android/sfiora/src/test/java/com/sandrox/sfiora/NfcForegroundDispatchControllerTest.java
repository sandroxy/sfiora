package com.sandrox.sfiora;

import static org.junit.Assert.*;
import static org.robolectric.Shadows.shadowOf;

import android.app.Activity;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.nfc.NfcAdapter;
import android.os.Looper;
import org.junit.After;
import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.Robolectric;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.android.controller.ActivityController;
import org.robolectric.annotation.Config;
import org.robolectric.shadows.ShadowNfcAdapter;

@RunWith(RobolectricTestRunner.class)
@Config(sdk = {28, 35})
public class NfcForegroundDispatchControllerTest {
    private ActivityController<Activity> host;
    private NfcForegroundDispatchController first;
    private NfcForegroundDispatchController second;
    private ShadowNfcAdapter adapter;

    @Before public void setUp() {
        host = Robolectric.buildActivity(Activity.class).setup();
        shadowOf(host.get().getPackageManager()).setSystemFeature(PackageManager.FEATURE_NFC, true);
        adapter = shadowOf(NfcAdapter.getDefaultAdapter(host.get()));
        adapter.setEnabled(true);
        first = new NfcForegroundDispatchController(host.get());
        second = new NfcForegroundDispatchController(host.get());
        first.onResume(host.get());
        second.onResume(host.get());
    }

    @After public void tearDown() {
        if (first != null) first.close();
        if (second != null) second.close();
        host.pause().stop().destroy();
    }

    @Test public void optInIsIdempotentAndOwnersDoNotDisableEachOther() {
        assertEquals("disabled", first.getState().get("state"));
        assertNull(adapter.getEnabledActivity());
        assertEquals("active", first.acquire("screen.a").get("state"));
        Object revision = first.getState().get("revision");
        first.acquire("screen.a");
        first.acquire("screen.b");
        assertEquals(revision, first.getState().get("revision"));
        first.release("screen.a");
        first.release("unknown");
        assertNull(adapter.getDisabledActivity());
        first.release("screen.b");
        assertEquals(host.get(), adapter.getDisabledActivity());
        assertEquals("disabled", first.getState().get("state"));
    }

    @Test public void independentBridgeInstancesShareOneNativeRegistration() {
        first.acquire("same-owner");
        second.acquire("same-owner");
        first.close();
        assertEquals("active", second.getState().get("state"));
        assertNull(adapter.getDisabledActivity());
        second.close();
        assertEquals(host.get(), adapter.getDisabledActivity());
    }

    @Test public void pausePreservesRequestsAndResumeRestoresDispatch() {
        first.acquire("screen");
        first.onPause();
        assertEquals("paused", first.getState().get("state"));
        first.onResume(host.get());
        assertEquals("active", first.getState().get("state"));
        first.onPause();
        first.release("screen");
        first.onResume(host.get());
        assertEquals("disabled", first.getState().get("state"));
    }

    @Test public void concurrentActivityCannotReplaceOrDisableTheCurrentOwner() {
        ActivityController<Activity> otherHost = Robolectric.buildActivity(Activity.class).setup();
        try {
            first.acquire("screen.a");
            second.onResume(otherHost.get());
            assertEquals("failed", second.acquire("screen.b").get("state"));
            assertEquals(host.get(), adapter.getEnabledActivity());
            assertNull(adapter.getDisabledActivity());
            first.onPause();
            assertEquals("active", second.acquire("screen.b").get("state"));
            assertEquals(otherHost.get(), adapter.getEnabledActivity());
            second.onPause();
        } finally {
            otherHost.pause().stop().destroy();
        }
    }

    @Test public void nfcToggleRestoresOwnedDispatchWithoutStartingAReader() {
        first.acquire("screen");
        adapter.setEnabled(false);
        changed();
        assertEquals("nfcDisabled", first.getState().get("state"));
        adapter.setEnabled(true);
        changed();
        assertEquals("active", first.getState().get("state"));
        assertFalse(adapter.isInReaderMode());
        Intent intent = shadowOf(adapter.getIntent()).getSavedIntent();
        assertEquals(NfcForegroundReceiver.class.getName(), intent.getComponent().getClassName());
        assertEquals("com.sandrox.sfiora.FOREGROUND_TAG", intent.getAction());
        assertEquals("application/vnd.sandrox.sfiora.foreground", intent.getType());
        assertTrue(shadowOf(adapter.getIntent()).isBroadcast());
    }

    @Test public void invalidOwnersHaveNoSideEffectsAndClosedControllersCannotReacquire() {
        for (String owner : new String[] {null, "", " leading", "a\n", "a\r", "中文", "a/b", "x".repeat(129)}) {
            assertThrows(IllegalArgumentException.class, () -> first.acquire(owner));
        }
        assertEquals("disabled", first.getState().get("state"));
        first.acquire("x".repeat(128));
        first.close();
        assertThrows(IllegalStateException.class, () -> first.acquire("screen"));
    }

    @Test public void disabledAndUnavailableNfcNeverRegisterDispatch() {
        adapter.setEnabled(false);
        assertEquals("nfcDisabled", first.acquire("screen").get("state"));
        assertNull(adapter.getEnabledActivity());
        first.release("screen");
        ShadowNfcAdapter.setNfcHardwareExists(false);
        assertEquals("unavailable", first.acquire("screen").get("state"));
        assertNull(adapter.getEnabledActivity());
    }

    private void changed() {
        host.get().sendBroadcast(new Intent(NfcAdapter.ACTION_ADAPTER_STATE_CHANGED));
        shadowOf(Looper.getMainLooper()).idle();
    }
}
