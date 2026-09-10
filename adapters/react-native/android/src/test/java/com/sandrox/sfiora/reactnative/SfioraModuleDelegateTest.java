package com.sandrox.sfiora.reactnative;

import static org.junit.Assert.*;
import static org.robolectric.Shadows.shadowOf;

import android.app.Activity;
import android.content.pm.PackageManager;
import android.nfc.NfcAdapter;
import android.nfc.Tag;
import android.nfc.tech.Ndef;
import android.os.Looper;
import com.facebook.react.bridge.Arguments;
import com.facebook.react.bridge.BridgeReactContext;
import com.facebook.react.bridge.JavaOnlyMap;
import com.facebook.react.bridge.Promise;
import com.facebook.react.bridge.ReactApplicationContext;
import com.facebook.react.bridge.WritableNativeMap;
import java.lang.reflect.Proxy;
import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;
import java.util.function.BooleanSupplier;
import org.junit.After;
import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.Robolectric;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.annotation.Config;
import org.robolectric.annotation.Implementation;
import org.robolectric.annotation.Implements;
import org.robolectric.shadows.ShadowBasicTagTechnology;
import org.robolectric.shadows.ShadowNfcAdapter;
import org.robolectric.util.ReflectionHelpers;
import org.robolectric.util.ReflectionHelpers.ClassParameter;

/** Actual RN UI queue, lifecycle, delegate and native controllers; no JS VM or NFC hardware. */
@RunWith(RobolectricTestRunner.class)
@Config(sdk = 28, shadows = {SfioraModuleDelegateTest.MapTransport.class, SfioraModuleDelegateTest.BlockedNdef.class})
public class SfioraModuleDelegateTest {
    private ReactApplicationContext context;
    private SfioraModuleDelegate delegate;
    private ShadowNfcAdapter adapter;
    private final List<Reply> replies = new ArrayList<>();

    @Before public void setUp() {
        BlockedNdef.readEntered = new CountDownLatch(1);
        BlockedNdef.gate = new CountDownLatch(1);
        Activity activity = Robolectric.buildActivity(Activity.class).setup().get();
        shadowOf(activity.getPackageManager()).setSystemFeature(PackageManager.FEATURE_NFC, true);
        adapter = shadowOf(NfcAdapter.getDefaultAdapter(activity));
        adapter.setEnabled(true);
        context = new BridgeReactContext(activity.getApplicationContext());
        context.onHostResume(activity);
        delegate = new SfioraModuleDelegate(context);
    }

    @After public void tearDown() throws Exception {
        BlockedNdef.gate.countDown();
        delegate.invalidate();
        await(this::isIdle);
        for (Reply reply : replies) assertFalse("a bridge reply ran off the UI thread", reply.offMain);
    }

    @Test public void queuedScanAfterPauseIsRejectedBeforeOpeningAController() throws Exception {
        Reply scan = reply();
        fromNativeModules(() -> delegate.startScan(options(), scan.promise));
        assertEquals(0, scan.calls);
        context.onHostPause();
        shadowOf(Looper.getMainLooper()).idle();
        assertEquals("INTERNAL_ERROR", scan.code);
        assertEquals(1, scan.calls);
        Reply state = reply(); delegate.isScanning(state.promise);
        shadowOf(Looper.getMainLooper()).idle();
        assertEquals(false, state.value);
    }

