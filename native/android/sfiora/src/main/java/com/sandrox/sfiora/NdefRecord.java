package com.sandrox.sfiora;

import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.Locale;
import java.util.Objects;

/**
 * One immutable, complete NDEF record.
 *
 * <p>The factory methods implement common NFC Forum record types without
 * interpreting or transforming application payloads.</p>
 */
public final class NdefRecord {
    private static final byte[] TEXT_TYPE = {0x54};
    private static final byte[] URI_TYPE = {0x55};

    private final NdefTypeNameFormat typeNameFormat;
    private final byte[] type;
    private final byte[] identifier;
    private final byte[] payload;

    public NdefRecord(
            NdefTypeNameFormat typeNameFormat,
            byte[] type,
            byte[] identifier,
            byte[] payload
    ) {
        this.typeNameFormat = Objects.requireNonNull(
                typeNameFormat,
                "typeNameFormat is required"
        );
        this.type = copyRequired(type, "type");
        this.identifier = copyRequired(identifier, "identifier");
        this.payload = copyRequired(payload, "payload");

        if (this.type.length > 0xFF) {
            throw new IllegalArgumentException(
                    "NDEF record type cannot exceed 255 bytes"
            );
        }
        if (this.identifier.length > 0xFF) {
            throw new IllegalArgumentException(
                    "NDEF record identifier cannot exceed 255 bytes"
            );
        }
        validateShape();
    }

    public NdefRecord(
            NdefTypeNameFormat typeNameFormat,
            byte[] type,
            byte[] payload
    ) {
        this(typeNameFormat, type, new byte[0], payload);
    }

    public static NdefRecord text(String text, String languageCode) {
        return text(
                text,
                languageCode,
                NdefTextEncoding.UTF_8,
                new byte[0]
        );
    }

    public static NdefRecord text(
            String text,
            String languageCode,
            NdefTextEncoding encoding
    ) {
        return text(text, languageCode, encoding, new byte[0]);
    }

    public static NdefRecord text(
            String text,
            String languageCode,
            NdefTextEncoding encoding,
            byte[] identifier
    ) {
        Objects.requireNonNull(text, "text is required");
        Objects.requireNonNull(encoding, "encoding is required");
        byte[] languageBytes = validatedLanguageCode(languageCode);
        byte[] textBytes = text.getBytes(
                encoding == NdefTextEncoding.UTF_16
                        ? StandardCharsets.UTF_16BE
                        : StandardCharsets.UTF_8
        );
        byte[] encodedPayload = new byte[
                1 + languageBytes.length + textBytes.length
        ];
        encodedPayload[0] = (byte) (
                (encoding == NdefTextEncoding.UTF_16 ? 0x80 : 0x00)
                        | languageBytes.length
        );
        System.arraycopy(
                languageBytes,
                0,
                encodedPayload,
                1,
                languageBytes.length
        );
        System.arraycopy(
                textBytes,
                0,
                encodedPayload,
                1 + languageBytes.length,
                textBytes.length
        );
        return new NdefRecord(
                NdefTypeNameFormat.WELL_KNOWN,
                TEXT_TYPE,
                identifier,
                encodedPayload
        );
    }

    public static NdefRecord uri(String uri) {
        return uri(uri, new byte[0]);
    }

    public static NdefRecord uri(String uri, byte[] identifier) {
        if (uri == null || uri.isEmpty()) {
            throw new IllegalArgumentException("NDEF URI value cannot be empty");
        }
        return new NdefRecord(
                NdefTypeNameFormat.WELL_KNOWN,
                URI_TYPE,
                identifier,
                NdefUriCodec.encode(uri)
        );
    }

    public static NdefRecord mime(String mediaType, byte[] payload) {
        return mime(mediaType, payload, new byte[0]);
    }

    public static NdefRecord mime(
            String mediaType,
            byte[] payload,
            byte[] identifier
    ) {
        if (!isValidMimeType(mediaType)) {
            throw new IllegalArgumentException(
                    "NDEF MIME type must be a valid ASCII type/subtype value"
            );
        }
        return new NdefRecord(
                NdefTypeNameFormat.MIME_MEDIA,
                mediaType.getBytes(StandardCharsets.US_ASCII),
                identifier,
                payload
        );
    }

