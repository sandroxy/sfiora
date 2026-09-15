package com.sandrox.sfiora.ui;

import static org.junit.Assert.*;
import static org.robolectric.Shadows.shadowOf;

import android.animation.ValueAnimator;
import android.app.Activity;
import android.app.Dialog;
import android.content.pm.PackageManager;
import android.nfc.NfcAdapter;
import android.os.Looper;
import com.sandrox.sfiora.NdefExternalType;
import com.sandrox.sfiora.NdefMessage;
import com.sandrox.sfiora.NdefRecord;
import com.sandrox.sfiora.NfcClient;
import com.sandrox.sfiora.NfcError;
import com.sandrox.sfiora.NfcErrorCode;
import com.sandrox.sfiora.NfcInitializationResult;
import com.sandrox.sfiora.NfcTagSnapshot;
import com.sandrox.sfiora.NfcWriteResult;
import java.time.Duration;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.concurrent.atomic.AtomicInteger;
import org.junit.After;
import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.Robolectric;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.android.controller.ActivityController;
import org.robolectric.annotation.Config;
import org.robolectric.annotation.GraphicsMode;
import org.robolectric.annotation.LooperMode;
import org.robolectric.shadows.ShadowDialog;
import org.robolectric.util.ReflectionHelpers;

/** Runs production controllers and dialogs; disabled hardware supplies a terminal result without a tag. */
@RunWith(RobolectricTestRunner.class)
@Config(sdk = 28)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@LooperMode(LooperMode.Mode.PAUSED)
public class NfcControllerPresentationLifecycleTest {
    private ActivityController<Activity> host;
    private NfcScanController reader;
    private NfcWriteController writer;
    private final List<Dialog> panels = new ArrayList<>();
    private final NdefExternalType marker = new NdefExternalType("example.org", "initialized");
    private final NdefMessage message = new NdefMessage(Collections.singletonList(
            NdefRecord.external("example.org", "initialized", new byte[] {1})));

    @Before public void setUp() {
        ReflectionHelpers.callStaticMethod(ValueAnimator.class, "setDurationScale",
                ReflectionHelpers.ClassParameter.from(float.class, 1.0f));
        host = Robolectric.buildActivity(Activity.class).setup();
        shadowOf(host.get().getPackageManager()).setSystemFeature(PackageManager.FEATURE_NFC, true);
        shadowOf(NfcAdapter.getDefaultAdapter(host.get())).setEnabled(false);
        reader = new NfcScanController(host.get());
        writer = new NfcWriteController(host.get());
    }

    @After public void tearDown() {
        reader.close();
        writer.close();
        // Also clean up panels exposed by a failing regression before the fix.
        for (Dialog panel : panels) panel.dismiss();
        shadowOf(Looper.getMainLooper()).idle();
        host.pause().stop().destroy();
    }

    @Test public void repeatedReadThenCloseReleasesEveryPanelWithoutAnotherFrame() {
        read(NfcScanPresentation.MANAGED);
        captureTerminalPanel();
        read(NfcScanPresentation.MANAGED);
        capturePanel();
        assertReleased(reader::close);
    }

    @Test public void headlessReplacementThenStopReleasesThePreviousManagedPanel() {
        read(NfcScanPresentation.MANAGED);
        captureTerminalPanel();
        read(NfcScanPresentation.NONE);
        assertReleased(reader::stopScan);
    }

    @Test public void repeatedWriteThenCloseReleasesEveryPanelWithoutAnotherFrame() {
        write();
        captureTerminalPanel();
        write();
        capturePanel();
        assertReleased(writer::close);
    }

    @Test public void initializeReplacementThenStopReleasesEveryPanelWithoutAnotherFrame() {
        write();
        captureTerminalPanel();
        writer.startInitialize(message, marker, new NfcClient.InitializationCallback() {
            @Override public void onSuccess(NfcInitializationResult result) { fail("NFC is disabled"); }
            @Override public void onFailure(NfcError error) { assertEquals(NfcErrorCode.NFC_DISABLED, error.getCode()); }
        });
        capturePanel();
        assertReleased(writer::stopWrite);
    }

    private void read(NfcScanPresentation presentation) {
        reader.startScan(null, presentation, new NfcClient.ReadCallback() {
            @Override public void onSuccess(NfcTagSnapshot tag) { fail("NFC is disabled"); }
            @Override public void onFailure(NfcError error) { assertEquals(NfcErrorCode.NFC_DISABLED, error.getCode()); }
        });
        assertFalse(reader.isScanning());
    }

    private void write() {
        writer.startWrite(message, new NfcClient.WriteCallback() {
            @Override public void onSuccess(NfcWriteResult result) { fail("NFC is disabled"); }
            @Override public void onFailure(NfcError error) { assertEquals(NfcErrorCode.NFC_DISABLED, error.getCode()); }
        });
        assertFalse(writer.isWriting());
    }

    private void capturePanel() {
        Dialog panel = ShadowDialog.getLatestDialog();
        assertTrue(panel.isShowing());
        panels.add(panel);
    }

    private void captureTerminalPanel() {
        capturePanel();
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(400));
        assertTrue("The terminal panel remains visible when the next operation starts", panels.get(0).isShowing());
    }

    private void assertReleased(Runnable end) {
        AtomicInteger ended = new AtomicInteger();
        NfcPresentationState.waitForEnd(5000, new NfcPresentationState.Completion() {
            @Override public void onSuccess() { ended.incrementAndGet(); }
            @Override public void onFailure(NfcError error) { fail(error.getMessage()); }
        });
        end.run();
        for (Dialog panel : panels) assertFalse("A replaced panel escaped controller cleanup", panel.isShowing());
        // Deliver dismiss notifications, without advancing the animation clock.
        shadowOf(Looper.getMainLooper()).idle();
        assertEquals(1, ended.get());
        assertTrue(((List<?>) NfcPresentationState.getState().get("activePresentationIds")).isEmpty());
    }
}
