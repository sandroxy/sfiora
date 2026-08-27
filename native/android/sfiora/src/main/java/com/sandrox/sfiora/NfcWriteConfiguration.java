package com.sandrox.sfiora;

/** Immutable settings for one Android foreground NDEF write. */
public final class NfcWriteConfiguration {
    public static final long MINIMUM_TIMEOUT_MILLIS = 1_000L;
    public static final long MAXIMUM_TIMEOUT_MILLIS = 60_000L;

    private final long timeoutMillis;
    private final int presenceCheckDelayMillis;

    private NfcWriteConfiguration(Builder builder) {
        timeoutMillis = builder.timeoutMillis;
        presenceCheckDelayMillis = builder.presenceCheckDelayMillis;
    }

    public long getTimeoutMillis() {
        return timeoutMillis;
    }

    public int getPresenceCheckDelayMillis() {
        return presenceCheckDelayMillis;
    }

    public static Builder builder() {
        return new Builder();
    }

    public static final class Builder {
        private long timeoutMillis = 30_000L;
        private int presenceCheckDelayMillis = 250;

        public Builder timeoutMillis(long value) {
            timeoutMillis = value;
            return this;
        }

        public Builder presenceCheckDelayMillis(int value) {
            presenceCheckDelayMillis = value;
            return this;
        }

        public NfcWriteConfiguration build() {
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
                    < NfcReadConfiguration.MINIMUM_PRESENCE_CHECK_DELAY_MILLIS
                    || presenceCheckDelayMillis
                    > NfcReadConfiguration.MAXIMUM_PRESENCE_CHECK_DELAY_MILLIS) {
                throw new IllegalArgumentException(
                        "presenceCheckDelayMillis must be between "
                                + NfcReadConfiguration.MINIMUM_PRESENCE_CHECK_DELAY_MILLIS
                                + " and "
                                + NfcReadConfiguration.MAXIMUM_PRESENCE_CHECK_DELAY_MILLIS
                );
            }
            return new NfcWriteConfiguration(this);
        }
    }
}
