package com.sandrox.sfiora.ui;

import android.animation.ValueAnimator;
import android.app.Activity;
import android.app.Dialog;
import android.content.res.Configuration;
import android.graphics.Color;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.view.Gravity;
import android.view.KeyEvent;
import android.view.View;
import android.view.ViewGroup;
import android.view.Window;
import android.view.WindowInsets;
import android.view.WindowInsetsController;
import android.view.WindowManager;
import android.view.animation.DecelerateInterpolator;
import android.view.animation.OvershootInterpolator;
import android.view.animation.PathInterpolator;
import android.widget.Button;
import android.widget.ImageButton;
import android.widget.ImageView;
import android.widget.TextView;

import com.sandrox.sfiora.NfcError;
import com.sandrox.sfiora.NfcErrorCode;

final class ManagedNfcOperationDialog {
    enum Operation {
        READ,
        WRITE
    }

    private static final long SUCCESS_VISIBLE_MILLIS = 100L;
    private static final long ERROR_VISIBLE_MILLIS = 1_100L;
    private static final long TIMEOUT_VISIBLE_MILLIS = 35L;

    private final Activity activity;
    private final Operation operation;
    private final NfcPresentationMessages.Resolved messages;
    private final Runnable cancellationAction;
    private final Runnable dismissalAction;
    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    private final Dialog dialog;

    private final View panelView;
    private final NfcReaderScanAnimationView scanAnimationView;
    private final ImageView statusIconView;
    private final TextView titleView;
    private final TextView messageView;
    private final ImageButton closeButton;
    private final Button cancelButton;
    private final int panelBaseBottomMargin;

    private ValueAnimator dimAnimator;
    private boolean terminal;
    private boolean successful;
    private boolean cancellationRequested;
    private boolean dismissing;

    ManagedNfcOperationDialog(
            Activity activity,
            Operation operation,
            NfcPresentationMessages.Resolved messages,
            Runnable cancellationAction,
            Runnable dismissalAction
    ) {
        this.activity = activity;
        this.operation = operation;
        this.messages = messages;
        this.cancellationAction = cancellationAction;
        this.dismissalAction = dismissalAction;

        dialog = new Dialog(activity, R.style.NfcReader_ScanPanel);
        dialog.setContentView(R.layout.nfc_reader_scan_panel);
        dialog.setCancelable(true);
        dialog.setCanceledOnTouchOutside(false);

        panelView = dialog.findViewById(R.id.nfc_reader_scan_panel);
        scanAnimationView = dialog.findViewById(R.id.nfc_reader_scan_animation);
        statusIconView = dialog.findViewById(R.id.nfc_reader_scan_status_icon);
        titleView = dialog.findViewById(R.id.nfc_reader_scan_title);
        messageView = dialog.findViewById(R.id.nfc_reader_scan_message);
        closeButton = dialog.findViewById(R.id.nfc_reader_scan_close);
        cancelButton = dialog.findViewById(R.id.nfc_reader_scan_cancel);
        ViewGroup.MarginLayoutParams panelLayoutParams =
                (ViewGroup.MarginLayoutParams) panelView.getLayoutParams();
        panelBaseBottomMargin = panelLayoutParams.bottomMargin;

        configurePendingActions();
        dialog.setOnCancelListener(ignored -> requestCancellation());
        dialog.setOnKeyListener((ignored, keyCode, event) -> {
            if (keyCode == KeyEvent.KEYCODE_BACK
                    && event.getAction() == KeyEvent.ACTION_UP) {
                requestCancellation();
                return true;
            }
            return false;
        });
        dialog.setOnDismissListener(ignored -> {
            scanAnimationView.stopAnimation();
            panelView.animate().cancel();
            statusIconView.animate().cancel();
            if (dimAnimator != null) {
                dimAnimator.cancel();
                dimAnimator = null;
            }
            mainHandler.removeCallbacksAndMessages(this);
            dismissalAction.run();
        });
    }

    boolean isShowing() {
        return dialog.isShowing();
    }

