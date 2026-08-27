package com.sandrox.sfiora.internal;

import java.nio.charset.Charset;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.LinkedHashMap;
import java.util.Map;

public final class NdefPayloadCodec {
    private static final String[] URI_PREFIXES = {
            "",
            "http://www.",
            "https://www.",
            "http://",
            "https://",
            "tel:",
            "mailto:",
            "ftp://anonymous:anonymous@",
            "ftp://ftp.",
            "ftps://",
            "sftp://",
            "smb://",
            "nfs://",
            "ftp://",
            "dav://",
            "news:",
            "telnet://",
            "imap:",
            "rtsp://",
            "urn:",
            "pop:",
            "sip:",
            "sips:",
            "tftp:",
            "btspp://",
            "btl2cap://",
            "btgoep://",
            "tcpobex://",
            "irdaobex://",
            "file://",
            "urn:epc:id:",
            "urn:epc:tag:",
            "urn:epc:pat:",
            "urn:epc:raw:",
            "urn:epc:",
            "urn:nfc:"
    };

    private NdefPayloadCodec() {
    }

    public static Map<String, Object> decodeText(byte[] payload) {
        Map<String, Object> result = new LinkedHashMap<>();
        if (payload == null || payload.length == 0) {
            return result;
        }

        int status = payload[0] & 0xFF;
        if ((status & 0x40) != 0) {
            return result;
        }
        boolean utf16 = (status & 0x80) != 0;
        int languageLength = status & 0x3F;
        if (payload.length < 1 + languageLength) {
            return result;
        }

        String languageCode = new String(payload, 1, languageLength, StandardCharsets.US_ASCII);
        Charset charset = utf16 ? StandardCharsets.UTF_16 : StandardCharsets.UTF_8;
        String text = new String(
                payload,
                1 + languageLength,
                payload.length - 1 - languageLength,
                charset
        );

        result.put("languageCode", languageCode);
        result.put("textEncoding", utf16 ? "UTF-16" : "UTF-8");
        result.put("text", text);
        return result;
    }

    public static String decodeUri(byte[] payload) {
        if (payload == null || payload.length == 0) {
            return null;
        }
        int prefixIndex = payload[0] & 0xFF;
        if (prefixIndex >= URI_PREFIXES.length) {
            return null;
        }
        String prefix = URI_PREFIXES[prefixIndex];
        String suffix = new String(
                Arrays.copyOfRange(payload, 1, payload.length),
                StandardCharsets.UTF_8
        );
        return prefix + suffix;
    }
}
