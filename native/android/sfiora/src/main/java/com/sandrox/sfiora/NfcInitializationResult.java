package com.sandrox.sfiora;

import com.sandrox.sfiora.internal.ByteEncoding;

import org.json.JSONObject;

import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Objects;

/** Result of one marker-based, single-tag NDEF initialization operation. */
public final class NfcInitializationResult {
    private final NfcInitializationAction action;
    private final NdefExternalType marker;
    private final NfcTagSnapshot tag;
    private final NdefMessage writtenMessage;
    private final long completedAtEpochMillis;

    private NfcInitializationResult(
            NfcInitializationAction action,
            NdefExternalType marker,
            NfcTagSnapshot tag,
            NdefMessage writtenMessage,
            long completedAtEpochMillis
    ) {
        this.action = Objects.requireNonNull(action, "action is required");
        this.marker = Objects.requireNonNull(marker, "marker is required");
        this.tag = Objects.requireNonNull(tag, "tag is required");
        this.writtenMessage = writtenMessage;
        this.completedAtEpochMillis = completedAtEpochMillis;
        if ((action == NfcInitializationAction.INITIALIZED
                && writtenMessage == null)
                || (action == NfcInitializationAction.PRESERVED
                && writtenMessage != null)) {
            throw new IllegalArgumentException(
                    "writtenMessage must match the initialization action"
            );
        }
    }

    static NfcInitializationResult preserved(
            NdefExternalType marker,
            NfcTagSnapshot tag,
            long completedAtEpochMillis
    ) {
        return new NfcInitializationResult(
                NfcInitializationAction.PRESERVED,
                marker,
                tag,
                null,
                completedAtEpochMillis
        );
    }

    static NfcInitializationResult initialized(
            NdefExternalType marker,
            NfcTagSnapshot tag,
            NdefMessage writtenMessage,
            long completedAtEpochMillis
    ) {
        return new NfcInitializationResult(
                NfcInitializationAction.INITIALIZED,
                marker,
                tag,
                writtenMessage,
                completedAtEpochMillis
        );
    }

    public NfcInitializationAction getAction() {
        return action;
    }

    public NdefExternalType getMarker() {
        return marker;
    }

    public NfcTagSnapshot getTag() {
        return tag;
    }

    public NfcTagSnapshot getTagSnapshot() {
        return tag;
    }

    public NdefMessage getWrittenMessage() {
        return writtenMessage;
    }

    public boolean isVerified() {
        return action == NfcInitializationAction.INITIALIZED;
    }

    public int getBytesWritten() {
        return writtenMessage == null ? 0 : writtenMessage.getByteCount();
    }

    public int getRecordCount() {
        return writtenMessage == null ? 0 : writtenMessage.getRecords().size();
    }

    public byte[] getWrittenMessageData() {
        return writtenMessage == null
                ? null
                : writtenMessage.getSerializedData();
    }

    public long getCompletedAtEpochMillis() {
        return completedAtEpochMillis;
    }

    /** Returns a stable, immutable-shape value suitable for bridge conversion. */
    public Map<String, Object> toMap() {
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("schemaVersion", 1);
        result.put("platform", "android");
        result.put("operation", "initializeNdef");
        result.put("completedAtEpochMs", completedAtEpochMillis);
        result.put("action", action.getValue());

        Map<String, Object> markerValue = new LinkedHashMap<>();
        markerValue.put("domain", marker.getDomain());
        markerValue.put("type", marker.getType());
        markerValue.put("externalType", marker.getValue());
        result.put("marker", Collections.unmodifiableMap(markerValue));

        if (writtenMessage != null) {
            byte[] messageData = writtenMessage.getSerializedData();
            result.put("verified", true);
            result.put("bytesWritten", messageData.length);
            result.put("recordCount", writtenMessage.getRecords().size());
            result.put("messageHex", ByteEncoding.toHex(messageData));
            result.put("messageBase64", ByteEncoding.toBase64(messageData));
        }
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
