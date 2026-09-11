package com.sandrox.sfiora.ui;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;
import static org.robolectric.Shadows.shadowOf;

import android.animation.ValueAnimator;
import android.app.Activity;
import android.app.Dialog;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.os.Looper;
import android.view.View;
import android.widget.FrameLayout;

import java.time.Duration;
import java.util.ArrayList;
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
import org.robolectric.util.ReflectionHelpers.ClassParameter;

/** Exercises the production dialog, animator and Canvas, including delayed frames. */
@RunWith(RobolectricTestRunner.class)
@Config(sdk = 28, qualifiers = "mdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@LooperMode(LooperMode.Mode.PAUSED)
public class ManagedNfcSuccessPresentationTest {
    private ActivityController<Activity> activityController;
    private Activity activity;
    private ManagedNfcOperationDialog managedDialog;
    private Dialog dialog;
    private final List<NfcReaderScanAnimationView> views = new ArrayList<>();

    @Before
    public void setUp() {
        setDurationScale(1.0f);
        activityController = Robolectric.buildActivity(Activity.class).setup();
        activity = activityController.get();
    }

    @After
    public void tearDown() {
        for (NfcReaderScanAnimationView view : views) {
            view.stopAnimation();
        }
        if (dialog != null) {
            dialog.dismiss();
        }
        activityController.pause().stop().destroy();
        setDurationScale(1.0f);
    }

    @Test
    public void phoneLeavesBeforeCheckAppearsAndFinalCheckIsComplete() {
        NfcReaderScanAnimationView view = createView();
        view.playSuccessAnimation(() -> {});
        ValueAnimator animator = pauseSuccess(view);
        boolean sawPhone = false;
        boolean sawCheck = false;
        for (int milliseconds = 0; milliseconds <= 200; milliseconds += 10) {
            animator.setCurrentPlayTime(milliseconds);
            Bitmap frame = draw(view);
            // These sample points lie inside the phone and the check's first stroke,
            // respectively, clear of the fixed ring and the phone's border.
            boolean phoneVisible = Color.alpha(frame.getPixel(80, 120)) > 0;
            boolean checkVisible = isAccent(frame.getPixel(70, 86));
            sawPhone |= phoneVisible;
            sawCheck |= checkVisible;
            assertFalse("Overlapping phone/check at " + milliseconds + " ms",
                    phoneVisible && checkVisible);
            if (milliseconds == 80) {
                assertEquals("The phone has left before the check starts", 0,
                        Color.alpha(frame.getPixel(80, 120)));
            }
            frame.recycle();
        }
        assertTrue("The transition must include the outgoing phone", sawPhone);
        assertTrue("The transition must draw the check", sawCheck);
        Bitmap finalFrame = draw(view);
        assertTrue("The long stroke reaches its upper-right endpoint",
                isAccent(finalFrame.getPixel(99, 69)));
        finalFrame.recycle();
    }

    @Test
    public void automaticDismissalWaitsForDrawnCheckThenBriefDwell() {
        NfcReaderScanAnimationView view = createDialog();
        managedDialog.showSuccess();
        ValueAnimator animator = pauseSuccess(view);

        // The old fixed 230 ms deadline would dismiss a still-incomplete animation.
        idleFor(600);
        assertTrue(managedDialog.isShowing());
        assertEquals(0.0f, panel().getTranslationY(), 0.01f);

        animator.end();
        draw(view).recycle();
        shadowOf(Looper.getMainLooper()).idle();
        idleFor(80);
        assertTrue("The complete check must remain visible briefly", managedDialog.isShowing());
        assertEquals(0.0f, panel().getTranslationY(), 0.01f);
        idleFor(400);
        assertFalse("The success sheet must then dismiss automatically", managedDialog.isShowing());
    }

    @Test
    public void disabledAnimationsStillDrawCompleteCheckAndDismiss() {
        setDurationScale(0.0f);
        NfcReaderScanAnimationView view = createDialog();
        managedDialog.showSuccess();
        Bitmap frame = draw(view);
        assertEquals(0, Color.alpha(frame.getPixel(80, 120)));
        assertTrue(isAccent(frame.getPixel(99, 69)));
        frame.recycle();
        shadowOf(Looper.getMainLooper()).idle();
        idleFor(80);
        assertTrue(managedDialog.isShowing());
        idleFor(200);
        assertFalse(managedDialog.isShowing());
    }

    @Test
    public void stoppingRemovesQueuedCompletionBeforeAnotherSession() {
        NfcReaderScanAnimationView view = createView();
        AtomicInteger oldCompletions = new AtomicInteger();
        AtomicInteger newCompletions = new AtomicInteger();
        view.playSuccessAnimation(oldCompletions::incrementAndGet);
        pauseSuccess(view).end();
        draw(view).recycle();
        view.stopAnimation();
        view.resetToPending();
        view.playSuccessAnimation(newCompletions::incrementAndGet);
        ValueAnimator nextAnimator = pauseSuccess(view);
        idleFor(300);
        assertEquals(0, oldCompletions.get());
        assertEquals(0, newCompletions.get());
        nextAnimator.end();
        draw(view).recycle();
        shadowOf(Looper.getMainLooper()).idle();
        draw(view).recycle();
        shadowOf(Looper.getMainLooper()).idle();
        assertEquals(0, oldCompletions.get());
        assertEquals(1, newCompletions.get());
    }

    @Test
    public void explicitDismissalDoesNotWaitForSuccessAnimation() {
        NfcReaderScanAnimationView view = createDialog();
        managedDialog.showSuccess();
        pauseSuccess(view).setCurrentPlayTime(100L);
        managedDialog.dismissWithoutCancellation();
        idleFor(400);
        assertFalse(managedDialog.isShowing());
    }

    private NfcReaderScanAnimationView createView() {
        NfcReaderScanAnimationView view = new NfcReaderScanAnimationView(activity);
        FrameLayout root = new FrameLayout(activity);
        root.addView(view, new FrameLayout.LayoutParams(160, 160));
        activity.setContentView(root);
        shadowOf(Looper.getMainLooper()).idle();
        views.add(view);
        return view;
    }

    private NfcReaderScanAnimationView createDialog() {
        managedDialog = new ManagedNfcOperationDialog(
                activity,
                ManagedNfcOperationDialog.Operation.READ,
                NfcPresentationMessages.resolveScan(activity, null),
                () -> {},
                () -> {}
        );
        managedDialog.showPending();
        dialog = ShadowDialog.getLatestDialog();
        idleFor(500);
        NfcReaderScanAnimationView view = dialog.findViewById(R.id.nfc_reader_scan_animation);
        views.add(view);
        return view;
    }

    private View panel() {
        return dialog.findViewById(R.id.nfc_reader_scan_panel);
    }

    private static ValueAnimator pauseSuccess(NfcReaderScanAnimationView view) {
        ValueAnimator animator = ReflectionHelpers.getField(view, "successAnimator");
        animator.pause();
        return animator;
    }

    private static Bitmap draw(NfcReaderScanAnimationView view) {
        int exact = View.MeasureSpec.makeMeasureSpec(160, View.MeasureSpec.EXACTLY);
        view.measure(exact, exact);
        view.layout(0, 0, 160, 160);
        Bitmap frame = Bitmap.createBitmap(160, 160, Bitmap.Config.ARGB_8888);
        view.draw(new Canvas(frame));
        return frame;
    }

    private static boolean isAccent(int pixel) {
        return Color.alpha(pixel) > 240 && Color.red(pixel) < 30
                && Color.green(pixel) > 80 && Color.blue(pixel) > 200;
    }

    private static void idleFor(long milliseconds) {
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(milliseconds));
    }

    private static void setDurationScale(float scale) {
        ReflectionHelpers.callStaticMethod(ValueAnimator.class, "setDurationScale",
                ClassParameter.from(float.class, scale));
    }
}
