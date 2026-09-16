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

    @Test public void queuedReadCannotStartAfterPause() throws Exception {
        assertQueuedOperationRejectedAfterPause("startScan");
    }

    @Test public void queuedWriteCannotStartAfterPause() throws Exception {
        assertQueuedOperationRejectedAfterPause("writeNdef");
    }

    @Test public void queuedInitializationCannotStartAfterPause() throws Exception {
        assertQueuedOperationRejectedAfterPause("initializeNdef");
    }

    @Test public void queuedOldQueryCannotCancelReplacementRead() throws Exception {
        assertOldQueryCannotCancelReplacement("startScan");
    }

    @Test public void queuedOldQueryCannotCancelReplacementWrite() throws Exception {
        assertOldQueryCannotCancelReplacement("writeNdef");
    }

    @Test public void firstBackgroundCallsRejectOperationsButAllowCleanup() throws Exception {
        host.pause();
        for (String method : new String[] {"startScan", "writeNdef", "initializeNdef"}) {
            JSONObject result = call(host.get(), method, operationArguments(method));
            assertFalse(result.getBoolean("ok"));
            assertEquals("INTERNAL_ERROR", result.getJSONObject("error").getString("code"));
        }
        assertState(host.get(), "acquireForegroundDispatch", "[\"screen\"]", "paused");
        assertTrue(call(host.get(), "getCapabilities", "[]").getBoolean("ok"));
        assertTrue(call(host.get(), "cancelScan", "[]").getBoolean("ok"));
        assertTrue(call(host.get(), "cancelWrite", "[]").getBoolean("ok"));
        assertState(host.get(), "releaseForegroundDispatch", "[\"screen\"]", "disabled");
        assertFalse(call(host.get(), "isScanning", "[]").getBoolean("data"));
        assertFalse(call(host.get(), "isWriting", "[]").getBoolean("data"));
        assertNull(shadowOf(NfcAdapter.getDefaultAdapter(host.get())).getEnabledActivity());
        host.resume();
    }

    @Test public void callsFromRetiredHostCannotTakeOverAnActiveReplacement() throws Exception {
        assertState(host.get(), "acquireForegroundDispatch", "[\"old-screen\"]", "active");
        host.pause().stop();
        ActivityController<HostActivity> replacement = newHost();
        assertState(replacement.get(), "acquireForegroundDispatch", "[\"new-screen\"]", "active");
        AtomicReference<String> operation = new AtomicReference<>();
        bridge.invokeJson(replacement.get(), replacement.get().getApplication(), "writeNdef",
                operationArguments("writeNdef"), operation::set);
        shadowOf(Looper.getMainLooper()).idle();
        assertTrue(call(replacement.get(), "isWriting", "[]").getBoolean("data"));

        // These calls enter after B was bound, so a queue-generation check alone
        // cannot identify A as retired. Its actual lifecycle must also be checked.
        assertTrue(call(host.get(), "getCapabilities", "[]").getBoolean("ok"));
        assertTrue(call(host.get(), "getForegroundDispatchState", "[]").getBoolean("ok"));
        assertTrue(call(host.get(), "releaseForegroundDispatch", "[\"old-screen\"]").getBoolean("ok"));
        for (String method : new String[] {"cancelScan", "cancelWrite", "acquireForegroundDispatch"}) {
            String args = method.equals("acquireForegroundDispatch") ? "[\"retired-screen\"]" : "[]";
            assertFalse(call(host.get(), method, args).getBoolean("ok"));
        }
        for (String method : new String[] {"startScan", "writeNdef", "initializeNdef"}) {
            assertFalse(call(host.get(), method, operationArguments(method)).getBoolean("ok"));
        }
        assertNull("Old calls must not settle the replacement's write", operation.get());
        assertTrue(call(replacement.get(), "isWriting", "[]").getBoolean("data"));
        assertEquals(0, host.get().lifecycle.getObserverCount());
        assertEquals(1, replacement.get().lifecycle.getObserverCount());
        call(replacement.get(), "cancelWrite", "[]");
        awaitResult(operation);
        assertEquals("USER_CANCELLED", new JSONObject(operation.get()).getJSONObject("error").getString("code"));
        assertState(replacement.get(), "releaseForegroundDispatch", "[\"new-screen\"]", "disabled");
    }

    @Test public void queuedFirstCallsToTheSameHostRemainUsable() throws Exception {
        AtomicReference<String> capabilities = enqueue(host.get(), "getCapabilities", "[]");
        AtomicReference<String> operation = enqueue(host.get(), "startScan", operationArguments("startScan"));
        shadowOf(Looper.getMainLooper()).idle();
        assertTrue(new JSONObject(capabilities.get()).getBoolean("ok"));
        assertNull(operation.get());
        assertTrue(call(host.get(), "isScanning", "[]").getBoolean("data"));
        call(host.get(), "cancelScan", "[]");
        awaitResult(operation);
        assertEquals("USER_CANCELLED", new JSONObject(operation.get()).getJSONObject("error").getString("code"));
    }

    @Test public void previousHostCanBindAgainAfterActuallyReturningToForeground() throws Exception {
        assertState(host.get(), "acquireForegroundDispatch", "[\"screen\"]", "active");
        host.pause().stop();
        ActivityController<HostActivity> replacement = newHost();
        assertState(replacement.get(), "getForegroundDispatchState", "[]", "active");
        replacement.pause().stop();
        host.restart().start().resume();
        assertState(host.get(), "getForegroundDispatchState", "[]", "active");
        assertEquals(1, host.get().lifecycle.getObserverCount());
        assertEquals(0, replacement.get().lifecycle.getObserverCount());
        AtomicReference<String> operation = new AtomicReference<>();
        bridge.invokeJson(host.get(), host.get().getApplication(), "startScan", "[{}]", operation::set);
        shadowOf(Looper.getMainLooper()).idle();
        assertTrue(call(host.get(), "isScanning", "[]").getBoolean("data"));
        call(host.get(), "cancelScan", "[]");
        awaitResult(operation);
        assertEquals("USER_CANCELLED", new JSONObject(operation.get()).getJSONObject("error").getString("code"));
    }

    @Test public void foregroundWriteAndInitializationStillStartAndCancel() throws Exception {
        for (String method : new String[] {"writeNdef", "initializeNdef"}) {
            AtomicReference<String> operation = new AtomicReference<>();
            bridge.invokeJson(host.get(), host.get().getApplication(), method, operationArguments(method), operation::set);
            shadowOf(Looper.getMainLooper()).idle();
            assertNull(operation.get());
            assertTrue(call(host.get(), "isWriting", "[]").getBoolean("data"));
            call(host.get(), "cancelWrite", "[]");
            awaitResult(operation);
            assertEquals("USER_CANCELLED", new JSONObject(operation.get()).getJSONObject("error").getString("code"));
            assertFalse(call(host.get(), "isWriting", "[]").getBoolean("data"));
        }
    }

    private void assertQueuedOperationRejectedAfterPause(String method) throws Exception {
        assertState(host.get(), "acquireForegroundDispatch", "[\"screen\"]", "active");
        AtomicReference<String> result = enqueue(host.get(), method, operationArguments(method));
        // Deliver the lifecycle event without ActivityController draining the queued call.
        host.get().lifecycle.handleLifecycleEvent(Lifecycle.Event.ON_PAUSE);
        shadowOf(Looper.getMainLooper()).idle();
        assertNotNull("A background request must fail without starting an NFC session", result.get());
        assertFalse(new JSONObject(result.get()).getBoolean("ok"));
        assertEquals("INTERNAL_ERROR", new JSONObject(result.get()).getJSONObject("error").getString("code"));
        assertFalse(call(host.get(), "isScanning", "[]").getBoolean("data"));
        assertFalse(call(host.get(), "isWriting", "[]").getBoolean("data"));
        assertEquals(0, call(host.get(), "getPresentationState", "[]").getJSONObject("data")
                .getJSONArray("activePresentationIds").length());
        assertFalse(shadowOf(NfcAdapter.getDefaultAdapter(host.get())).isInReaderMode());
        assertSame(host.get(), shadowOf(NfcAdapter.getDefaultAdapter(host.get())).getDisabledActivity());
        host.get().lifecycle.handleLifecycleEvent(Lifecycle.Event.ON_RESUME);
    }

    private void assertOldQueryCannotCancelReplacement(String method) throws Exception {
        assertState(host.get(), "acquireForegroundDispatch", "[\"screen\"]", "active");
        ActivityController<HostActivity> replacement = newHost();
        AtomicReference<String> oldQuery = enqueue(host.get(), "getCapabilities", "[]");
        host.get().lifecycle.handleLifecycleEvent(Lifecycle.Event.ON_PAUSE);
        host.get().lifecycle.handleLifecycleEvent(Lifecycle.Event.ON_STOP);
        AtomicReference<String> operation = new AtomicReference<>();
        bridge.invokeJson(replacement.get(), replacement.get().getApplication(),
                method, operationArguments(method), operation::set);
        assertNull("The old query must still be queued after the replacement starts", oldQuery.get());
        shadowOf(Looper.getMainLooper()).idle();

        assertNotNull(oldQuery.get());
        assertTrue(new JSONObject(oldQuery.get()).getBoolean("ok"));
        assertNull("An old query must not cancel the replacement operation", operation.get());
        assertTrue(call(replacement.get(), method.equals("startScan") ? "isScanning" : "isWriting", "[]")
                .getBoolean("data"));
        assertEquals(0, host.get().lifecycle.getObserverCount());
        assertEquals(1, replacement.get().lifecycle.getObserverCount());
        replacement.pause();
        shadowOf(Looper.getMainLooper()).idle();
        assertEquals("USER_CANCELLED", new JSONObject(operation.get()).getJSONObject("error").getString("code"));
        replacement.resume();
    }

    private AtomicReference<String> enqueue(Activity activity, String method, String arguments)
            throws InterruptedException {
        AtomicReference<String> result = new AtomicReference<>();
        Thread worker = new Thread(() -> bridge.invokeJson(activity, host.get().getApplication(),
                method, arguments, result::set));
        worker.start();
        worker.join();
        assertNull(result.get());
        return result;
    }

    private static String operationArguments(String method) {
        String message = "{\"records\":[{\"kind\":\"text\",\"text\":\"lifecycle\",\"languageCode\":\"en\"}]}";
        if (method.equals("startScan")) return "[{}]";
        if (method.equals("writeNdef")) return "[" + message + ",{}]";
        String initialization = "{\"records\":[{\"kind\":\"external\",\"domain\":\"sfiora.test\","
                + "\"type\":\"initialized\",\"payloadBase64\":\"bGlmZWN5Y2xl\"}]}";
        return "[" + initialization + ",{\"domain\":\"sfiora.test\",\"type\":\"initialized\"},{}]";
    }

    private static void awaitResult(AtomicReference<String> result) throws InterruptedException {
        long deadline = System.nanoTime() + java.util.concurrent.TimeUnit.SECONDS.toNanos(5);
        while (result.get() == null && System.nanoTime() < deadline) {
            shadowOf(Looper.getMainLooper()).idle();
            if (result.get() == null) Thread.sleep(10);
        }
        assertNotNull("The NFC operation must complete after cancellation", result.get());
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
