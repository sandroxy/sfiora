package com.sandrox.sfiora.ui;

import android.content.Context;

import java.util.Objects;

/**
 * Immutable, caller-supplied text for the optional managed Android panel.
 *
 * <p>Passing {@code null} to the controller keeps the plugin's localized Android
 * resources. A non-null value must be complete so the panel never mixes two
 * locales or guesses missing copy.</p>
 */
public final class NfcPresentationMessages {
    private NfcPresentationMessages() {}

    public static final class Scan {
        public final String title;
        public final String instruction;
        public final String cancel;
        public final String done;
        public final String success;
        public final String failureTitle;
        public final String timeout;
        public final String nfcDisabled;
        public final String nfcUnsupported;
        public final String multipleTags;
        public final String reading;
        public final String tagLost;
        public final String unsupportedTag;
        public final String readFailed;

        public Scan(
                String title,
                String instruction,
                String cancel,
                String done,
                String success,
                String failureTitle,
                String timeout,
                String nfcDisabled,
                String nfcUnsupported,
                String multipleTags,
                String reading,
                String tagLost,
                String unsupportedTag,
                String readFailed
        ) {
            this.title = requireText(title, "title");
            this.instruction = requireText(instruction, "instruction");
            this.cancel = requireText(cancel, "cancel");
            this.done = requireText(done, "done");
            this.success = requireText(success, "success");
            this.failureTitle = requireText(failureTitle, "failureTitle");
            this.timeout = requireText(timeout, "timeout");
            this.nfcDisabled = requireText(nfcDisabled, "nfcDisabled");
            this.nfcUnsupported = requireText(nfcUnsupported, "nfcUnsupported");
            this.multipleTags = requireText(multipleTags, "multipleTags");
            this.reading = requireText(reading, "reading");
            this.tagLost = requireText(tagLost, "tagLost");
            this.unsupportedTag = requireText(unsupportedTag, "unsupportedTag");
            this.readFailed = requireText(readFailed, "readFailed");
        }
    }

    public static final class Write {
        public final String title;
        public final String instruction;
        public final String cancel;
        public final String done;
        public final String success;
        public final String failureTitle;
        public final String timeout;
        public final String nfcDisabled;
        public final String nfcUnsupported;
        public final String multipleTags;
        public final String checking;
        public final String writing;
        public final String verifying;
        public final String tagLost;
        public final String tagReadOnly;
        public final String capacityExceeded;
        public final String unsupportedTag;
        public final String writeFailed;
        public final String verificationFailed;

        public Write(
                String title,
                String instruction,
                String cancel,
                String done,
                String success,
                String failureTitle,
                String timeout,
                String nfcDisabled,
                String nfcUnsupported,
                String multipleTags,
                String checking,
                String writing,
                String verifying,
                String tagLost,
                String tagReadOnly,
                String capacityExceeded,
                String unsupportedTag,
                String writeFailed,
                String verificationFailed
        ) {
            this.title = requireText(title, "title");
            this.instruction = requireText(instruction, "instruction");
            this.cancel = requireText(cancel, "cancel");
            this.done = requireText(done, "done");
            this.success = requireText(success, "success");
            this.failureTitle = requireText(failureTitle, "failureTitle");
            this.timeout = requireText(timeout, "timeout");
            this.nfcDisabled = requireText(nfcDisabled, "nfcDisabled");
            this.nfcUnsupported = requireText(nfcUnsupported, "nfcUnsupported");
            this.multipleTags = requireText(multipleTags, "multipleTags");
            this.checking = requireText(checking, "checking");
            this.writing = requireText(writing, "writing");
            this.verifying = requireText(verifying, "verifying");
            this.tagLost = requireText(tagLost, "tagLost");
            this.tagReadOnly = requireText(tagReadOnly, "tagReadOnly");
            this.capacityExceeded = requireText(capacityExceeded, "capacityExceeded");
            this.unsupportedTag = requireText(unsupportedTag, "unsupportedTag");
            this.writeFailed = requireText(writeFailed, "writeFailed");
            this.verificationFailed = requireText(
                    verificationFailed,
                    "verificationFailed"
            );
        }
    }

