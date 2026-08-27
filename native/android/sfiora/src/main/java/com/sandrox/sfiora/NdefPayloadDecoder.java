package com.sandrox.sfiora;

import java.nio.ByteBuffer;
import java.nio.charset.CharacterCodingException;
import java.nio.charset.Charset;
import java.nio.charset.CodingErrorAction;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;

final class NdefPayloadDecoder {
    private NdefPayloadDecoder() {
    }

    static NdefText decodeText(byte[] payload) {
        if (payload == null || payload.length == 0) {
            return null;
        }
        int status = payload[0] & 0xFF;
        if ((status & 0x40) != 0) {
            return null;
        }
        int languageLength = status & 0x3F;
        if (payload.length < 1 + languageLength) {
            return null;
        }

        String languageCode = decodeAscii(
                Arrays.copyOfRange(payload, 1, 1 + languageLength)
        );
        if (!NdefRecord.isValidDecodedLanguageCode(languageCode)) {
            return null;
        }

        boolean usesUtf16 = (status & 0x80) != 0;
        Charset charset = usesUtf16
                ? StandardCharsets.UTF_16
                : StandardCharsets.UTF_8;
        String text = decodeStrict(
                Arrays.copyOfRange(
                        payload,
                        1 + languageLength,
                        payload.length
                ),
                charset
        );
        if (text == null) {
            return null;
        }
        return new NdefText(
                text,
                languageCode,
                usesUtf16 ? NdefTextEncoding.UTF_16 : NdefTextEncoding.UTF_8
        );
    }

    static String decodeUtf8(byte[] value) {
        return decodeStrict(value, StandardCharsets.UTF_8);
    }

    static String decodeAscii(byte[] value) {
        if (value == null) {
            return null;
        }
        for (byte item : value) {
            if ((item & 0x80) != 0) {
                return null;
            }
        }
        return new String(value, StandardCharsets.US_ASCII);
    }

    private static String decodeStrict(byte[] value, Charset charset) {
        if (value == null) {
            return null;
        }
        try {
            return charset.newDecoder()
                    .onMalformedInput(CodingErrorAction.REPORT)
                    .onUnmappableCharacter(CodingErrorAction.REPORT)
                    .decode(ByteBuffer.wrap(value))
                    .toString();
        } catch (CharacterCodingException ignored) {
            return null;
        }
    }
}