    void showPending() {
        if (activity.isFinishing() || activity.isDestroyed()) {
            requestCancellation();
            return;
        }
        terminal = false;
        successful = false;
        cancellationRequested = false;
        dismissing = false;
        panelView.setVisibility(View.VISIBLE);
        titleView.setText(messages.title);
        messageView.setText(messages.instruction);
        statusIconView.setVisibility(View.INVISIBLE);
        scanAnimationView.setVisibility(View.VISIBLE);
        closeButton.setVisibility(View.VISIBLE);
        closeButton.setContentDescription(messages.cancel);
        closeButton.setEnabled(true);
        closeButton.setAlpha(1.0f);
        cancelButton.setVisibility(View.VISIBLE);
        cancelButton.setEnabled(true);
        cancelButton.setAlpha(1.0f);
        cancelButton.setText(messages.cancel);
        configurePendingActions();
        scanAnimationView.resetToPending();

        if (!dialog.isShowing()) {
            dialog.show();
            configureWindow();
            playPresentationAnimation();
        }
        scanAnimationView.startAnimation();
    }

    void showSuccess() {
        if (!dialog.isShowing() || terminal || dismissing) {
            return;
        }
        terminal = true;
        successful = true;
        mainHandler.removeCallbacksAndMessages(this);
        titleView.setText(messages.title);
        messageView.setText(messages.success);
        statusIconView.animate().cancel();
        statusIconView.setVisibility(View.INVISIBLE);
        scanAnimationView.setVisibility(View.VISIBLE);
        closeButton.setVisibility(View.VISIBLE);
        closeButton.setEnabled(true);
        closeButton.setAlpha(1.0f);
        closeButton.setOnClickListener(view -> dismissWithoutCancellation());
        cancelButton.setVisibility(View.VISIBLE);
        cancelButton.setEnabled(true);
        cancelButton.setAlpha(1.0f);
        cancelButton.setText(messages.done);
        cancelButton.setOnClickListener(view -> dismissWithoutCancellation());
        scanAnimationView.playSuccessAnimation(() -> {
            if (dialog.isShowing() && !dismissing) {
                scheduleDismissal(SUCCESS_VISIBLE_MILLIS);
            }
        });
    }

    void showError(NfcError error) {
        if (!dialog.isShowing()) {
            return;
        }
        terminal = true;

        if (!isUserPresentable(error)) {
            dismissWithoutCancellation();
            return;
        }

        if (isTimeout(error)) {
            scanAnimationView.stopAnimation();
            messageView.setText(messages.timeout);
            scheduleDismissal(TIMEOUT_VISIBLE_MILLIS);
            return;
        }

        showTerminalIcon(R.drawable.nfc_reader_ic_error);
        titleView.setText(messages.failureTitle);
        messageView.setText(errorMessage(error));
        closeButton.setVisibility(View.INVISIBLE);
        cancelButton.setVisibility(View.INVISIBLE);
        scheduleDismissal(ERROR_VISIBLE_MILLIS);
    }

    void dismissWithoutCancellation() {
        terminal = true;
        mainHandler.removeCallbacksAndMessages(this);
        scanAnimationView.stopAnimation();
        if (!dialog.isShowing() || dismissing) {
            return;
        }
        dismissing = true;
        animateDimAmountToZero();
        panelView.animate().cancel();
        panelView.animate()
                .translationY(Math.max(panelView.getHeight() + dp(12.0f), dp(420.0f)))
                .alpha(1.0f)
                .scaleX(1.0f)
                .scaleY(1.0f)
                .setDuration(successful ? 120L : 160L)
                .setInterpolator(new PathInterpolator(0.16f, 1.0f, 0.3f, 1.0f))
                .withEndAction(() -> {
                    if (dialog.isShowing()) {
                        dialog.dismiss();
                    }
                })
                .start();
    }

    private void configureWindow() {
        Window window = dialog.getWindow();
        if (window == null) {
            return;
        }
        window.setBackgroundDrawableResource(android.R.color.transparent);
        window.setDimAmount(0.64f);
        window.addFlags(WindowManager.LayoutParams.FLAG_DIM_BEHIND);
        configureNavigationBar(window);
        window.setLayout(
                WindowManager.LayoutParams.MATCH_PARENT,
                WindowManager.LayoutParams.MATCH_PARENT
        );
        window.setGravity(Gravity.BOTTOM);
        WindowManager.LayoutParams attributes = window.getAttributes();
        attributes.windowAnimations = R.style.NfcReader_ScanPanelAnimation;
        window.setAttributes(attributes);
        configurePanelWidth();
        panelView.requestApplyInsets();
    }

