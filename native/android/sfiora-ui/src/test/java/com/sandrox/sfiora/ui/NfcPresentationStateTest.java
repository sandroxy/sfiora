package com.sandrox.sfiora.ui;

import static org.junit.Assert.*;
import static org.robolectric.Shadows.shadowOf;

import android.os.Looper;
import com.sandrox.sfiora.NfcError;
import com.sandrox.sfiora.NfcErrorCode;
import java.time.Duration;
import java.util.List;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.annotation.Config;
import org.robolectric.annotation.LooperMode;

@RunWith(RobolectricTestRunner.class)
@Config(sdk = 28)
@LooperMode(LooperMode.Mode.PAUSED)
public class NfcPresentationStateTest {
    private static final class Result implements NfcPresentationState.Completion {
        int successes;
        int failures;
        NfcError error;
        @Override public void onSuccess() { successes++; }
        @Override public void onFailure(NfcError value) { failures++; error = value; }
    }

    @Test public void capturesCurrentPanelsAndDoesNotWaitForFuturePanels() {
        String first = NfcPresentationState.began();
        Result result = new Result();
        NfcPresentationState.waitForEnd(100, result);
        String later = NfcPresentationState.began();
        NfcPresentationState.ended(first);
        assertEquals(1, result.successes);
        assertEquals(List.of(later), NfcPresentationState.getState().get("activePresentationIds"));
        NfcPresentationState.ended(first);
        NfcPresentationState.ended(later);
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(200));
        assertEquals(1, result.successes);
        assertEquals(0, result.failures);
    }

    @Test public void emptySnapshotFinishesImmediatelyAndDoesNotReserveNextPanel() {
        Result result = new Result();
        NfcPresentationState.waitForEnd(100, result);
        assertEquals(1, result.successes);
        String later = NfcPresentationState.began();
        NfcPresentationState.ended(later);
        assertEquals(1, result.successes);
    }

    @Test public void timeoutDoesNotDismissPanelsOrFinishOtherWaits() {
        String panel = NfcPresentationState.began();
        Result shortWait = new Result();
        Result longWait = new Result();
        NfcPresentationState.waitForEnd(50, shortWait);
        NfcPresentationState.waitForEnd(500, longWait);
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(50));
        assertEquals(NfcErrorCode.PRESENTATION_TIMEOUT, shortWait.error.getCode());
        assertEquals(List.of(panel), NfcPresentationState.getState().get("activePresentationIds"));
        assertEquals(0, longWait.successes);
        NfcPresentationState.ended(panel);
        assertEquals(0, shortWait.successes);
        assertEquals(1, shortWait.failures);
        assertEquals(1, longWait.successes);
    }

    @Test public void consumerCallbackFailureDoesNotStrandOtherWaiters() {
        String panel = NfcPresentationState.began();
        NfcPresentationState.waitForEnd(100, new NfcPresentationState.Completion() {
            @Override public void onSuccess() { throw new IllegalStateException("consumer failure"); }
            @Override public void onFailure(NfcError error) { throw new AssertionError(error); }
        });
        Result result = new Result();
        NfcPresentationState.waitForEnd(100, result);
        NfcPresentationState.ended(panel);
        assertEquals(1, result.successes);
    }

    @Test public void invalidTimeoutDoesNotCreateAWaiter() {
        for (long timeout : new long[] {-1, 0, 60001}) {
            assertThrows(IllegalArgumentException.class, () -> NfcPresentationState.waitForEnd(timeout, new Result()));
        }
    }
}
