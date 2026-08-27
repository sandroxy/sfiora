package com.sandrox.sfiora;

import java.util.Arrays;

final class NdefWritePolicy {
    private NdefWritePolicy() {
    }

    static void validateInitializationMessage(
            NdefMessage message,
            NdefExternalType marker
    ) {
        int matches = 0;
        for (NdefRecord record : message.getRecords()) {
            if (marker.matches(record)) {
                matches++;
            }
        }
        if (matches != 1) {
            throw new IllegalArgumentException(
                    "The initialization message must contain exactly one "
                            + "record matching the external type marker"
            );
        }
    }

    static void validateWritable(
            boolean writable,
            int capacityBytes,
            NdefMessage message
    ) throws NfcOperationException {
        if (!writable) {
            throw new NfcOperationException(
                    NfcErrorCode.TAG_READ_ONLY,
                    "The detected NDEF tag is read-only",
                    false
            );
        }
        if (message.getByteCount() > capacityBytes) {
            throw new NfcOperationException(
                    NfcErrorCode.NDEF_CAPACITY_EXCEEDED,
                    "The NDEF message requires "
                            + message.getByteCount()
                            + " bytes but the tag capacity is "
                            + capacityBytes
                            + " bytes",
                    false
            );
        }
    }

    static void verify(NdefMessage expected, NdefMessage actual)
            throws NfcOperationException {
        if (actual == null
                || !Arrays.equals(
                expected.getSerializedData(),
                actual.getSerializedData()
        )) {
            throw new NfcOperationException(
                    NfcErrorCode.WRITE_VERIFICATION_FAILED,
                    "The NDEF message read from the tag differs from the message written",
                    true
            );
        }
    }
}
