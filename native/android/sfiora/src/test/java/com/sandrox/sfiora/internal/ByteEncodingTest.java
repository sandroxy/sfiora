package com.sandrox.sfiora.internal;

import static org.junit.Assert.assertArrayEquals;
import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertThrows;

import org.junit.Test;

public final class ByteEncodingTest {
    @Test
    public void hexRoundTripIsStable() {
        byte[] bytes = {0x00, 0x01, 0x0F, 0x10, (byte) 0xFE, (byte) 0xFF};

        assertEquals("00010F10FEFF", ByteEncoding.toHex(bytes));
        assertArrayEquals(bytes, ByteEncoding.fromHex("00010F10FEFF"));
    }

    @Test
    public void commonHexSeparatorsAreAccepted() {
        assertArrayEquals(
                new byte[]{0x01, 0x23, 0x45, 0x67},
                ByteEncoding.fromHex("01:23 45-67")
        );
    }

    @Test
    public void malformedHexIsRejected() {
        assertThrows(
                IllegalArgumentException.class,
                () -> ByteEncoding.fromHex("ABC")
        );
        assertThrows(
                IllegalArgumentException.class,
                () -> ByteEncoding.fromHex("01GG")
        );
    }
}
