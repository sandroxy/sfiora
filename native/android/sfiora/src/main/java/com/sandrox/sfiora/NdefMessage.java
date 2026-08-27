package com.sandrox.sfiora;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Objects;

/**
 * One complete NDEF message with deterministic NFC Forum serialization.
 */
public final class NdefMessage {
    private final List<NdefRecord> records;
    private final byte[] serializedData;

    public NdefMessage(List<NdefRecord> records) {
        if (records == null || records.isEmpty()) {
            throw new IllegalArgumentException(
                    "An NDEF message must contain at least one record"
            );
        }
        List<NdefRecord> copy = new ArrayList<>(records.size());
        for (NdefRecord record : records) {
            if (record == null) {
                throw new IllegalArgumentException(
                        "NDEF message records cannot contain null"
                );
            }
            copy.add(record);
        }
        this.records = Collections.unmodifiableList(copy);
        serializedData = NdefMessageEncoder.encode(this.records);
    }

    public List<NdefRecord> getRecords() {
        return records;
    }

    public int getByteCount() {
        return serializedData.length;
    }

    public byte[] getSerializedData() {
        return serializedData.clone();
    }

    @Override
    public boolean equals(Object other) {
        if (this == other) {
            return true;
        }
        if (!(other instanceof NdefMessage)) {
            return false;
        }
        NdefMessage that = (NdefMessage) other;
        return records.equals(that.records);
    }

    @Override
    public int hashCode() {
        return Objects.hash(records);
    }
}
