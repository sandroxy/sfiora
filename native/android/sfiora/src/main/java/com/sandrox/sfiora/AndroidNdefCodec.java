package com.sandrox.sfiora;

import android.nfc.NdefRecord;

import java.util.ArrayList;
import java.util.List;

final class AndroidNdefCodec {
    private AndroidNdefCodec() {
    }

    static com.sandrox.sfiora.NdefMessage fromPlatform(
            android.nfc.NdefMessage message
    ) throws NfcOperationException {
        if (message == null) {
            return null;
        }
        List<com.sandrox.sfiora.NdefRecord> records = new ArrayList<>();
        try {
            for (NdefRecord record : message.getRecords()) {
                records.add(new com.sandrox.sfiora.NdefRecord(
                        fromPlatformTypeNameFormat(record.getTnf()),
                        record.getType(),
                        record.getId(),
                        record.getPayload()
                ));
            }
            return new com.sandrox.sfiora.NdefMessage(records);
        } catch (IllegalArgumentException error) {
            throw new NfcOperationException(
                    NfcErrorCode.READ_FAILED,
                    "The tag contains an unsupported or malformed NDEF message",
                    false,
                    error
            );
        }
    }

    static android.nfc.NdefMessage toPlatform(
            com.sandrox.sfiora.NdefMessage message
    ) throws NfcOperationException {
        NdefRecord[] records = new NdefRecord[message.getRecords().size()];
        try {
            for (int index = 0; index < records.length; index++) {
                com.sandrox.sfiora.NdefRecord record =
                        message.getRecords().get(index);
                records[index] = new NdefRecord(
                        (short) record.getTypeNameFormat().getValue(),
                        record.typeBytes(),
                        record.identifierBytes(),
                        record.payloadBytes()
                );
            }
            return new android.nfc.NdefMessage(records);
        } catch (IllegalArgumentException error) {
            throw new NfcOperationException(
                    NfcErrorCode.INTERNAL_ERROR,
                    "The validated NDEF message could not be converted for Android",
                    false,
                    error
            );
        }
    }

    private static NdefTypeNameFormat fromPlatformTypeNameFormat(short value)
            throws NfcOperationException {
        switch (value) {
            case NdefRecord.TNF_EMPTY:
                return NdefTypeNameFormat.EMPTY;
            case NdefRecord.TNF_WELL_KNOWN:
                return NdefTypeNameFormat.WELL_KNOWN;
            case NdefRecord.TNF_MIME_MEDIA:
                return NdefTypeNameFormat.MIME_MEDIA;
            case NdefRecord.TNF_ABSOLUTE_URI:
                return NdefTypeNameFormat.ABSOLUTE_URI;
            case NdefRecord.TNF_EXTERNAL_TYPE:
                return NdefTypeNameFormat.EXTERNAL_TYPE;
            case NdefRecord.TNF_UNKNOWN:
                return NdefTypeNameFormat.UNKNOWN;
            case NdefRecord.TNF_UNCHANGED:
            default:
                throw new NfcOperationException(
                        NfcErrorCode.READ_FAILED,
                        "The tag contains an unsupported NDEF type name format",
                        false
                );
        }
    }
}