    private void requestCancellation() {
        if (terminal || cancellationRequested) {
            return;
        }
        cancellationRequested = true;
        closeButton.setEnabled(false);
        cancelButton.setEnabled(false);
        cancellationAction.run();
    }

    private void configurePendingActions() {
        cancelButton.setOnClickListener(view -> requestCancellation());
        closeButton.setOnClickListener(view -> requestCancellation());
    }

    private void scheduleDismissal(long delayMillis) {
        mainHandler.postAtTime(
                this::dismissWithoutCancellation,
                this,
                android.os.SystemClock.uptimeMillis() + delayMillis
        );
    }

    private void playPresentationAnimation() {
        panelView.animate().cancel();
        panelView.setTranslationY(dp(420.0f));
        panelView.setAlpha(1.0f);
        panelView.setScaleX(1.0f);
        panelView.setScaleY(1.0f);
        panelView.post(() -> panelView.animate()
                .translationY(0.0f)
                .setDuration(420L)
                .setInterpolator(new PathInterpolator(0.16f, 1.0f, 0.3f, 1.0f))
                .start());
    }

    private void animateDimAmountToZero() {
        Window window = dialog.getWindow();
        if (window == null) {
            return;
        }
        if (dimAnimator != null) {
            dimAnimator.cancel();
        }
        float startingDimAmount = window.getAttributes().dimAmount;
        dimAnimator = ValueAnimator.ofFloat(startingDimAmount, 0.0f);
        dimAnimator.setDuration(350L);
        dimAnimator.setInterpolator(new DecelerateInterpolator());
        dimAnimator.addUpdateListener(animation -> {
            if (!dialog.isShowing()) {
                return;
            }
            WindowManager.LayoutParams attributes = window.getAttributes();
            attributes.dimAmount = (float) animation.getAnimatedValue();
            window.setAttributes(attributes);
        });
        dimAnimator.start();
    }

    private void showTerminalIcon(int drawableResource) {
        scanAnimationView.stopAnimation();
        scanAnimationView.setVisibility(View.INVISIBLE);
        statusIconView.animate().cancel();
        statusIconView.setImageResource(drawableResource);
        statusIconView.setVisibility(View.VISIBLE);
        statusIconView.setAlpha(0.0f);
        statusIconView.setScaleX(0.78f);
        statusIconView.setScaleY(0.78f);
        statusIconView.animate()
                .alpha(1.0f)
                .scaleX(1.0f)
                .scaleY(1.0f)
                .setDuration(320L)
                .setInterpolator(new OvershootInterpolator(0.75f))
                .start();
    }

    private void configurePanelWidth() {
        int screenWidth = activity.getResources().getDisplayMetrics().widthPixels;
        int availableWidth = Math.max(0, screenWidth - Math.round(dp(12.0f)));
        int desiredWidth = Math.min(availableWidth, Math.round(dp(430.0f)));
        ViewGroup.LayoutParams layoutParams = panelView.getLayoutParams();
        layoutParams.width = desiredWidth;
        panelView.setLayoutParams(layoutParams);
    }

    @SuppressWarnings("deprecation")
    private void configureNavigationBar(Window window) {
        window.clearFlags(WindowManager.LayoutParams.FLAG_TRANSLUCENT_NAVIGATION);
        window.addFlags(WindowManager.LayoutParams.FLAG_DRAWS_SYSTEM_BAR_BACKGROUNDS);

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            window.setNavigationBarColor(
                    resolveColor(R.color.nfc_reader_legacy_navigation_bar)
            );
            return;
        }

