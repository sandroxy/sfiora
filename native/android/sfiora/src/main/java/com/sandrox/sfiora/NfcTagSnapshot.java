package com.sandrox.sfiora;

import org.json.JSONObject;

import java.util.ArrayList;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;

/**
 * Immutable data observed during one NFC tag operation.
 *
 * <p>The typed accessors are the preferred native API. {@link #toMap()} keeps
 * the complete, recursively immutable representation needed by bridge layers,
 * including platform-specific metadata and non-fatal read diagnostics.</p>
 */
public final class NfcTagSnapshot {
    public static final int SCHEMA_VERSION = 1;

    private final byte[] identifier;
    private final List<NfcTechnology> technologies;
    private final List<String> nativeTechnologies;
    private final NfcNdefStatus ndefStatus;
    private final NfcNdefStatus ndefAccessStatus;
    private final Integer ndefCapacityBytes;
    private final Boolean ndefWritable;
    private final Boolean ndefCanMakeReadOnly;
    private final String ndefType;
    private final NdefMessage ndefMessage;
    private final List<String> warnings;
    private final Map<String, Object> platformDetails;
    private final Map<String, Object> ndefReadError;
    private final Map<String, Object> readOnlyProbes;
    private final long discoveredAtEpochMillis;
    private final Map<String, Object> values;

    NfcTagSnapshot(
            byte[] identifier,
            List<NfcTechnology> technologies,
            NfcNdefStatus ndefStatus,
            Integer ndefCapacityBytes,
            NdefMessage ndefMessage,
            long discoveredAtEpochMillis
    ) {
        this(builder()
                .identifier(identifier)
                .technologies(technologies)
                .ndefStatus(ndefStatus)
                .ndefCapacityBytes(ndefCapacityBytes)
                .ndefMessage(ndefMessage)
                .discoveredAtEpochMillis(discoveredAtEpochMillis));
    }

    private NfcTagSnapshot(Builder builder) {
        identifier = builder.identifier == null ? null : builder.identifier.clone();
        technologies = immutableList(builder.technologies, "technologies");
        nativeTechnologies = immutableList(
                builder.nativeTechnologies,
                "nativeTechnologies"
        );
        ndefStatus = Objects.requireNonNull(builder.ndefStatus, "ndefStatus is required");
        ndefAccessStatus = builder.ndefAccessStatus;
        if (builder.ndefCapacityBytes != null && builder.ndefCapacityBytes < 0) {
            throw new IllegalArgumentException("ndefCapacityBytes cannot be negative");
        }
        ndefCapacityBytes = builder.ndefCapacityBytes;
        ndefWritable = builder.ndefWritable;
        ndefCanMakeReadOnly = builder.ndefCanMakeReadOnly;
        ndefType = builder.ndefType;
        ndefMessage = builder.ndefMessage;
        warnings = immutableList(builder.warnings, "warnings");
        platformDetails = immutableMap(builder.platformDetails);
        ndefReadError = immutableNullableMap(builder.ndefReadError);
        readOnlyProbes = immutableNullableMap(builder.readOnlyProbes);
        discoveredAtEpochMillis = builder.discoveredAtEpochMillis;
        values = immutableMap(
                builder.values == null ? defaultValues(builder) : builder.values
        );
    }

    static Builder builder() {
        return new Builder();
    }

    public int getSchemaVersion() {
        return SCHEMA_VERSION;
    }

    public String getPlatform() {
        return "android";
    }

    public boolean hasIdentifier() {
        return identifier != null;
    }

    public byte[] getIdentifier() {
        return identifier == null ? null : identifier.clone();
    }

    public List<NfcTechnology> getTechnologies() {
        return technologies;
    }

    public List<String> getNativeTechnologies() {
        return nativeTechnologies;
    }

    public NfcNdefStatus getNdefStatus() {
        return ndefStatus;
    }

    /** Returns the last known access status when {@link #getNdefStatus()} is READ_ERROR. */
    public NfcNdefStatus getNdefAccessStatus() {
        return ndefAccessStatus;
    }

    public Integer getNdefCapacityBytes() {
        return ndefCapacityBytes;
    }

    public Boolean isNdefWritable() {
        return ndefWritable;
    }

    public Boolean canMakeNdefReadOnly() {
        return ndefCanMakeReadOnly;
    }

    public String getNdefType() {
        return ndefType;
    }

    public NdefMessage getNdefMessage() {
        return ndefMessage;
    }

    public List<String> getWarnings() {
        return warnings;
    }

    /** Returns recursively immutable Android protocol metadata. */
    public Map<String, Object> getPlatformDetails() {
        return platformDetails;
    }

    /** Returns a recursively immutable native NDEF error, or {@code null}. */
    public Map<String, Object> getNdefReadError() {
        return ndefReadError;
    }

    /** Returns recursively immutable opt-in read-only probe results, or {@code null}. */
    public Map<String, Object> getReadOnlyProbes() {
        return readOnlyProbes;
    }

    public long getDiscoveredAtEpochMillis() {
        return discoveredAtEpochMillis;
    }

