package com.sandrox.sfiora.internal;

import java.nio.charset.StandardCharsets;

public final class NdefUriCodec {
    private static final String[] PREFIXES = {
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

    private NdefUriCodec() {
    }

    public static byte[] encode(String uri) {
        int prefixIndex = 0;
        int prefixLength = 0;
        for (int index = 1; index < PREFIXES.length; index++) {
            String prefix = PREFIXES[index];
            if (uri.startsWith(prefix) && prefix.length() > prefixLength) {
                prefixIndex = index;
                prefixLength = prefix.length();
            }
        }

        byte[] suffix = uri.substring(prefixLength).getBytes(StandardCharsets.UTF_8);
        byte[] payload = new byte[suffix.length + 1];
        payload[0] = (byte) prefixIndex;
        System.arraycopy(suffix, 0, payload, 1, suffix.length);
        return payload;
    }
}