    @Test public void pauseAndActivityReplacementKeepClosingSessionBusyUntilIoExits() throws Exception {
        Reply first = reply();
        fromNativeModules(() -> delegate.startScan(options(), first.promise));
        shadowOf(Looper.getMainLooper()).idle();
        adapter.dispatchTagDiscovered(ShadowNfcAdapter.createMockTag());
        assertTrue(BlockedNdef.readEntered.await(5, TimeUnit.SECONDS));
        context.onHostPause();
        Activity replacement = Robolectric.buildActivity(Activity.class).setup().get();
        context.onHostResume(replacement);
        Reply state = reply(); Reply second = reply();
        fromNativeModules(() -> { delegate.isScanning(state.promise); delegate.startScan(options(), second.promise); });
        assertEquals(0, state.calls);
        shadowOf(Looper.getMainLooper()).idle();
        assertEquals(true, state.value);
        assertEquals("SCAN_BUSY", second.code);
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(5));
        assertEquals("USER_CANCELLED", first.code);
        assertEquals(1, first.calls);
        BlockedNdef.gate.countDown();
        await(this::isIdle);
        Reply restarted = reply(); delegate.startScan(options(), restarted.promise);
        Reply restartedState = reply(); delegate.isScanning(restartedState.promise);
        shadowOf(Looper.getMainLooper()).idle();
        assertEquals(true, restartedState.value);
        context.onHostDestroy();
        await(() -> restarted.calls == 1);
        assertEquals("USER_CANCELLED", restarted.code);
        assertEquals(1, first.calls);
    }

    @Test public void invalidationIsOrderedWithAllQueuedEntryPoints() throws Exception {
        Reply scan = reply(), write = reply(), initialize = reply(), capabilities = reply();
        fromNativeModules(() -> {
            delegate.invalidate();
            delegate.startScan(null, scan.promise);
            delegate.writeNdef(null, null, write.promise);
            delegate.initializeNdef(null, null, null, initialize.promise);
            delegate.getCapabilities(capabilities.promise);
        });
        for (Reply value : replies) assertEquals(0, value.calls);
        context.onHostDestroy();
        shadowOf(Looper.getMainLooper()).idle();
        for (Reply value : replies) {
            assertEquals(1, value.calls);
            assertEquals("INTERNAL_ERROR", value.code);
        }
    }

    private Reply reply() { Reply value = new Reply(); replies.add(value); return value; }
    private static JavaOnlyMap options() { return JavaOnlyMap.of("android", Map.of("presentation", "none")); }
    private boolean isIdle() {
        Reply reading = new Reply(); Reply writing = new Reply();
        delegate.isScanning(reading.promise); delegate.isWriting(writing.promise);
        shadowOf(Looper.getMainLooper()).idle();
        return Boolean.FALSE.equals(reading.value) && Boolean.FALSE.equals(writing.value);
    }
    private static void fromNativeModules(Runnable action) throws Exception {
        AtomicReference<Throwable> failure = new AtomicReference<>();
        Thread thread = new Thread(action, "test-native-modules");
        thread.setUncaughtExceptionHandler((source, error) -> failure.set(error));
        thread.start(); thread.join(5000); assertFalse(thread.isAlive());
        if (failure.get() != null) throw new AssertionError(failure.get());
    }
    private static void await(BooleanSupplier predicate) throws Exception {
        long deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(5);
        while (!predicate.getAsBoolean() && System.nanoTime() < deadline) {
            shadowOf(Looper.getMainLooper()).idle(); Thread.sleep(5);
        }
        shadowOf(Looper.getMainLooper()).idle(); assertTrue(predicate.getAsBoolean());
    }
    private static final class Reply {
        int calls; Object value; String code; boolean offMain;
        final Promise promise = (Promise) Proxy.newProxyInstance(Promise.class.getClassLoader(), new Class<?>[] {Promise.class},
                (proxy, method, arguments) -> {
                    if (method.getName().equals("resolve") || method.getName().equals("reject")) {
                        calls++; offMain |= Looper.myLooper() != Looper.getMainLooper();
                        if (method.getName().equals("resolve")) value = arguments[0]; else code = (String) arguments[0];
                    }
                    return null;
                });
    }
    @Implements(Arguments.class)
    public static class MapTransport {
        // These tests observe Promise completion, codes and thread identity; JNI
        // map allocation belongs to the JS VM and is deliberately not exercised.
        @Implementation protected static WritableNativeMap makeNativeMap(Map<String, Object> values) { return null; }
    }
    @Implements(Ndef.class)
    public static class BlockedNdef extends ShadowBasicTagTechnology {
        static CountDownLatch readEntered, gate;
        @Implementation protected void __constructor__(Tag tag) { }
        @Implementation protected static Ndef get(Tag tag) { return ReflectionHelpers.callConstructor(Ndef.class, ClassParameter.from(Tag.class, tag)); }
        @Implementation protected void connect() { }
        @Implementation protected boolean isWritable() { return true; }
        @Implementation protected boolean canMakeReadOnly() { return true; }
        @Implementation protected int getMaxSize() { return 4096; }
        @Implementation protected String getType() { return Ndef.NFC_FORUM_TYPE_2; }
        @Implementation protected android.nfc.NdefMessage getNdefMessage() {
            readEntered.countDown(); block(); return null;
        }
        @Implementation protected void close() { block(); }
        private static void block() {
            boolean interrupted = false;
            while (true) { try { gate.await(); break; } catch (InterruptedException error) { interrupted = true; } }
            if (interrupted) Thread.currentThread().interrupt();
        }
    }
}
