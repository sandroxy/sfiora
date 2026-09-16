package com.sandrox.sfiora.bridge;

import static org.junit.Assert.*;
import static org.robolectric.Shadows.shadowOf;

import android.app.Activity;
import android.content.pm.PackageManager;
import android.nfc.NfcAdapter;
import android.os.Bundle;
import android.os.Looper;

import androidx.lifecycle.Lifecycle;
import androidx.lifecycle.LifecycleOwner;
import androidx.lifecycle.LifecycleRegistry;

import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.atomic.AtomicReference;

import org.json.JSONObject;
import org.junit.After;
import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.Robolectric;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.android.controller.ActivityController;
import org.robolectric.annotation.Config;

@RunWith(RobolectricTestRunner.class)
@Config(sdk = {28, 35})
public class SfioraBridgeLifecycleTest {
    public static final class HostActivity extends Activity implements LifecycleOwner {
        final LifecycleRegistry lifecycle = new LifecycleRegistry(this);
        @Override public Lifecycle getLifecycle() { return lifecycle; }
        @Override protected void onCreate(Bundle state) {
            super.onCreate(state);
            lifecycle.handleLifecycleEvent(Lifecycle.Event.ON_CREATE);
        }
        @Override protected void onStart() {
            super.onStart();
            lifecycle.handleLifecycleEvent(Lifecycle.Event.ON_START);
        }
        @Override protected void onResume() {
            super.onResume();
            lifecycle.handleLifecycleEvent(Lifecycle.Event.ON_RESUME);
        }
        @Override protected void onPause() {
            lifecycle.handleLifecycleEvent(Lifecycle.Event.ON_PAUSE);
            super.onPause();
        }
        @Override protected void onStop() {
            lifecycle.handleLifecycleEvent(Lifecycle.Event.ON_STOP);
            super.onStop();
        }
        @Override protected void onDestroy() {
            lifecycle.handleLifecycleEvent(Lifecycle.Event.ON_DESTROY);
            super.onDestroy();
        }
    }

    private final List<ActivityController<HostActivity>> hosts = new ArrayList<>();
    private SfioraBridgeRuntime runtime;
    private SfioraBridgeLifecycle bridge;
    private ActivityController<HostActivity> host;

    @Before public void setUp() {
        host = newHost();
        shadowOf(host.get().getPackageManager()).setSystemFeature(PackageManager.FEATURE_NFC, true);
        shadowOf(NfcAdapter.getDefaultAdapter(host.get())).setEnabled(true);
        runtime = new SfioraBridgeRuntime();
        bridge = new SfioraBridgeLifecycle(runtime);
    }

    @After public void tearDown() {
        runtime.close();
        for (ActivityController<HostActivity> controller : hosts) {
            if (!controller.get().isDestroyed()) controller.pause().stop().destroy();
        }
        shadowOf(Looper.getMainLooper()).idle();
    }

    @Test public void lateBindingReplaysResumeAndDoesNotDuplicateObservers() throws Exception {
        assertState(host.get(), "acquireForegroundDispatch", "[\"screen\"]", "active");
        for (int index = 0; index < 3; index++) {
            assertState(host.get(), "getForegroundDispatchState", "[]", "active");
        }
        assertEquals(1, host.get().lifecycle.getObserverCount());
    }

    @Test public void repeatedRecreationBindsAlreadyResumedReplacementAndDropsOldOwners() throws Exception {
        for (int index = 0; index < 3; index++) {
            assertState(host.get(), "acquireForegroundDispatch", "[\"screen\"]", "active");
            host.pause().stop().destroy();
            assertEquals(0, host.get().lifecycle.getObserverCount());
            host = newHost();
            assertState(host.get(), "getForegroundDispatchState", "[]", "disabled");
        }
        assertState(host.get(), "acquireForegroundDispatch", "[\"screen\"]", "active");
        host.pause();
        assertState(host.get(), "getForegroundDispatchState", "[]", "paused");
        host.resume();
        assertState(host.get(), "getForegroundDispatchState", "[]", "active");
    }

    @Test public void firstCallInBackgroundStaysPausedUntilActualResume() throws Exception {
        host.pause();
        assertState(host.get(), "acquireForegroundDispatch", "[\"screen\"]", "paused");
        assertNull(shadowOf(NfcAdapter.getDefaultAdapter(host.get())).getEnabledActivity());
        host.resume();
        assertState(host.get(), "getForegroundDispatchState", "[]", "active");
    }

