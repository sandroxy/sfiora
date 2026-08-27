package com.sandrox.sfiora;

import com.sandrox.sfiora.internal.ByteEncoding;

import org.json.JSONObject;

import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Objects;

/** Result of an NDEF write that was immediately read back and verified. */
public final class NfcWriteResult {
    private final NfcTagSnapshot tag;
    private final NdefMessage message;
    private final long completedAtEpochMillis;

    NfcWriteResult(
            NfcTagSnapshot tag,
            NdefMessage message,
            long completedAtEpochMillis
    ) {
        this.tag = Objects.requireNonNull(tag, "tag is required");
        this.message = Objects.requireNonNull(message, "message is required");
        this.completedAtEpochMillis = completedAtEpochMillis;
    }

    public NfcTagSnapshot getTag() {
        return tag;
    }

    public NfcTagSnapshot getTagSnapshot() {
        return tag;
    }

    public NdefMessage getMessage() {
        return message;
    }

    public boolean isVerified() {
        return true;
    }

    public int getBytesWritten() {
        return message.getByteCount();
    }

    public int getRecordCount() {
        return message.getRecords().size();
    }

    public long getCompletedAtEpochMillis() {
        return completedAtEpochMillis;
    }

    /** Returns a stable, immutable-shape value suitable for bridge conversion. */
    public Map<String, Object> toMap() {
        byte[] messageData = message.getSerializedData();
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("schemaVersion", 1);
        result.put("platform", "android");
        result.put("operation", "writeNdef");
        result.put("completedAtEpochMs", completedAtEpochMillis);
        result.put("verified", true);
        result.put("bytesWritten", messageData.length);
        result.put("recordCount", message.getRecords().size());
        result.put("messageHex", ByteEncoding.toHex(messageData));
        result.put("messageBase64", ByteEncoding.toBase64(messageData));
        result.put("tag", tag.toMap());
        return Collections.unmodifiableMap(result);
    }

    public String toJsonString() {
        return new JSONObject(toMap()).toString();
    }

    public String toPrettyJsonString() {
        try {
            return new JSONObject(toMap()).toString(2);
        } catch (Exception ignored) {
            return toJsonString();
        }
    }
}