        window.setNavigationBarColor(Color.TRANSPARENT);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            window.setNavigationBarDividerColor(Color.TRANSPARENT);
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            window.setNavigationBarContrastEnforced(false);
        }

        boolean useDarkNavigationIcons = isLightTheme();
        View decorView = window.getDecorView();
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.setDecorFitsSystemWindows(false);
            WindowInsetsController controller = decorView.getWindowInsetsController();
            if (controller != null) {
                int navigationAppearance =
                        WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS;
                controller.setSystemBarsAppearance(
                        useDarkNavigationIcons ? navigationAppearance : 0,
                        navigationAppearance
                );
            }
        } else {
            int visibility = decorView.getSystemUiVisibility()
                    | View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                    | View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION;
            if (useDarkNavigationIcons) {
                visibility |= View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR;
            } else {
                visibility &= ~View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR;
            }
            decorView.setSystemUiVisibility(visibility);
        }

        panelView.setOnApplyWindowInsetsListener((view, insets) -> {
            int navigationBarBottom;
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                navigationBarBottom = insets.getInsets(
                        WindowInsets.Type.navigationBars()
                ).bottom;
            } else {
                navigationBarBottom = insets.getSystemWindowInsetBottom();
            }
            ViewGroup.MarginLayoutParams layoutParams =
                    (ViewGroup.MarginLayoutParams) view.getLayoutParams();
            int desiredBottomMargin = panelBaseBottomMargin + navigationBarBottom;
            if (layoutParams.bottomMargin != desiredBottomMargin) {
                layoutParams.bottomMargin = desiredBottomMargin;
                view.setLayoutParams(layoutParams);
            }
            return insets;
        });
    }

    private float dp(float value) {
        return value * activity.getResources().getDisplayMetrics().density;
    }

    private boolean isLightTheme() {
        int nightMode = activity.getResources().getConfiguration().uiMode
                & Configuration.UI_MODE_NIGHT_MASK;
        return nightMode != Configuration.UI_MODE_NIGHT_YES;
    }

    @SuppressWarnings("deprecation")
    private int resolveColor(int colorResource) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            return activity.getColor(colorResource);
        }
        return activity.getResources().getColor(colorResource);
    }

    private String errorMessage(NfcError error) {
        if (error.getCode() == NfcErrorCode.NFC_DISABLED) {
            return messages.nfcDisabled;
        }
        if (error.getCode() == NfcErrorCode.NFC_UNSUPPORTED) {
            return messages.nfcUnsupported;
        }
        if (error.getCode() == NfcErrorCode.TAG_LOST) {
            return messages.tagLost;
        }
        if (operation == Operation.WRITE) {
            if (error.getCode() == NfcErrorCode.TAG_READ_ONLY) {
                return messages.tagReadOnly;
            }
            if (error.getCode() == NfcErrorCode.NDEF_CAPACITY_EXCEEDED) {
                return messages.capacityExceeded;
            }
            if (error.getCode() == NfcErrorCode.UNSUPPORTED_TAG) {
                return messages.unsupportedTag;
            }
            if (error.getCode() == NfcErrorCode.WRITE_VERIFICATION_FAILED) {
                return messages.verificationFailed;
            }
            return messages.failed;
        }
        if (error.getCode() == NfcErrorCode.UNSUPPORTED_TAG) {
            return messages.unsupportedTag;
        }
        return messages.failed;
    }

    private boolean isTimeout(NfcError error) {
        return error.getCode() == NfcErrorCode.SCAN_TIMEOUT
                || error.getCode() == NfcErrorCode.WRITE_TIMEOUT;
    }

    private boolean isUserPresentable(NfcError error) {
        NfcErrorCode code = error.getCode();
        if (code == NfcErrorCode.USER_CANCELLED) {
            return false;
        }
        if (operation == Operation.READ) {
            return code == NfcErrorCode.NFC_DISABLED
                    || code == NfcErrorCode.NFC_UNSUPPORTED
                    || code == NfcErrorCode.SCAN_TIMEOUT
                    || code == NfcErrorCode.TAG_LOST
                    || code == NfcErrorCode.UNSUPPORTED_TAG
                    || code == NfcErrorCode.READ_FAILED;
        }
        return code == NfcErrorCode.NFC_DISABLED
                || code == NfcErrorCode.NFC_UNSUPPORTED
                || code == NfcErrorCode.WRITE_TIMEOUT
                || code == NfcErrorCode.TAG_LOST
                || code == NfcErrorCode.TAG_READ_ONLY
                || code == NfcErrorCode.NDEF_CAPACITY_EXCEEDED
                || code == NfcErrorCode.UNSUPPORTED_TAG
                || code == NfcErrorCode.WRITE_FAILED
                || code == NfcErrorCode.WRITE_VERIFICATION_FAILED;
    }
}
