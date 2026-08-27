package com.sandrox.sfiora;

import java.util.List;

final class NdefMessageEncoder {
    private NdefMessageEncoder() {
    }

    static byte[] encode(List<NdefRecord> records) {
        long encodedLength = 0L;
        for (NdefRecord record : records) {
            byte[] type = record.typeBytes();
            byte[] identifier = record.identifierBytes();
            byte[] payload = record.payloadBytes();
            encodedLength += 2L;
            encodedLength += payload.length <= 0xFF ? 1L : 4L;
            encodedLength += identifier.length == 0 ? 0L : 1L;
            encodedLength += type.length;
            encodedLength += identifier.length;
            encodedLength += payload.length;
            if (encodedLength > Integer.MAX_VALUE) {
                throw new IllegalArgumentException(
                        "The encoded NDEF message is too large"
                );
            }
        }

        byte[] encoded = new byte[(int) encodedLength];
        int offset = 0;
        for (int index = 0; index < records.size(); index++) {
            NdefRecord record = records.get(index);
            byte[] type = record.typeBytes();
            byte[] identifier = record.identifierBytes();
            byte[] payload = record.payloadBytes();
            boolean shortRecord = payload.length <= 0xFF;
            boolean hasIdentifier = identifier.length > 0;

            int header = record.getTypeNameFormat().getValue() & 0x07;
            if (index == 0) {
                header |= 0x80;
            }
            if (index == records.size() - 1) {
                header |= 0x40;
            }
            if (shortRecord) {
                header |= 0x10;
            }
            if (hasIdentifier) {
                header |= 0x08;
            }

            encoded[offset++] = (byte) header;
            encoded[offset++] = (byte) type.length;
            if (shortRecord) {
                encoded[offset++] = (byte) payload.length;
            } else {
                encoded[offset++] = (byte) ((payload.length >>> 24) & 0xFF);
                encoded[offset++] = (byte) ((payload.length >>> 16) & 0xFF);
                encoded[offset++] = (byte) ((payload.length >>> 8) & 0xFF);
                encoded[offset++] = (byte) (payload.length & 0xFF);
            }
            if (hasIdentifier) {
                encoded[offset++] = (byte) identifier.length;
            }
            offset = copy(type, encoded, offset);
            if (hasIdentifier) {
                offset = copy(identifier, encoded, offset);
            }
            offset = copy(payload, encoded, offset);
        }
        return encoded;
    }

    private static int copy(byte[] source, byte[] destination, int offset) {
        System.arraycopy(source, 0, destination, offset, source.length);
        return offset + source.length;
    }
}
