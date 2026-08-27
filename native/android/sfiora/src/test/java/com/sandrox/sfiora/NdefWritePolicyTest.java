package com.sandrox.sfiora;

import org.junit.Test;

import java.util.Arrays;
import java.util.Collections;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertThrows;

public final class NdefWritePolicyTest {
    @Test
    public void initializationRequiresExactlyOneMarkerRecord() {
        NdefExternalType marker = new NdefExternalType("example.org", "sample");
        NdefRecord matching = NdefRecord.external(
                marker.getDomain(),
                marker.getType(),
                new byte[] {0x01}
        );
        NdefRecord text = NdefRecord.text("value", "en");

        NdefWritePolicy.validateInitializationMessage(
                new NdefMessage(Arrays.asList(matching, text)),
                marker
        );
        assertThrows(
                IllegalArgumentException.class,
                () -> NdefWritePolicy.validateInitializationMessage(
                        new NdefMessage(Collections.singletonList(text)),
                        marker
                )
        );
        assertThrows(
                IllegalArgumentException.class,
                () -> NdefWritePolicy.validateInitializationMessage(
                        new NdefMessage(Arrays.asList(matching, matching)),
                        marker
                )
        );
    }

    @Test
    public void writablePolicyDistinguishesPermanentTagFailures() {
        NdefMessage message = new NdefMessage(Collections.singletonList(
                NdefRecord.text("value", "en")
        ));

        NfcOperationException readOnly = assertThrows(
                NfcOperationException.class,
                () -> NdefWritePolicy.validateWritable(false, 512, message)
        );
        NfcOperationException capacity = assertThrows(
                NfcOperationException.class,
                () -> NdefWritePolicy.validateWritable(
                        true,
                        message.getByteCount() - 1,
                        message
                )
        );

        assertEquals(NfcErrorCode.TAG_READ_ONLY, readOnly.toPublicError().getCode());
        assertEquals(
                NfcErrorCode.NDEF_CAPACITY_EXCEEDED,
                capacity.toPublicError().getCode()
        );
    }

    @Test
    public void verificationUsesCanonicalMessageBytes() {
        NdefMessage expected = new NdefMessage(Collections.singletonList(
                NdefRecord.uri("https://example.org")
        ));
        NdefMessage equal = new NdefMessage(Collections.singletonList(
                NdefRecord.uri("https://example.org")
        ));
        NdefMessage different = new NdefMessage(Collections.singletonList(
                NdefRecord.uri("https://example.com")
        ));

        try {
            NdefWritePolicy.verify(expected, equal);
        } catch (NfcOperationException error) {
            throw new AssertionError(error);
        }
        NfcOperationException mismatch = assertThrows(
                NfcOperationException.class,
                () -> NdefWritePolicy.verify(expected, different)
        );
        assertEquals(
                NfcErrorCode.WRITE_VERIFICATION_FAILED,
                mismatch.toPublicError().getCode()
        );
    }
}
