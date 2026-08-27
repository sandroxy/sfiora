package com.sandrox.sfiora;

import java.util.Objects;

/** Immutable settings for one Android foreground NFC scan. */
public final class NfcReadConfiguration {
    public static final long MINIMUM_TIMEOUT_MILLIS = 1_000L;
    public static final long MAXIMUM_TIMEOUT_MILLIS = 60_000L;
    public static final int MINIMUM_PRESENCE_CHECK_DELAY_MILLIS = 50;
    public static final int MAXIMUM_PRESENCE_CHECK_DELAY_MILLIS = 5_000;

    private final NfcReadMode mode;
    private final long timeoutMillis;
    private final boolean deepReadEnabled;
    private final int presenceCheckDelayMillis;

    private NfcReadConfiguration(Builder builder) {
        mode = builder.mode;
        timeoutMillis = builder.timeoutMillis;
        deepReadEnabled = builder.deepReadEnabled;
        presenceCheckDelayMillis = builder.presenceCheckDelayMillis;
    }

    public NfcReadMode getMode() {
        return mode;
    }

    public long getTimeoutMillis() {
        return timeoutMillis;
    }

    /**
     * Returns whether opt-in, read-only protocol probes are enabled.
     *
     * <p>These probes issue only read/authentication commands. They never
     * format, write, lock, or change authentication data on a tag.</p>
     */
    public boolean isDeepReadEnabled() {
        return deepReadEnabled;
    }

    public int getPresenceCheckDelayMillis() {
        return presenceCheckDelayMillis;
    }

    public static Builder builder() {
        return new Builder();
    }

    public static final class Builder {
        private NfcReadMode mode = NfcReadMode.AUTOMATIC;
        private long timeoutMillis = 30_000L;
        private boolean deepReadEnabled;
        private int presenceCheckDelayMillis = 250;

        public Builder mode(NfcReadMode value) {
            mode = Objects.requireNonNull(value, "mode is required");
            return this;
        }

        public Builder timeoutMillis(long value) {
            timeoutMillis = value;
            return this;
        }

        public Builder deepReadEnabled(boolean enabled) {
            deepReadEnabled = enabled;
            return this;
        }

        public Builder presenceCheckDelayMillis(int value) {
            presenceCheckDelayMillis = value;
            return this;
        }

        public NfcReadConfiguration build() {
            if (timeoutMillis < MINIMUM_TIMEOUT_MILLIS
                    || timeoutMillis > MAXIMUM_TIMEOUT_MILLIS) {
                throw new IllegalArgumentException(
                        "timeoutMillis must be between "
                                + MINIMUM_TIMEOUT_MILLIS
                                + " and "
                                + MAXIMUM_TIMEOUT_MILLIS
                );
            }
            if (presenceCheckDelayMillis
                    < MINIMUM_PRESENCE_CHECK_DELAY_MILLIS
                    || presenceCheckDelayMillis
                    > MAXIMUM_PRESENCE_CHECK_DELAY_MILLIS) {
                throw new IllegalArgumentException(
                        "presenceCheckDelayMillis must be between "
                                + MINIMUM_PRESENCE_CHECK_DELAY_MILLIS
                                + " and "
                                + MAXIMUM_PRESENCE_CHECK_DELAY_MILLIS
                );
            }
            return new NfcReadConfiguration(this);
        }
    }
}