    /** Returns the complete recursively immutable bridge representation. */
    public Map<String, Object> toMap() {
        return values;
    }

    public String toJsonString() {
        return new JSONObject(values).toString();
    }

    public String toPrettyJsonString() {
        try {
            return new JSONObject(values).toString(2);
        } catch (Exception ignored) {
            return toJsonString();
        }
    }

    private static Map<String, Object> defaultValues(Builder builder) {
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("schemaVersion", SCHEMA_VERSION);
        result.put("platform", "android");
        result.put("discoveredAtEpochMs", builder.discoveredAtEpochMillis);
        result.put("technologies", technologyValues(builder.technologies));
        result.put("nativeTechnologies", new ArrayList<>(builder.nativeTechnologies));
        result.put("warnings", new ArrayList<>(builder.warnings));
        return result;
    }

    private static List<String> technologyValues(List<NfcTechnology> source) {
        List<String> result = new ArrayList<>(source.size());
        for (NfcTechnology technology : source) {
            result.add(technology.getValue());
        }
        return result;
    }

    private static <T> List<T> immutableList(List<T> source, String name) {
        return Collections.unmodifiableList(new ArrayList<>(Objects.requireNonNull(
                source,
                name + " is required"
        )));
    }

    private static Map<String, Object> immutableNullableMap(Map<?, ?> source) {
        return source == null ? null : immutableMap(source);
    }

    private static Map<String, Object> immutableMap(Map<?, ?> source) {
        Map<String, Object> result = new LinkedHashMap<>();
        if (source != null) {
            for (Map.Entry<?, ?> entry : source.entrySet()) {
                if (!(entry.getKey() instanceof String)) {
                    throw new IllegalArgumentException("Snapshot map keys must be strings");
                }
                result.put((String) entry.getKey(), immutableValue(entry.getValue()));
            }
        }
        return Collections.unmodifiableMap(result);
    }

    private static Object immutableValue(Object value) {
        if (value instanceof Map<?, ?>) {
            return immutableMap((Map<?, ?>) value);
        }
        if (value instanceof List<?>) {
            List<Object> result = new ArrayList<>();
            for (Object item : (List<?>) value) {
                result.add(immutableValue(item));
            }
            return Collections.unmodifiableList(result);
        }
        if (value == null
                || value instanceof String
                || value instanceof Number
                || value instanceof Boolean) {
            return value;
        }
        throw new IllegalArgumentException(
                "Unsupported snapshot value type: " + value.getClass().getName()
        );
    }

    static final class Builder {
        private byte[] identifier;
        private List<NfcTechnology> technologies = Collections.emptyList();
        private List<String> nativeTechnologies = Collections.emptyList();
        private NfcNdefStatus ndefStatus = NfcNdefStatus.NOT_CHECKED;
        private NfcNdefStatus ndefAccessStatus;
        private Integer ndefCapacityBytes;
        private Boolean ndefWritable;
        private Boolean ndefCanMakeReadOnly;
        private String ndefType;
        private NdefMessage ndefMessage;
        private List<String> warnings = Collections.emptyList();
        private Map<String, Object> platformDetails = Collections.emptyMap();
        private Map<String, Object> ndefReadError;
        private Map<String, Object> readOnlyProbes;
        private long discoveredAtEpochMillis;
        private Map<String, Object> values;

        Builder identifier(byte[] value) {
            identifier = value == null ? null : value.clone();
            return this;
        }

        Builder technologies(List<NfcTechnology> value) {
            technologies = value;
            return this;
        }

        Builder nativeTechnologies(List<String> value) {
            nativeTechnologies = value;
            return this;
        }

        Builder ndefStatus(NfcNdefStatus value) {
            ndefStatus = value;
            return this;
        }

        Builder ndefAccessStatus(NfcNdefStatus value) {
            ndefAccessStatus = value;
            return this;
        }

        Builder ndefCapacityBytes(Integer value) {
            ndefCapacityBytes = value;
            return this;
        }

        Builder ndefWritable(Boolean value) {
            ndefWritable = value;
            return this;
        }

        Builder ndefCanMakeReadOnly(Boolean value) {
            ndefCanMakeReadOnly = value;
            return this;
        }

        Builder ndefType(String value) {
            ndefType = value;
            return this;
        }

        Builder ndefMessage(NdefMessage value) {
            ndefMessage = value;
            return this;
        }

        Builder warnings(List<String> value) {
            warnings = value;
            return this;
        }

        Builder platformDetails(Map<String, Object> value) {
            platformDetails = value;
            return this;
        }

        Builder ndefReadError(Map<String, Object> value) {
            ndefReadError = value;
            return this;
        }

        Builder readOnlyProbes(Map<String, Object> value) {
            readOnlyProbes = value;
            return this;
        }

        Builder discoveredAtEpochMillis(long value) {
            discoveredAtEpochMillis = value;
            return this;
        }

        Builder values(Map<String, Object> value) {
            values = value;
            return this;
        }

        NfcTagSnapshot build() {
            return new NfcTagSnapshot(this);
        }
    }
}
