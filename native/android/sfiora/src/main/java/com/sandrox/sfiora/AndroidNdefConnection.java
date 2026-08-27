package com.sandrox.sfiora;

import android.nfc.FormatException;
import android.nfc.Tag;
import android.nfc.tech.Ndef;

import java.io.IOException;

final class AndroidNdefConnection implements AutoCloseable {
    static final class ReadResult {
        private final android.nfc.NdefMessage platformMessage;
        private final NdefMessage message;
        private final NfcOperationException conversionError;

        private ReadResult(
                android.nfc.NdefMessage platformMessage,
                NdefMessage message,
                NfcOperationException conversionError
        ) {
            this.platformMessage = platformMessage;
            this.message = message;
            this.conversionError = conversionError;
        }

        android.nfc.NdefMessage getPlatformMessage() {
            return platformMessage;
        }

        NdefMessage getMessage() {
            return message;
        }

        NfcOperationException getConversionError() {
            return conversionError;
        }
    }

    private final Tag tag;
    private final Ndef technology;

    private AndroidNdefConnection(Tag tag, Ndef technology) {
        this.tag = tag;
        this.technology = technology;
    }

    static AndroidNdefConnection from(Tag tag) {
        Ndef technology = Ndef.get(tag);
        return technology == null
                ? null
                : new AndroidNdefConnection(tag, technology);
    }

    void connect() throws IOException {
        technology.connect();
    }

    boolean isWritable() {
        return technology.isWritable();
    }

    boolean canMakeReadOnly() {
        return technology.canMakeReadOnly();
    }

    int getCapacityBytes() {
        return technology.getMaxSize();
    }

    String getType() {
        return technology.getType();
    }

    ReadResult read() throws IOException, FormatException {
        return convert(technology.getNdefMessage());
    }

    ReadResult readWithCachedFallback()
            throws IOException, FormatException {
        android.nfc.NdefMessage platformMessage = technology.getNdefMessage();
        if (platformMessage == null) {
            platformMessage = technology.getCachedNdefMessage();
        }
        return convert(platformMessage);
    }

    void write(NdefMessage message)
            throws IOException, FormatException, NfcOperationException {
        technology.writeNdefMessage(AndroidNdefCodec.toPlatform(message));
    }

    Tag getTag() {
        return tag;
    }

    private static ReadResult convert(android.nfc.NdefMessage platformMessage) {
        try {
            return new ReadResult(
                    platformMessage,
                    AndroidNdefCodec.fromPlatform(platformMessage),
                    null
            );
        } catch (NfcOperationException error) {
            return new ReadResult(platformMessage, null, error);
        }
    }

    @Override
    public void close() throws IOException {
        technology.close();
    }
}
