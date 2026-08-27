package com.sandrox.sfiora.ui;

import android.animation.ValueAnimator;
import android.content.Context;
import android.content.res.Configuration;
import android.graphics.Canvas;
import android.graphics.Matrix;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.RectF;
import android.os.Build;
import android.util.AttributeSet;
import android.view.View;
import android.view.animation.LinearInterpolator;

/** Draws the lightweight, looping device-approach cue used by the managed NFC sheet. */
public final class NfcReaderScanAnimationView extends View {
    private static final long LOOP_DURATION_MILLIS = 2_600L;
    private static final long SUCCESS_DURATION_MILLIS = 190L;
    private static final float MAX_PHONE_PITCH_DEGREES = 22.0f;
    private static final float CAMERA_FOCAL_LENGTH_MULTIPLIER = 4.0f;
    private static final float PHONE_DEPTH_TRAVEL_MULTIPLIER = 0.68f;
    private static final float SUCCESS_DEPTH_TRAVEL_MULTIPLIER = 0.55f;

    private final float density;
    private final Paint ringPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint phoneFillPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint phoneGlarePaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint phoneBorderPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint phoneNotchPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint successCheckPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final RectF phoneRect = new RectF();
    private final RectF phoneFaceRect = new RectF();
    private final Path ringClipPath = new Path();
    private final Path phoneClipPath = new Path();
    private final Path phoneFillPath = new Path();
    private final Path phoneNotchPath = new Path();
    private final Matrix phonePerspectiveMatrix = new Matrix();
    private final float[] perspectiveSource = new float[8];
    private final float[] perspectiveDestination = new float[8];

    private ValueAnimator loopAnimator;
    private ValueAnimator successAnimator;
    private float phase;
    private float successProgress = -1.0f;
    private float successStartDistance;

    public NfcReaderScanAnimationView(Context context) {
        this(context, null);
    }

    public NfcReaderScanAnimationView(Context context, AttributeSet attrs) {
        this(context, attrs, 0);
    }

    public NfcReaderScanAnimationView(Context context, AttributeSet attrs, int defStyleAttr) {
        super(context, attrs, defStyleAttr);
        density = getResources().getDisplayMetrics().density;
        setImportantForAccessibility(IMPORTANT_FOR_ACCESSIBILITY_NO);
        configurePaints();
    }

    void startAnimation() {
        if (loopAnimator != null || successProgress >= 0.0f || !isShown()) {
            return;
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O
                && !ValueAnimator.areAnimatorsEnabled()) {
            phase = 0.5f;
            invalidate();
            return;
        }

        loopAnimator = ValueAnimator.ofFloat(0.0f, 1.0f);
        loopAnimator.setDuration(LOOP_DURATION_MILLIS);
        loopAnimator.setRepeatCount(ValueAnimator.INFINITE);
        loopAnimator.setRepeatMode(ValueAnimator.RESTART);
        loopAnimator.setInterpolator(new LinearInterpolator());
        loopAnimator.addUpdateListener(animation -> {
            phase = (float) animation.getAnimatedValue();
            invalidate();
        });
        loopAnimator.start();
    }

    void resetToPending() {
        stopAnimation();
        phase = 0.0f;
        successProgress = -1.0f;
        invalidate();
        startAnimation();
    }

    void playSuccessAnimation() {
        if (successProgress >= 0.0f) {
            return;
        }
        successStartDistance = loopDistance();
        stopLoopAnimation();
        successProgress = 0.0f;

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O
                && !ValueAnimator.areAnimatorsEnabled()) {
            successProgress = 1.0f;
            invalidate();
            return;
        }

