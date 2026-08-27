package com.sandrox.sfiora.internal;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

import java.nio.charset.StandardCharsets;
import java.util.Map;

public final class NdefPayloadCodecTest {
    @Test
    public void decodesUtf8TextPayload() {
        byte[] text = "你好".getBytes(StandardCharsets.UTF_8);
        byte[] payload = new byte[3 + text.length];
        payload[0] = 0x02;
        payload[1] = 0x7A;
        payload[2] = 0x68;
        System.arraycopy(text, 0, payload, 3, text.length);

        Map<String, Object> result = NdefPayloadCodec.decodeText(payload);

        assertEquals("zh", result.get("languageCode"));
        assertEquals("UTF-8", result.get("textEncoding"));
        assertEquals("你好", result.get("text"));
    }

    @Test
    public void expandsUriPrefix() {
        byte[] suffix = "example.com".getBytes(StandardCharsets.UTF_8);
        byte[] payload = new byte[1 + suffix.length];
        payload[0] = 0x04;
        System.arraycopy(suffix, 0, payload, 1, suffix.length);

        assertEquals("https://example.com", NdefPayloadCodec.decodeUri(payload));
    }

    @Test
    public void malformedStandardPayloadsAreNotGuessed() {
        assertTrue(NdefPayloadCodec.decodeText(new byte[]{0x40, 0x41}).isEmpty());
        assertNull(NdefPayloadCodec.decodeUri(new byte[]{(byte) 0xFF, 0x41}));
    }
}
