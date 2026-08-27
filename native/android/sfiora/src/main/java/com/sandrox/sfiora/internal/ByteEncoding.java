package com.sandrox.sfiora.internal;

import android.util.Base64;

public final class ByteEncoding {
    private static final char[] HEX = "0123456789ABCDEF".toCharArray();

    private ByteEncoding() {
    }

    public static String toHex(byte[] bytes) {
        if (bytes == null || bytes.length == 0) {
            return "";
        }
        char[] chars = new char[bytes.length * 2];
        for (int i = 0; i < bytes.length; i++) {
            int value = bytes[i] & 0xFF;
            chars[i * 2] = HEX[value >>> 4];
            chars[i * 2 + 1] = HEX[value & 0x0F];
        }
        return new String(chars);
    }

    public static byte[] fromHex(String value) {
        if (value == null) {
            return new byte[0];
        }
        StringBuilder normalizedBuilder = new StringBuilder(value.length());
        for (int index = 0; index < value.length(); index++) {
            char character = value.charAt(index);
            if (Character.digit(character, 16) >= 0) {
                normalizedBuilder.append(character);
            } else if (!Character.isWhitespace(character)
                    && character != ':'
                    && character != '-') {
                throw new IllegalArgumentException(
                        "HEX string contains an unsupported character"
                );
            }
        }
        String normalized = normalizedBuilder.toString();
        if ((normalized.length() & 1) != 0) {
            throw new IllegalArgumentException("HEX string must contain an even number of digits");
        }
        byte[] result = new byte[normalized.length() / 2];
        for (int i = 0; i < normalized.length(); i += 2) {
            int high = Character.digit(normalized.charAt(i), 16);
            int low = Character.digit(normalized.charAt(i + 1), 16);
            if (high < 0 || low < 0) {
                throw new IllegalArgumentException("Invalid HEX string");
            }
            result[i / 2] = (byte) ((high << 4) | low);
        }
        return result;
    }

    public static String toBase64(byte[] bytes) {
        if (bytes == null || bytes.length == 0) {
            return "";
        }
        return Base64.encodeToString(bytes, Base64.NO_WRAP);
    }
}
