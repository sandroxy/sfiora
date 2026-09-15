package com.sandrox.sfiora.ui;

import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import com.sandrox.sfiora.NfcError;
import com.sandrox.sfiora.NfcErrorCode;
import java.util.ArrayList;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

/** Process-wide state of Sfiora-owned Android panels, independent of RF sessions. */
public final class NfcPresentationState {
    public interface Completion {
        void onSuccess();
        void onFailure(NfcError error);
    }

    private static final Handler MAIN = new Handler(Looper.getMainLooper());
    private static final Set<String> ACTIVE = new LinkedHashSet<>();
    private static final Set<Waiter> WAITERS = new LinkedHashSet<>();

    private NfcPresentationState() {}

    static String began() {
        requireMain();
        String id = UUID.randomUUID().toString();
        ACTIVE.add(id);
        return id;
    }

    static void ended(String id) {
        requireMain();
        if (id == null || !ACTIVE.remove(id)) return;
        for (Waiter waiter : new ArrayList<>(WAITERS)) waiter.check();
    }

    public static Map<String, Object> getState() {
        requireMain();
        Map<String, Object> value = new LinkedHashMap<>();
        value.put("platform", "android");
        value.put("supported", true);
        value.put("activePresentationIds", new ArrayList<>(ACTIVE));
        return Collections.unmodifiableMap(value);
    }

    /** Captures the currently visible panels. Later panels never extend this wait. */
    public static void waitForEnd(long timeoutMilliseconds, Completion completion) {
        requireMain();
        if (timeoutMilliseconds < 1 || timeoutMilliseconds > 60000 || completion == null) {
            throw new IllegalArgumentException("A completion and a timeout from 1 to 60000 milliseconds are required");
        }
        Waiter waiter = new Waiter(new LinkedHashSet<>(ACTIVE), completion);
        WAITERS.add(waiter);
        MAIN.postDelayed(waiter.deadline, timeoutMilliseconds);
        waiter.check();
    }

    private static final class Waiter {
        final Set<String> captured;
        final Completion completion;
        final Runnable deadline = () -> finish(new NfcError(
                NfcErrorCode.PRESENTATION_TIMEOUT,
                "The captured NFC panels did not finish before the wait deadline", true));

        Waiter(Set<String> captured, Completion completion) {
            this.captured = captured;
            this.completion = completion;
        }

        void check() {
            if (Collections.disjoint(captured, ACTIVE)) finish(null);
        }

        void finish(NfcError error) {
            if (!WAITERS.remove(this)) return;
            MAIN.removeCallbacks(deadline);
            try {
                if (error == null) completion.onSuccess();
                else completion.onFailure(error);
            } catch (RuntimeException callbackError) {
                Log.e("Sfiora", "Presentation completion callback failed", callbackError);
            }
        }
    }

    private static void requireMain() {
        if (Looper.myLooper() != Looper.getMainLooper()) {
            throw new IllegalStateException("Presentation state must be accessed on the main thread");
        }
    }
}
