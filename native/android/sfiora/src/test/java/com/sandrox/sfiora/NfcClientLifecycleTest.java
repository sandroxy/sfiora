package com.sandrox.sfiora;

import static org.junit.Assert.*;
import static org.robolectric.Shadows.shadowOf;

import android.app.Activity;
import android.content.pm.PackageManager;
import android.nfc.NfcAdapter;
import android.nfc.Tag;
import android.nfc.TagLostException;
import android.nfc.tech.MifareClassic;
import android.nfc.tech.MifareUltralight;
import android.nfc.tech.Ndef;
import android.nfc.tech.NfcA;
import android.os.Looper;
import java.io.IOException;
import java.time.Duration;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Map;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;
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
import org.robolectric.shadows.ShadowNfcAdapter;
import org.robolectric.shadows.ShadowBasicTagTechnology;
import org.robolectric.util.ReflectionHelpers;
import org.robolectric.util.ReflectionHelpers.ClassParameter;

/** Drives the production client; only Android's tag technology is substituted. */
@RunWith(RobolectricTestRunner.class)
@Config(sdk = 28, shadows = {
        NfcClientLifecycleTest.ControlledNdef.class,
        NfcClientLifecycleTest.ControlledUltralight.class,
        NfcClientLifecycleTest.ControlledNfcA.class,
        NfcClientLifecycleTest.ControlledClassic.class
})
public class NfcClientLifecycleTest {
    private Activity activity;
    private NfcClient client;
    private ShadowNfcAdapter adapter;
    private final List<NfcClient> clients = new ArrayList<>();
    private final List<NfcError> failures = new ArrayList<>();
    private final List<NfcTagSnapshot> successes = new ArrayList<>();
    private final List<Boolean> states = new ArrayList<>();
    private final NfcClient.ReadCallback readCallback = new NfcClient.ReadCallback() {
        @Override public void onSuccess(NfcTagSnapshot snapshot) {
            assertEquals(Looper.getMainLooper(), Looper.myLooper());
            successes.add(snapshot);
        }
        @Override public void onFailure(NfcError error) {
            assertEquals(Looper.getMainLooper(), Looper.myLooper());
            failures.add(error);
        }
        @Override public void onStateChanged(boolean reading) { states.add(reading); }
    };

    @Before public void setUp() {
        TechnologyConnection.reset();
        ControlledNdef.resetPlan();
        activity = Robolectric.buildActivity(Activity.class).setup().get();
        shadowOf(activity.getPackageManager()).setSystemFeature(PackageManager.FEATURE_NFC, true);
        adapter = shadowOf(NfcAdapter.getDefaultAdapter(activity));
        adapter.setEnabled(true);
        client = newClient();
    }

    private NfcClient newClient() {
        NfcClient value = new NfcClient(activity);
        clients.add(value);
        return value;
    }

    @After public void tearDown() throws Exception {
        ControlledNdef.connectGate.countDown();
        ControlledNdef.readGate.countDown();
        ControlledNdef.closeGate.countDown();
        TechnologyConnection.readGate.countDown();
        for (NfcClient value : clients) value.close();
        await(() -> clients.stream().noneMatch(value -> value.isReading() || value.isWriting()));
    }