    public static NdefRecord external(
            String domain,
            String type,
            byte[] payload
    ) {
        return external(domain, type, payload, new byte[0]);
    }

    public static NdefRecord external(
            String domain,
            String type,
            byte[] payload,
            byte[] identifier
    ) {
        Objects.requireNonNull(domain, "domain is required");
        Objects.requireNonNull(type, "type is required");
        String externalType = domain + ":" + type;
        if (!isCanonicalExternalType(externalType)) {
            throw new IllegalArgumentException(
                    "NDEF external type must be a lowercase domain:type value"
            );
        }
        return new NdefRecord(
                NdefTypeNameFormat.EXTERNAL_TYPE,
                externalType.getBytes(StandardCharsets.US_ASCII),
                identifier,
                payload
        );
    }

    public NdefTypeNameFormat getTypeNameFormat() {
        return typeNameFormat;
    }

    public byte[] getType() {
        return type.clone();
    }

    public byte[] getIdentifier() {
        return identifier.clone();
    }

    public byte[] getPayload() {
        return payload.clone();
    }

    byte[] typeBytes() {
        return type;
    }

    byte[] identifierBytes() {
        return identifier;
    }

    byte[] payloadBytes() {
        return payload;
    }

    /**
     * Decodes this record as an NFC Forum Text record.
     *
     * @return the decoded value, or {@code null} when the record is not a
     *         well-formed Text record
     */
    public NdefText getDecodedText() {
        if (typeNameFormat != NdefTypeNameFormat.WELL_KNOWN
                || !Arrays.equals(type, TEXT_TYPE)) {
            return null;
        }
        return NdefPayloadDecoder.decodeText(payload);
    }

    /**
     * Decodes a well-known URI record or an absolute-URI record.
     *
     * @return the decoded URI, or {@code null} when this record has another
     *         type or contains malformed text
     */
    public String getDecodedUri() {
        if (typeNameFormat == NdefTypeNameFormat.WELL_KNOWN
                && Arrays.equals(type, URI_TYPE)) {
            return NdefUriCodec.decode(payload);
        }
        if (typeNameFormat == NdefTypeNameFormat.ABSOLUTE_URI) {
            return NdefPayloadDecoder.decodeUtf8(type);
        }
        return null;
    }

    /**
     * Returns a validated MIME media type for this record, if present.
     */
    public String getMediaType() {
        if (typeNameFormat != NdefTypeNameFormat.MIME_MEDIA) {
            return null;
        }
        String value = NdefPayloadDecoder.decodeAscii(type);
        return isValidMimeType(value) ? value : null;
    }

    /**
     * Returns a validated NFC Forum external type for this record, if present.
     */
    public String getExternalType() {
        if (typeNameFormat != NdefTypeNameFormat.EXTERNAL_TYPE) {
            return null;
        }
        String value = NdefPayloadDecoder.decodeAscii(type);
        return isValidExternalType(value) ? value : null;
    }

    @Override
    public boolean equals(Object other) {
        if (this == other) {
            return true;
        }
        if (!(other instanceof NdefRecord)) {
            return false;
        }
        NdefRecord that = (NdefRecord) other;
        return typeNameFormat == that.typeNameFormat
                && Arrays.equals(type, that.type)
                && Arrays.equals(identifier, that.identifier)
                && Arrays.equals(payload, that.payload);
    }

    @Override
    public int hashCode() {
        int result = Objects.hash(typeNameFormat);
        result = 31 * result + Arrays.hashCode(type);
        result = 31 * result + Arrays.hashCode(identifier);
        result = 31 * result + Arrays.hashCode(payload);
        return result;
    }

    private void validateShape() {
        switch (typeNameFormat) {
            case EMPTY:
                if (type.length != 0
                        || identifier.length != 0
                        || payload.length != 0) {
                    throw new IllegalArgumentException(
                            "An empty NDEF record cannot contain type, "
                                    + "identifier, or payload"
                    );
                }
                break;
            case WELL_KNOWN:
            case MIME_MEDIA:
            case ABSOLUTE_URI:
            case EXTERNAL_TYPE:
                if (type.length == 0) {
                    throw new IllegalArgumentException(
                            "NDEF record type is required for " + typeNameFormat
                    );
                }
                break;
            case UNKNOWN:
                if (type.length != 0) {
                    throw new IllegalArgumentException(
                            "An unknown NDEF record cannot declare a type"
                    );
                }
                break;
            default:
                throw new IllegalStateException(
                        "Unhandled NDEF type name format: " + typeNameFormat
                );
        }
    }