    @Test public void backgroundQueriesCannotResumeTheHost() throws Exception {
        assertState(host.get(), "acquireForegroundDispatch", "[\"screen\"]", "active");
        host.pause().stop();
        for (int index = 0; index < 3; index++) {
            call(host.get(), "getCapabilities", "[]");
            assertState(host.get(), "getForegroundDispatchState", "[]", "paused");
        }
        host.restart().start().resume();
        assertState(host.get(), "getForegroundDispatchState", "[]", "active");
    }

    @Test public void previousActivityDestroyCannotCloseReplacement() throws Exception {
        assertState(host.get(), "acquireForegroundDispatch", "[\"screen\"]", "active");
        host.pause().stop();
        ActivityController<HostActivity> replacement = newHost();
        assertState(replacement.get(), "getForegroundDispatchState", "[]", "active");
        assertEquals(0, host.get().lifecycle.getObserverCount());
        host.destroy();
        assertState(replacement.get(), "getForegroundDispatchState", "[]", "active");
        replacement.pause();
        assertState(replacement.get(), "getForegroundDispatchState", "[]", "paused");
        replacement.resume();
    }

    @Test public void capabilitiesBeforeHostDoNotPreventLaterBinding() throws Exception {
        assertTrue(call(null, "getCapabilities", "[]").getBoolean("ok"));
        assertEquals(0, host.get().lifecycle.getObserverCount());
        assertState(host.get(), "acquireForegroundDispatch", "[\"screen\"]", "active");
        call(null, "getCapabilities", "[]");
        assertEquals(1, host.get().lifecycle.getObserverCount());
    }

    @Test public void destroyedHostCannotBeRebound() throws Exception {
        assertState(host.get(), "acquireForegroundDispatch", "[\"screen\"]", "active");
        host.pause().stop().destroy();
        JSONObject result = call(host.get(), "startScan", "[{}]");
        assertFalse(result.getBoolean("ok"));
        assertEquals("INTERNAL_ERROR", result.getJSONObject("error").getString("code"));
        assertEquals(0, host.get().lifecycle.getObserverCount());
    }

    @Test public void workerInvocationBindsAndCompletesOnMain() throws Exception {
        AtomicReference<String> result = new AtomicReference<>();
        AtomicReference<Looper> callbackLooper = new AtomicReference<>();
        Thread worker = new Thread(() -> bridge.invokeJson(host.get(), host.get().getApplication(),
                "acquireForegroundDispatch", "[\"screen\"]", json -> {
                    callbackLooper.set(Looper.myLooper());
                    result.set(json);
                }));
        worker.start();
        worker.join();
        assertNull(result.get());
        shadowOf(Looper.getMainLooper()).idle();
        assertEquals(Looper.getMainLooper(), callbackLooper.get());
        assertEquals("active", new JSONObject(result.get()).getJSONObject("data").getString("state"));
    }

    @Test public void pauseSettlesPendingReadAndReleasesItsPresentation() throws Exception {
        AtomicReference<String> result = new AtomicReference<>();
        bridge.invokeJson(host.get(), host.get().getApplication(), "startScan", "[{}]", result::set);
        shadowOf(Looper.getMainLooper()).idle();
        assertTrue(call(host.get(), "isScanning", "[]").getBoolean("data"));
        host.pause();
        shadowOf(Looper.getMainLooper()).idle();
        assertFalse(call(host.get(), "isScanning", "[]").getBoolean("data"));
        assertEquals("USER_CANCELLED", new JSONObject(result.get()).getJSONObject("error").getString("code"));
        assertEquals(0, call(host.get(), "getPresentationState", "[]").getJSONObject("data")
                .getJSONArray("activePresentationIds").length());
        host.resume();
    }

    private ActivityController<HostActivity> newHost() {
        ActivityController<HostActivity> controller = Robolectric.buildActivity(HostActivity.class).setup();
        hosts.add(controller);
        return controller;
    }

    private JSONObject call(Activity activity, String method, String arguments) throws Exception {
        AtomicReference<String> result = new AtomicReference<>();
        bridge.invokeJson(activity, host.get().getApplication(), method, arguments, result::set);
        shadowOf(Looper.getMainLooper()).idle();
        assertNotNull(result.get());
        return new JSONObject(result.get());
    }

    private void assertState(Activity activity, String method, String arguments, String state) throws Exception {
        JSONObject result = call(activity, method, arguments);
        assertTrue(result.toString(), result.getBoolean("ok"));
        assertEquals(state, result.getJSONObject("data").getString("state"));
    }
}