    @Test public void cancelDoesNotBlockMainOrReleaseLeaseBeforeIoAndClose() throws Exception {
        ControlledNdef.readGate = new CountDownLatch(1);
        ControlledNdef.closeGate = new CountDownLatch(1);
        startRead();
        awaitLatch(ControlledNdef.readEntered);
        client.cancelRead();
        awaitLatch(ControlledNdef.closeEntered);
        assertTrue(client.isReading());
        assertEquals(Collections.singletonList(true), states);
        newClient().startRead(configuration(), readCallback);
        assertEquals(NfcErrorCode.SCAN_BUSY, failures.get(0).getCode());
        failures.clear();

        // The business deadline must not announce idle while Android close is blocked.
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(5));
        assertEquals(NfcErrorCode.USER_CANCELLED, failures.get(0).getCode());
        assertTrue(client.isReading());
        assertEquals(0, successes.size());
        ControlledNdef.readGate.countDown();
        ControlledNdef.closeGate.countDown();
        await(() -> !client.isReading());
        assertEquals(1, failures.size());
        assertEquals(0, successes.size());
        assertEquals(List.of(true, false), states);
        assertFalse(ControlledNdef.closeOnMain);
    }

    @Test public void staleTagCookieDuringCloseDoesNotEscapeOrStrandLease() throws Exception {
        ControlledNdef.failClose = true;
        startRead();
        await(() -> !client.isReading());
        assertEquals(1, successes.size());
        assertTrue(failures.isEmpty());
        newClient().startRead(configuration(), readCallback);
        assertTrue(failures.isEmpty());
    }

    @Test public void operationTimeoutDiscardsTheLateReadAndOldDiscovery() throws Exception {
        ControlledNdef.readGate = new CountDownLatch(1);
        startRead();
        NfcAdapter.ReaderCallback oldReader = ReflectionHelpers.getField(adapter, "readerCallback");
        awaitLatch(ControlledNdef.readEntered);
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(1));
        ControlledNdef.readGate.countDown();
        await(() -> !client.isReading());
        assertEquals(NfcErrorCode.SCAN_TIMEOUT, failures.get(0).getCode());
        assertTrue(successes.isEmpty());
        int oldReadCount = ControlledNdef.readCount.get();
        client.startRead(configuration(), readCallback);
        oldReader.onTagDiscovered(ShadowNfcAdapter.createMockTag());
        shadowOf(Looper.getMainLooper()).idle();
        assertEquals(oldReadCount, ControlledNdef.readCount.get());
        adapter.dispatchTagDiscovered(ShadowNfcAdapter.createMockTag());
        await(() -> !client.isReading());
        assertEquals(1, successes.size());
        assertEquals(1, failures.size());
    }

    @Test public void initializationUsesLiveEmptyMessageInsteadOfCachedMarker() throws Exception {
        NdefExternalType marker = new NdefExternalType("io.sfiora", "initialized");
        NdefMessage message = new NdefMessage(Collections.singletonList(
                NdefRecord.external("io.sfiora", "initialized", new byte[] {1, 2, 3})));
        ControlledNdef.live = null;
        ControlledNdef.cached = AndroidNdefCodec.toPlatform(message);
        List<NfcInitializationResult> results = new ArrayList<>();
        client.startInitialize(message, marker, NfcWriteConfiguration.builder().build(),
                new NfcClient.InitializationCallback() {
                    @Override public void onSuccess(NfcInitializationResult result) { results.add(result); }
                    @Override public void onFailure(NfcError error) { failures.add(error); }
                });
        adapter.dispatchTagDiscovered(ShadowNfcAdapter.createMockTag());
        await(() -> !client.isWriting());
        assertTrue(failures.isEmpty());
        assertEquals(1, results.size());
        assertEquals(1, ControlledNdef.writeCount.get());
        assertEquals(0, ControlledNdef.cachedReadCount.get());
    }

    @Test public void removingTagAfterWriteNeverReportsVerifiedSuccess() throws Exception {
        ControlledNdef.failVerification = true;
        NdefMessage message = new NdefMessage(Collections.singletonList(NdefRecord.text("hello", "en")));
        AtomicInteger writesSucceeded = new AtomicInteger();
        client.startWrite(message, NfcWriteConfiguration.builder().build(), new NfcClient.WriteCallback() {
            @Override public void onSuccess(NfcWriteResult result) { writesSucceeded.incrementAndGet(); }
            @Override public void onFailure(NfcError error) { failures.add(error); }
        });
        adapter.dispatchTagDiscovered(ShadowNfcAdapter.createMockTag());
        await(() -> !client.isWriting());
        assertEquals(0, writesSucceeded.get());
        assertEquals(NfcErrorCode.WRITE_VERIFICATION_FAILED, failures.get(0).getCode());
        assertEquals(1, ControlledNdef.writeCount.get());
    }

    @Test public void cancelRacingWithConnectRequiresAFinalCloseAfterWorkerExit() throws Exception {
        ControlledNdef.connectGate = new CountDownLatch(1);
        startRead();
        awaitLatch(ControlledNdef.connectEntered);
        client.cancelRead();
        awaitLatch(ControlledNdef.closeEntered);
        assertTrue(client.isReading());
        ControlledNdef.connectGate.countDown();
        await(() -> !client.isReading());
        assertEquals(2, ControlledNdef.closeCount.get());
        assertEquals(1, failures.size());
        assertEquals(NfcErrorCode.USER_CANCELLED, failures.get(0).getCode());
        assertTrue(successes.isEmpty());
    }

    @Test public void stopSilencesAPendingCancellationWithoutFakingIdle() throws Exception {
        ControlledNdef.readGate = new CountDownLatch(1);
        ControlledNdef.closeGate = new CountDownLatch(1);
        startRead();
        awaitLatch(ControlledNdef.readEntered);
        client.cancelRead();
        client.stop();
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(5));
        assertTrue(client.isReading());
        assertTrue(failures.isEmpty());
        ControlledNdef.readGate.countDown();
        ControlledNdef.closeGate.countDown();
        await(() -> !client.isReading());
        assertTrue(failures.isEmpty());
        assertTrue(successes.isEmpty());
    }

    private void startRead() {
        client.startRead(configuration(), readCallback);
        adapter.dispatchTagDiscovered(ShadowNfcAdapter.createMockTag());
    }

    @Test public void ndefClosesBeforeUltralightProbeAndFinalCleanupDoesNotCloseItAgain() throws Exception {
        assertDeepRead("ultralight", "mifareUltralightMemory");
    }

    @Test public void ndefClosesBeforeNfcAProbe() throws Exception {
        assertDeepRead("nfcA", "nfcAType2Memory");
    }

    @Test public void ndefClosesBeforeClassicProbe() throws Exception {
        assertDeepRead("classic", "mifareClassicDefaultKeys");
    }

    private void assertDeepRead(String technology, String resultKey) throws Exception {
        TechnologyConnection.probe = technology;
        TechnologyConnection.readGate = new CountDownLatch(1);
        startDeepRead();
        await(() -> TechnologyConnection.readEntered.getCount() == 0 || !client.isReading());
        assertEquals("deep read never reached the technology's I/O", 0, TechnologyConnection.readEntered.getCount());
        assertTrue(client.isReading());
        assertEquals(1, ControlledNdef.closeCount.get());
        assertEquals(technology, TechnologyConnection.connected);
        assertTrue(successes.isEmpty());
        TechnologyConnection.readGate.countDown();
        await(() -> !client.isReading());
        assertTrue(failures.isEmpty());
        assertEquals(1, successes.size());
        Map<?, ?> probe = (Map<?, ?>) successes.get(0).getReadOnlyProbes().get(resultKey);
        assertFalse(probe.containsKey("error"));
        if ("classic".equals(technology)) {
            Map<?, ?> sector = (Map<?, ?>) ((List<?>) probe.get("sectors")).get(0);
            Map<?, ?> block = (Map<?, ?>) ((List<?>) sector.get("blocks")).get(0);
            assertEquals("00000000000000000000000000000000", block.get("hex"));
        } else {
            assertEquals(16, probe.get("bytesRead"));
        }
        assertEquals(1, ControlledNdef.closeCount.get());
        assertEquals(0, TechnologyConnection.conflicts.get());
        assertNull(TechnologyConnection.connected);
        assertFalse(ControlledNdef.closeOnMain);
    }

    @Test public void cancellationDuringNdefPhaseCloseNeverStartsProbeOrReleasesLeaseEarly() throws Exception {
        TechnologyConnection.probe = "ultralight";
        ControlledNdef.closeGate = new CountDownLatch(1);
        startDeepRead();
        awaitLatch(ControlledNdef.closeEntered);
        client.cancelRead();
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(5));
        assertTrue(client.isReading());
        assertEquals(0, TechnologyConnection.connectCount.get());
        assertEquals(NfcErrorCode.USER_CANCELLED, failures.get(0).getCode());
        newClient().startRead(configuration(), readCallback);
        assertEquals(NfcErrorCode.SCAN_BUSY, failures.get(1).getCode());
        ControlledNdef.closeGate.countDown();
        await(() -> !client.isReading());
        assertEquals(0, TechnologyConnection.connectCount.get());
        assertTrue(successes.isEmpty());
        assertEquals(2, failures.size());
    }

    @Test public void failedNdefPhaseCloseDoesNotAttemptAnotherTechnology() throws Exception {
        TechnologyConnection.probe = "ultralight";
        ControlledNdef.failClose = true;
        startDeepRead();
        await(() -> !client.isReading());
        assertEquals(0, TechnologyConnection.connectCount.get());
        assertTrue(successes.isEmpty());
        assertEquals(NfcErrorCode.READ_FAILED, failures.get(0).getCode());
    }

    private void startDeepRead() {
        client.startRead(NfcReadConfiguration.builder().mode(NfcReadMode.AUTOMATIC)
                .deepReadEnabled(true).timeoutMillis(30_000).build(), readCallback);
        adapter.dispatchTagDiscovered(ShadowNfcAdapter.createMockTag());
    }

    private static NfcReadConfiguration configuration() {
        return NfcReadConfiguration.builder().mode(NfcReadMode.NDEF).timeoutMillis(1000).build();
    }

    private static void awaitLatch(CountDownLatch latch) throws Exception {
        assertTrue("worker did not reach the injected boundary", latch.await(5, TimeUnit.SECONDS));
    }

    private static void await(BooleanSupplier condition) throws Exception {
        long deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(5);
        while (!condition.getAsBoolean() && System.nanoTime() < deadline) {
            shadowOf(Looper.getMainLooper()).idle();
            Thread.sleep(5);
        }
        shadowOf(Looper.getMainLooper()).idle();
        assertTrue("client did not reach the expected state", condition.getAsBoolean());
    }

    @Implements(Ndef.class)
    public static class ControlledNdef extends ShadowBasicTagTechnology {
        static CountDownLatch connectEntered, connectGate, readEntered, closeEntered, readGate, closeGate;
        static AtomicInteger readCount, writeCount, cachedReadCount, closeCount;
        static volatile boolean failClose, failVerification, closeOnMain;
        static volatile android.nfc.NdefMessage live, cached;
        static void resetPlan() {
            connectEntered = new CountDownLatch(1); connectGate = new CountDownLatch(0);
            closeCount = new AtomicInteger();
            readEntered = new CountDownLatch(1); closeEntered = new CountDownLatch(1);
            readGate = new CountDownLatch(0); closeGate = new CountDownLatch(0);
            readCount = new AtomicInteger(); writeCount = new AtomicInteger(); cachedReadCount = new AtomicInteger();
            failClose = false; failVerification = false; closeOnMain = false;
            live = new android.nfc.NdefMessage(new android.nfc.NdefRecord[] {
                    android.nfc.NdefRecord.createTextRecord("en", "hello")});
            cached = live;
        }
        @Implementation protected void __constructor__(Tag tag) { }
        @Implementation protected static Ndef get(Tag tag) {
            return ReflectionHelpers.callConstructor(Ndef.class, ClassParameter.from(Tag.class, tag));
        }
        @Implementation protected void connect() throws IOException {
            connectEntered.countDown(); unblock(connectGate); TechnologyConnection.connect("ndef");
        }
        @Implementation protected boolean isWritable() { return true; }
        @Implementation protected boolean canMakeReadOnly() { return true; }
        @Implementation protected int getMaxSize() { return 4096; }
        @Implementation protected String getType() { return Ndef.NFC_FORUM_TYPE_2; }
        @Implementation protected android.nfc.NdefMessage getCachedNdefMessage() {
            cachedReadCount.incrementAndGet(); return cached;
        }
        @Implementation protected android.nfc.NdefMessage getNdefMessage() throws IOException {
            readCount.incrementAndGet(); readEntered.countDown(); unblock(readGate);
            if (failVerification && writeCount.get() > 0) throw new TagLostException("removed after write");
            return live;
        }
        @Implementation protected void writeNdefMessage(android.nfc.NdefMessage message) {
            writeCount.incrementAndGet(); live = message;
        }
        @Implementation protected void close() {
            closeCount.incrementAndGet();
            closeOnMain |= Looper.myLooper() == Looper.getMainLooper();
            closeEntered.countDown(); unblock(closeGate);
            if (failClose) throw new SecurityException("stale tag cookie");
            TechnologyConnection.close("ndef");
        }
        private static void unblock(CountDownLatch gate) {
            boolean interrupted = false;
            while (true) {
                try { gate.await(); break; }
                catch (InterruptedException error) { interrupted = true; }
            }
            if (interrupted) Thread.currentThread().interrupt();
        }
    }

    /** Models Android's per-tag exclusivity, including closes from another thread. */
    private static final class TechnologyConnection {
        static volatile String probe, connected;
        static CountDownLatch readEntered, readGate;
        static AtomicInteger conflicts, connectCount;
        static void reset() {
            probe = null; connected = null;
            conflicts = new AtomicInteger(); connectCount = new AtomicInteger();
            readEntered = new CountDownLatch(1); readGate = new CountDownLatch(0);
        }
        static synchronized void connect(String technology) throws IOException {
            if (!"ndef".equals(technology)) connectCount.incrementAndGet();
            if (connected != null) {
                conflicts.incrementAndGet();
                throw new IOException("Only one TagTechnology may be connected");
            }
            connected = technology;
        }
        static synchronized void close(String technology) {
            if (connected != null && !connected.equals(technology)) conflicts.incrementAndGet();
            connected = null;
        }
        static byte[] read(int page) {
            readEntered.countDown(); ControlledNdef.unblock(readGate);
            return page == 0 ? new byte[16] : new byte[0];
        }
    }

    @Implements(MifareUltralight.class)
    public static class ControlledUltralight extends ShadowBasicTagTechnology {
        @Implementation protected void __constructor__(Tag tag) { }
        @Implementation protected static MifareUltralight get(Tag tag) {
            return "ultralight".equals(TechnologyConnection.probe)
                    ? ReflectionHelpers.callConstructor(MifareUltralight.class, ClassParameter.from(Tag.class, tag)) : null;
        }
        @Implementation protected void connect() throws IOException { TechnologyConnection.connect("ultralight"); }
        @Implementation protected int getType() { return MifareUltralight.TYPE_ULTRALIGHT; }
        @Implementation protected void setTimeout(int milliseconds) { }
        @Implementation protected byte[] readPages(int page) { return TechnologyConnection.read(page); }
        @Implementation protected void close() { TechnologyConnection.close("ultralight"); }
    }

    @Implements(NfcA.class)
    public static class ControlledNfcA extends ShadowBasicTagTechnology {
        @Implementation protected void __constructor__(Tag tag) { }
        @Implementation protected static NfcA get(Tag tag) {
            return "nfcA".equals(TechnologyConnection.probe)
                    ? ReflectionHelpers.callConstructor(NfcA.class, ClassParameter.from(Tag.class, tag)) : null;
        }
        @Implementation protected void connect() throws IOException { TechnologyConnection.connect("nfcA"); }
        @Implementation protected short getSak() { return 0; }
        @Implementation protected byte[] getAtqa() { return new byte[] { 0x44, 0 }; }
        @Implementation protected void setTimeout(int milliseconds) { }
        @Implementation protected byte[] transceive(byte[] command) { return TechnologyConnection.read(command[1] & 0xff); }
        @Implementation protected void close() { TechnologyConnection.close("nfcA"); }
    }

    @Implements(MifareClassic.class)
    public static class ControlledClassic extends ShadowBasicTagTechnology {
        @Implementation protected void __constructor__(Tag tag) { }
        @Implementation protected static MifareClassic get(Tag tag) {
            return "classic".equals(TechnologyConnection.probe)
                    ? ReflectionHelpers.callConstructor(MifareClassic.class, ClassParameter.from(Tag.class, tag)) : null;
        }
        @Implementation protected void connect() throws IOException { TechnologyConnection.connect("classic"); }
        @Implementation protected int getType() { return MifareClassic.TYPE_CLASSIC; }
        @Implementation protected int getSize() { return 16; }
        @Implementation protected int getSectorCount() { return 1; }
        @Implementation protected int getBlockCount() { return 1; }
        @Implementation protected int sectorToBlock(int sector) { return 0; }
        @Implementation protected int getBlockCountInSector(int sector) { return 1; }
        @Implementation protected void setTimeout(int milliseconds) { }
        @Implementation protected boolean authenticateSectorWithKeyA(int sector, byte[] key) { return true; }
        @Implementation protected byte[] readBlock(int block) { return TechnologyConnection.read(0); }
        @Implementation protected void close() { TechnologyConnection.close("classic"); }
    }
}