    static boolean isValidLanguageCode(String languageCode) {
        if (languageCode == null || languageCode.isEmpty()) {
            return false;
        }
        if (languageCode.length() > 63
                || languageCode.charAt(0) == '-'
                || languageCode.charAt(languageCode.length() - 1) == '-') {
            return false;
        }
        boolean previousWasHyphen = false;
        for (int index = 0; index < languageCode.length(); index++) {
            char value = languageCode.charAt(index);
            boolean hyphen = value == '-';
            boolean alphanumeric = value >= '0' && value <= '9'
                    || value >= 'A' && value <= 'Z'
                    || value >= 'a' && value <= 'z';
            if (!alphanumeric && !hyphen || hyphen && previousWasHyphen) {
                return false;
            }
            previousWasHyphen = hyphen;
        }
        return true;
    }

    static boolean isValidDecodedLanguageCode(String languageCode) {
        return languageCode != null
                && (languageCode.isEmpty()
                || isValidLanguageCode(languageCode));
    }

    static boolean isValidMimeType(String mediaType) {
        if (mediaType == null) {
            return false;
        }
        String[] parts = mediaType.split("/", -1);
        if (parts.length != 2) {
            return false;
        }
        for (String part : parts) {
            if (part.isEmpty()) {
                return false;
            }
            for (int index = 0; index < part.length(); index++) {
                if (!isMimeTokenCharacter(part.charAt(index))) {
                    return false;
                }
            }
        }
        return true;
    }

    static boolean isValidExternalType(String externalType) {
        if (externalType == null) {
            return false;
        }
        String[] parts = externalType.split(":", -1);
        if (parts.length != 2) {
            return false;
        }
        return isValidDomain(parts[0]) && isValidExternalTypeName(parts[1]);
    }

    private static boolean isCanonicalExternalType(String externalType) {
        return externalType != null
                && externalType.equals(externalType.toLowerCase(Locale.ROOT))
                && isValidExternalType(externalType);
    }

    private static boolean isValidDomain(String domain) {
        if (domain.isEmpty()) {
            return false;
        }
        String[] labels = domain.split("\\.", -1);
        for (String label : labels) {
            if (label.isEmpty() || label.length() > 63
                    || !isAsciiAlphanumeric(label.charAt(0))
                    || !isAsciiAlphanumeric(label.charAt(label.length() - 1))) {
                return false;
            }
            for (int index = 0; index < label.length(); index++) {
                char value = label.charAt(index);
                if (!isAsciiAlphanumeric(value) && value != '-') {
                    return false;
                }
            }
        }
        return true;
    }

    private static boolean isValidExternalTypeName(String typeName) {
        if (typeName.isEmpty()) {
            return false;
        }
        for (int index = 0; index < typeName.length(); index++) {
            char value = typeName.charAt(index);
            if (!isAsciiAlphanumeric(value)
                    && "$'()*+,-.;=@_".indexOf(value) < 0) {
                return false;
            }
        }
        return true;
    }

    private static boolean isAsciiAlphanumeric(char value) {
        return value >= '0' && value <= '9'
                || value >= 'A' && value <= 'Z'
                || value >= 'a' && value <= 'z';
    }

    private static boolean isMimeTokenCharacter(char value) {
        if (value >= '0' && value <= '9'
                || value >= 'A' && value <= 'Z'
                || value >= 'a' && value <= 'z') {
            return true;
        }
        return "!#$%&'*+-.^_`|~".indexOf(value) >= 0;
    }

    private static byte[] validatedLanguageCode(String languageCode) {
        if (!isValidLanguageCode(languageCode)) {
            throw new IllegalArgumentException(
                    "NDEF Text language code must be a 1 to 63 byte ASCII "
                            + "language tag"
            );
        }
        return languageCode.getBytes(StandardCharsets.US_ASCII);
    }

    private static byte[] copyRequired(byte[] source, String name) {
        Objects.requireNonNull(source, name + " is required");
        return source.clone();
    }
}