    static Resolved resolveScan(Context context, Scan override) {
        Objects.requireNonNull(context, "context is required");
        if (override != null) {
            return new Resolved(
                    override.title,
                    override.instruction,
                    override.cancel,
                    override.done,
                    override.success,
                    override.failureTitle,
                    override.timeout,
                    override.nfcDisabled,
                    override.nfcUnsupported,
                    override.tagLost,
                    override.unsupportedTag,
                    override.readFailed,
                    null,
                    null,
                    null
            );
        }
        return new Resolved(
                context.getString(R.string.nfc_reader_scan_title),
                context.getString(R.string.nfc_reader_scan_instruction),
                context.getString(R.string.nfc_reader_scan_cancel),
                context.getString(R.string.nfc_reader_done),
                context.getString(R.string.nfc_reader_scan_success),
                context.getString(R.string.nfc_reader_scan_failed),
                context.getString(R.string.nfc_reader_scan_timeout_feedback),
                context.getString(R.string.nfc_reader_scan_nfc_disabled),
                context.getString(R.string.nfc_reader_scan_nfc_unsupported),
                context.getString(R.string.nfc_reader_scan_tag_lost),
                context.getString(R.string.nfc_reader_scan_unsupported),
                context.getString(R.string.nfc_reader_scan_failed_detail),
                null,
                null,
                null
        );
    }

    static Resolved resolveWrite(Context context, Write override) {
        Objects.requireNonNull(context, "context is required");
        if (override != null) {
            return new Resolved(
                    override.title,
                    override.instruction,
                    override.cancel,
                    override.done,
                    override.success,
                    override.failureTitle,
                    override.timeout,
                    override.nfcDisabled,
                    override.nfcUnsupported,
                    override.tagLost,
                    override.unsupportedTag,
                    override.writeFailed,
                    override.tagReadOnly,
                    override.capacityExceeded,
                    override.verificationFailed
            );
        }
        return new Resolved(
                context.getString(R.string.nfc_reader_write_title),
                context.getString(R.string.nfc_reader_write_instruction),
                context.getString(R.string.nfc_reader_scan_cancel),
                context.getString(R.string.nfc_reader_done),
                context.getString(R.string.nfc_reader_write_success),
                context.getString(R.string.nfc_reader_write_failed),
                context.getString(R.string.nfc_reader_write_timeout_feedback),
                context.getString(R.string.nfc_reader_scan_nfc_disabled),
                context.getString(R.string.nfc_reader_scan_nfc_unsupported),
                context.getString(R.string.nfc_reader_scan_tag_lost),
                context.getString(R.string.nfc_reader_write_unsupported),
                context.getString(R.string.nfc_reader_write_failed_detail),
                context.getString(R.string.nfc_reader_write_read_only),
                context.getString(R.string.nfc_reader_write_capacity_exceeded),
                context.getString(R.string.nfc_reader_write_verification_failed)
        );
    }

    private static String requireText(String value, String name) {
        if (value == null || value.trim().isEmpty()) {
            throw new IllegalArgumentException(name + " must be a non-empty string");
        }
        return value;
    }

    static final class Resolved {
        final String title;
        final String instruction;
        final String cancel;
        final String done;
        final String success;
        final String failureTitle;
        final String timeout;
        final String nfcDisabled;
        final String nfcUnsupported;
        final String tagLost;
        final String unsupportedTag;
        final String failed;
        final String tagReadOnly;
        final String capacityExceeded;
        final String verificationFailed;

        private Resolved(
                String title,
                String instruction,
                String cancel,
                String done,
                String success,
                String failureTitle,
                String timeout,
                String nfcDisabled,
                String nfcUnsupported,
                String tagLost,
                String unsupportedTag,
                String failed,
                String tagReadOnly,
                String capacityExceeded,
                String verificationFailed
        ) {
            this.title = title;
            this.instruction = instruction;
            this.cancel = cancel;
            this.done = done;
            this.success = success;
            this.failureTitle = failureTitle;
            this.timeout = timeout;
            this.nfcDisabled = nfcDisabled;
            this.nfcUnsupported = nfcUnsupported;
            this.tagLost = tagLost;
            this.unsupportedTag = unsupportedTag;
            this.failed = failed;
            this.tagReadOnly = tagReadOnly;
            this.capacityExceeded = capacityExceeded;
            this.verificationFailed = verificationFailed;
        }
    }
}