        successAnimator = ValueAnimator.ofFloat(0.0f, 1.0f);
        successAnimator.setDuration(SUCCESS_DURATION_MILLIS);
        successAnimator.setInterpolator(new LinearInterpolator());
        successAnimator.addUpdateListener(animation -> {
            successProgress = (float) animation.getAnimatedValue();
            invalidate();
        });
        successAnimator.start();
    }

    void stopAnimation() {
        stopLoopAnimation();
        if (successAnimator != null) {
            successAnimator.cancel();
            successAnimator = null;
        }
    }

    private void stopLoopAnimation() {
        if (loopAnimator != null) {
            loopAnimator.cancel();
            loopAnimator = null;
        }
    }

    @Override
    protected void onAttachedToWindow() {
        super.onAttachedToWindow();
        startAnimation();
    }

    @Override
    protected void onDetachedFromWindow() {
        stopAnimation();
        super.onDetachedFromWindow();
    }

    @Override
    protected void onVisibilityChanged(View changedView, int visibility) {
        super.onVisibilityChanged(changedView, visibility);
        if (visibility == VISIBLE) {
            startAnimation();
        } else {
            stopAnimation();
        }
    }

    @Override
    protected void onConfigurationChanged(Configuration newConfig) {
        super.onConfigurationChanged(newConfig);
        configurePaints();
        invalidate();
    }

    @Override
    protected void onDraw(Canvas canvas) {
        super.onDraw(canvas);

        float size = Math.min(getWidth(), getHeight());
        if (size <= 0.0f) {
            return;
        }

        float centerX = getWidth() / 2.0f;
        float centerY = getHeight() / 2.0f + size * 0.012f;
        float ringRadius = size * 0.35f;

        float distance = loopDistance();
        float collapse = 0.0f;
        float phoneAlpha = 1.0f;
        if (successProgress >= 0.0f) {
            collapse = smoothStep(0.0f, 0.66f, successProgress);
            distance = lerp(
                    successStartDistance,
                    1.0f,
                    smoothStep(0.0f, 0.62f, successProgress)
            );
            phoneAlpha = 1.0f - smoothStep(0.14f, 0.66f, successProgress);
        }

        drawPhone(
                canvas,
                centerX,
                centerY,
                size,
                ringRadius,
                distance,
                collapse,
                phoneAlpha
        );

        if (successProgress >= 0.0f) {
            drawSuccessCheck(canvas, centerX, centerY, ringRadius, successProgress);
        }

        // The reader ring stays fixed above both the moving device and success stroke.
        canvas.drawCircle(centerX, centerY, ringRadius, ringPaint);
    }

    private void drawPhone(
            Canvas canvas,
            float centerX,
            float centerY,
            float size,
            float ringRadius,
            float distance,
            float collapse,
            float alpha
    ) {
        if (alpha <= 0.0f) {
            return;
        }

        float phoneWidth = size * 0.375f;
        float phoneHeight = size * 0.50f;

        float phoneVisibleBottom = centerY + ringRadius * 0.95f;
        float phoneTop = phoneVisibleBottom - phoneHeight;
        // Extend the body beyond the circle so its straight bottom edge is never visible.
        float phoneBottom = centerY + ringRadius * 1.12f;
        phoneRect.set(
                centerX - phoneWidth / 2.0f,
                phoneTop,
                centerX + phoneWidth / 2.0f,
                phoneBottom
        );

        configurePhonePerspective(
                centerX,
                phoneVisibleBottom,
                size,
                distance,
                collapse
        );

        ringClipPath.reset();
        ringClipPath.addCircle(
                centerX,
                centerY,
                ringRadius - ringPaint.getStrokeWidth() / 2.0f,
                Path.Direction.CW
        );
        canvas.save();
        canvas.clipPath(ringClipPath);
        canvas.save();
        canvas.concat(phonePerspectiveMatrix);

        int resolvedAlpha = Math.round(255.0f * clamp(alpha, 0.0f, 1.0f));
        setPhonePaintAlpha(resolvedAlpha);

        // Build the blue edge as filled geometry, rather than a constant-width
        // stroke, so its apparent thickness foreshortens with the phone plane.
        float phoneCorner = dp(6.0f);
        float borderWidth = dp(3.0f);
        canvas.drawRoundRect(phoneRect, phoneCorner, phoneCorner, phoneBorderPaint);

        phoneFaceRect.set(
                phoneRect.left + borderWidth,
                phoneRect.top + borderWidth,
                phoneRect.right - borderWidth,
                phoneRect.bottom - borderWidth
        );
        float faceCorner = Math.max(0.0f, phoneCorner - borderWidth);
        canvas.drawRoundRect(phoneFaceRect, faceCorner, faceCorner, phoneGlarePaint);

        phoneClipPath.reset();
        phoneClipPath.addRoundRect(
                phoneFaceRect,
                faceCorner,
                faceCorner,
                Path.Direction.CW
        );

        // A diagonal light face drains as the phone recedes, then fills on its return.
        float fillBoundaryStart = -0.55f + 1.17f * distance;
        float fillBoundaryEnd = fillBoundaryStart + 0.55f;
        float faceAnimationHeight = Math.max(0.0f, phoneHeight - borderWidth * 2.0f);
        phoneFillPath.reset();
        phoneFillPath.moveTo(
                phoneFaceRect.left,
                phoneFaceRect.top + faceAnimationHeight * fillBoundaryStart
        );
        phoneFillPath.lineTo(
                phoneFaceRect.right,
                phoneFaceRect.top + faceAnimationHeight * fillBoundaryEnd
        );
        phoneFillPath.lineTo(phoneFaceRect.right, phoneFaceRect.bottom);
        phoneFillPath.lineTo(phoneFaceRect.left, phoneFaceRect.bottom);
        phoneFillPath.close();
        canvas.save();
        canvas.clipPath(phoneClipPath);
        canvas.drawPath(phoneFillPath, phoneFillPaint);
        canvas.restore();

        float notchHeight = phoneHeight * 0.095f;
        float notchTop = phoneRect.top;
        float notchBottom = notchTop + notchHeight;
        float notchTopHalfWidth = phoneWidth * 0.26f;
        float notchBottomHalfWidth = phoneWidth * 0.215f;
        float notchShoulderY = notchTop + notchHeight * 0.20f;
        phoneNotchPath.reset();
        phoneNotchPath.moveTo(centerX - notchTopHalfWidth, notchTop);
        phoneNotchPath.lineTo(centerX + notchTopHalfWidth, notchTop);
        phoneNotchPath.lineTo(centerX + notchTopHalfWidth, notchShoulderY);
        phoneNotchPath.quadTo(
                centerX + notchTopHalfWidth,
                notchBottom,
                centerX + notchBottomHalfWidth,
                notchBottom
        );
        phoneNotchPath.lineTo(centerX - notchBottomHalfWidth, notchBottom);
        phoneNotchPath.quadTo(
                centerX - notchTopHalfWidth,
                notchBottom,
                centerX - notchTopHalfWidth,
                notchShoulderY
        );
        phoneNotchPath.close();
        canvas.drawPath(phoneNotchPath, phoneNotchPaint);
        canvas.restore();
        canvas.restore();
        setPhonePaintAlpha(255);
    }

    private void configurePhonePerspective(
            float centerX,
            float pivotY,
            float size,
            float distance,
            float collapse
    ) {
        perspectiveSource[0] = phoneRect.left;
        perspectiveSource[1] = phoneRect.top;
        perspectiveSource[2] = phoneRect.right;
        perspectiveSource[3] = phoneRect.top;
        perspectiveSource[4] = phoneRect.right;
        perspectiveSource[5] = phoneRect.bottom;
        perspectiveSource[6] = phoneRect.left;
        perspectiveSource[7] = phoneRect.bottom;

        float pitchRadians = (float) Math.toRadians(
                MAX_PHONE_PITCH_DEGREES * smoothStep(0.0f, 1.0f, distance)
        );
        float pitchCosine = (float) Math.cos(pitchRadians);
        float pitchSine = (float) Math.sin(pitchRadians);
        float focalLength = size * CAMERA_FOCAL_LENGTH_MULTIPLIER;
        float depthTranslation = size * (
                PHONE_DEPTH_TRAVEL_MULTIPLIER * distance
                        + SUCCESS_DEPTH_TRAVEL_MULTIPLIER * collapse
        );

        projectPhonePoint(
                0,
                phoneRect.left,
                phoneRect.top,
                centerX,
                pivotY,
                pitchCosine,
                pitchSine,
                focalLength,
                depthTranslation
        );
        projectPhonePoint(
                2,
                phoneRect.right,
                phoneRect.top,
                centerX,
                pivotY,
                pitchCosine,
                pitchSine,
                focalLength,
                depthTranslation
        );
        projectPhonePoint(
                4,
                phoneRect.right,
                phoneRect.bottom,
                centerX,
                pivotY,
                pitchCosine,
                pitchSine,
                focalLength,
                depthTranslation
        );
        projectPhonePoint(
                6,
                phoneRect.left,
                phoneRect.bottom,
                centerX,
                pivotY,
                pitchCosine,
                pitchSine,
                focalLength,
                depthTranslation
        );

        phonePerspectiveMatrix.reset();
        phonePerspectiveMatrix.setPolyToPoly(
                perspectiveSource,
                0,
                perspectiveDestination,
                0,
                4
        );
    }

    private void projectPhonePoint(
            int destinationOffset,
            float sourceX,
            float sourceY,
            float centerX,
            float pivotY,
            float pitchCosine,
            float pitchSine,
            float focalLength,
            float depthTranslation
    ) {
        float localX = sourceX - centerX;
        float localY = sourceY - pivotY;
        float rotatedY = localY * pitchCosine;
        float depth = depthTranslation - localY * pitchSine;
        float projectionScale = focalLength / (focalLength + depth);
        perspectiveDestination[destinationOffset] = centerX + localX * projectionScale;
        perspectiveDestination[destinationOffset + 1] =
                pivotY + rotatedY * projectionScale;
    }

    private void drawSuccessCheck(
            Canvas canvas,
            float centerX,
            float centerY,
            float ringRadius,
            float progress
    ) {
        float drawProgress = smoothStep(0.08f, 0.94f, progress);
        if (drawProgress <= 0.0f) {
            return;
        }

        float startX = centerX - ringRadius * 0.28f;
        float startY = centerY - ringRadius * 0.04f;
        float turnX = centerX - ringRadius * 0.02f;
        float turnY = centerY + ringRadius * 0.27f;
        float endX = centerX + ringRadius * 0.34f;
        float endY = centerY - ringRadius * 0.24f;
        float firstSegmentShare = 0.40f;

        if (drawProgress <= firstSegmentShare) {
            float segmentProgress = drawProgress / firstSegmentShare;
            canvas.drawLine(
                    startX,
                    startY,
                    lerp(startX, turnX, segmentProgress),
                    lerp(startY, turnY, segmentProgress),
                    successCheckPaint
            );
            return;
        }

        canvas.drawLine(startX, startY, turnX, turnY, successCheckPaint);
        float segmentProgress = (drawProgress - firstSegmentShare)
                / (1.0f - firstSegmentShare);
        canvas.drawLine(
                turnX,
                turnY,
                lerp(turnX, endX, segmentProgress),
                lerp(turnY, endY, segmentProgress),
                successCheckPaint
        );
    }

    private void setPhonePaintAlpha(int alpha) {
        phoneFillPaint.setAlpha(alpha);
        phoneGlarePaint.setAlpha(alpha);
        phoneBorderPaint.setAlpha(alpha);
        phoneNotchPaint.setAlpha(alpha);
    }

    private float loopDistance() {
        // The system cue keeps the reader ring still while the phone recedes and returns.
        return 0.5f - 0.5f * (float) Math.cos(phase * Math.PI * 2.0);
    }

    private void configurePaints() {
        int accent = color(R.color.nfc_reader_accent);

        ringPaint.setStyle(Paint.Style.STROKE);
        ringPaint.setStrokeWidth(dp(5.0f));
        ringPaint.setStrokeCap(Paint.Cap.ROUND);
        ringPaint.setColor(accent);

        phoneBorderPaint.setStyle(Paint.Style.FILL);
        phoneBorderPaint.setColor(accent);

        phoneFillPaint.setStyle(Paint.Style.FILL);
        phoneFillPaint.setColor(color(R.color.nfc_reader_phone_fill));

        phoneGlarePaint.setStyle(Paint.Style.FILL);
        phoneGlarePaint.setColor(color(R.color.nfc_reader_phone_glare));

        phoneNotchPaint.setStyle(Paint.Style.FILL);
        phoneNotchPaint.setColor(accent);

        successCheckPaint.setStyle(Paint.Style.STROKE);
        successCheckPaint.setStrokeWidth(dp(7.0f));
        successCheckPaint.setStrokeCap(Paint.Cap.ROUND);
        successCheckPaint.setStrokeJoin(Paint.Join.ROUND);
        successCheckPaint.setColor(accent);
    }

    private static float smoothStep(float edge0, float edge1, float value) {
        float normalized = clamp((value - edge0) / (edge1 - edge0), 0.0f, 1.0f);
        return normalized * normalized * (3.0f - 2.0f * normalized);
    }

    private static float lerp(float start, float end, float amount) {
        return start + (end - start) * amount;
    }

    private static float clamp(float value, float minimum, float maximum) {
        return Math.max(minimum, Math.min(maximum, value));
    }

    @SuppressWarnings("deprecation")
    private int color(int colorResource) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            return getContext().getColor(colorResource);
        }
        return getResources().getColor(colorResource);
    }

    private float dp(float value) {
        return value * density;
    }
}
