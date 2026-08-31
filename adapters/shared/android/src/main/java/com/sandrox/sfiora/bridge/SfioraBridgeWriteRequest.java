package com.sandrox.sfiora.bridge;

import com.sandrox.sfiora.NdefMessage;
import com.sandrox.sfiora.NdefExternalType;
import com.sandrox.sfiora.NdefRecord;
import com.sandrox.sfiora.NdefTextEncoding;
import com.sandrox.sfiora.NfcWriteConfiguration;
import com.sandrox.sfiora.ui.NfcPresentationMessages;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.regex.Pattern;

/**
 * Strict Android-side parser for the frozen bridge NDEF write contract.
 */
public final class SfioraBridgeWriteRequest {
    private static final Set<String> MESSAGE_KEYS = setOf("records");
    private static final Set<String> MARKER_KEYS = setOf("domain", "type");
    private static final Set<String> WRITE_OPTION_KEYS = setOf(
            "timeoutMilliseconds",
            "messages"
    );
    private static final Set<String> TEXT_RECORD_KEYS = setOf(
            "kind",
            "text",
            "languageCode",
            "encoding",
            "identifierBase64"
    );
    private static final Set<String> URI_RECORD_KEYS = setOf(
            "kind",
            "uri",
            "identifierBase64"
    );
    private static final Set<String> MIME_RECORD_KEYS = setOf(
            "kind",
            "mediaType",
            "payloadBase64",
            "identifierBase64"
    );
    private static final Set<String> EXTERNAL_RECORD_KEYS = setOf(
            "kind",
            "domain",
            "type",
            "payloadBase64",
            "identifierBase64"
    );
    private static final Pattern STANDARD_BASE64 = Pattern.compile(
            "^(?:[A-Za-z0-9+/]{4})*"
                    + "(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$"
    );

    private final NdefMessage message;
    private final NfcWriteConfiguration writeConfiguration;
    private final NfcPresentationMessages.Write messages;

    private SfioraBridgeWriteRequest(
            NdefMessage message,
            NfcWriteConfiguration writeConfiguration,
            NfcPresentationMessages.Write messages
    ) {
        this.message = message;
        this.writeConfiguration = writeConfiguration;
        this.messages = messages;
    }

    public NdefMessage getMessage() {
        return message;
    }

    public NfcWriteConfiguration getWriteConfiguration() {
        return writeConfiguration;
    }

    public NfcPresentationMessages.Write getMessages() {
        return messages;
    }

    public static NdefExternalType parseExternalTypeMarker(
            Object rawMarker
    ) throws SfioraBridgeWriteRequestException {
        try {
            Map<?, ?> marker = objectMap(rawMarker, "marker", false);
            validateKeys(marker, MARKER_KEYS, "marker");
            return new NdefExternalType(
                    requiredString(
                            marker,
                            "domain",
                            "marker.domain",
                            false
                    ),
                    requiredString(marker, "type", "marker.type", false)
            );
        } catch (SfioraBridgeWriteRequestException error) {
            throw error;
        } catch (IllegalArgumentException error) {
            throw new SfioraBridgeWriteRequestException(
                    error.getMessage(),
                    error
            );
        }
    }

    public static SfioraBridgeWriteRequest parse(
            Object rawMessage,
            Object rawOptions
    ) throws SfioraBridgeWriteRequestException {
        try {
            return new SfioraBridgeWriteRequest(
                    parseMessage(rawMessage),
                    parseWriteConfiguration(rawOptions),
                    parseMessages(rawOptions)
            );
        } catch (SfioraBridgeWriteRequestException error) {
            throw error;
        } catch (IllegalArgumentException error) {
            throw new SfioraBridgeWriteRequestException(
                    error.getMessage(),
                    error
            );
        }
    }

    private static NdefMessage parseMessage(Object rawMessage)
            throws SfioraBridgeWriteRequestException {
        Map<?, ?> message = objectMap(rawMessage, "message", false);
        validateKeys(message, MESSAGE_KEYS, "message");
        Object rawRecords = required(message, "records", "message.records");
        if (!(rawRecords instanceof List<?>)) {
            throw invalid("message.records must be an array");
        }
        List<?> records = (List<?>) rawRecords;
        if (records.isEmpty()) {
            throw invalid("message.records must not be empty");
        }

        List<NdefRecord> parsedRecords = new ArrayList<>(records.size());
        for (int index = 0; index < records.size(); index++) {
            parsedRecords.add(parseRecord(
                    records.get(index),
                    "message.records[" + index + "]"
            ));
        }
        return new NdefMessage(parsedRecords);
    }

    private static NdefRecord parseRecord(Object rawRecord, String name)
            throws SfioraBridgeWriteRequestException {
        Map<?, ?> record = objectMap(rawRecord, name, false);
        String kind = requiredString(record, "kind", name + ".kind", false);
        switch (kind) {
            case "text":
                validateKeys(record, TEXT_RECORD_KEYS, name);
                return NdefRecord.text(
                        requiredString(record, "text", name + ".text", true),
                        requiredString(
                                record,
                                "languageCode",
                                name + ".languageCode",
                                false
                        ),
                        readTextEncoding(record, name),
                        readOptionalBase64(
                                record,
                                "identifierBase64",
                                name + ".identifierBase64"
                        )
                );
            case "uri":
                validateKeys(record, URI_RECORD_KEYS, name);
                return NdefRecord.uri(
                        requiredString(record, "uri", name + ".uri", false),
                        readOptionalBase64(
                                record,
                                "identifierBase64",
                                name + ".identifierBase64"
                        )
                );
            case "mime":
                validateKeys(record, MIME_RECORD_KEYS, name);
                return NdefRecord.mime(
                        requiredString(
                                record,
                                "mediaType",
                                name + ".mediaType",
                                false
                        ),
                        readRequiredBase64(
                                record,
                                "payloadBase64",
                                name + ".payloadBase64"
                        ),
                        readOptionalBase64(
                                record,
                                "identifierBase64",
                                name + ".identifierBase64"
                        )
                );
            case "external":
                validateKeys(record, EXTERNAL_RECORD_KEYS, name);
                return NdefRecord.external(
                        requiredString(
                                record,
                                "domain",
                                name + ".domain",
                                false
                        ),
                        requiredString(record, "type", name + ".type", false),
                        readRequiredBase64(
                                record,
                                "payloadBase64",
                                name + ".payloadBase64"
                        ),
                        readOptionalBase64(
                                record,
                                "identifierBase64",
                                name + ".identifierBase64"
                        )
                );
            default:
                throw invalid(
                        name + ".kind must be text, uri, mime, or external"
                );
        }
    }

    private static NdefTextEncoding readTextEncoding(
            Map<?, ?> record,
            String name
    ) throws SfioraBridgeWriteRequestException {
        if (!record.containsKey("encoding")) {
            return NdefTextEncoding.UTF_8;
        }
        String encoding = requiredString(
                record,
                "encoding",
                name + ".encoding",
                false
        );
        switch (encoding) {
            case "UTF-8":
                return NdefTextEncoding.UTF_8;
            case "UTF-16":
                return NdefTextEncoding.UTF_16;
            default:
                throw invalid(name + ".encoding must be UTF-8 or UTF-16");
        }
    }

    private static NfcWriteConfiguration parseWriteConfiguration(Object rawOptions)
            throws SfioraBridgeWriteRequestException {
        Map<?, ?> options = objectMap(rawOptions, "options", true);
        validateKeys(options, WRITE_OPTION_KEYS, "options");

        NfcWriteConfiguration.Builder builder = NfcWriteConfiguration.builder();
        if (options.containsKey("timeoutMilliseconds")) {
            builder.timeoutMillis(integer(
                    options.get("timeoutMilliseconds"),
                    "timeoutMilliseconds"
            ));
        }
        return builder.build();
    }

    private static NfcPresentationMessages.Write parseMessages(Object rawOptions)
            throws SfioraBridgeWriteRequestException {
        Map<?, ?> options = objectMap(rawOptions, "options", true);
        if (!options.containsKey("messages")) {
            return null;
        }
        return SfioraBridgePresentationMessages.parseWrite(options.get("messages"));
    }

    private static byte[] readRequiredBase64(
            Map<?, ?> values,
            String key,
            String name
    ) throws SfioraBridgeWriteRequestException {
        return decodeBase64(requiredString(values, key, name, true), name);
    }

    private static byte[] readOptionalBase64(
            Map<?, ?> values,
            String key,
            String name
    ) throws SfioraBridgeWriteRequestException {
        if (!values.containsKey(key)) {
            return new byte[0];
        }
        return decodeBase64(requiredString(values, key, name, true), name);
    }

    private static byte[] decodeBase64(String value, String name)
            throws SfioraBridgeWriteRequestException {
        if (!STANDARD_BASE64.matcher(value).matches()) {
            throw invalid(name + " must be canonical padded Base64");
        }
        if (value.isEmpty()) {
            return new byte[0];
        }

        int padding = value.endsWith("==") ? 2 : value.endsWith("=") ? 1 : 0;
        byte[] decoded = new byte[(value.length() / 4) * 3 - padding];
        int outputIndex = 0;
        for (int index = 0; index < value.length(); index += 4) {
            int first = base64Value(value.charAt(index));
            int second = base64Value(value.charAt(index + 1));
            char thirdCharacter = value.charAt(index + 2);
            char fourthCharacter = value.charAt(index + 3);
            int third = thirdCharacter == '=' ? 0 : base64Value(thirdCharacter);
            int fourth = fourthCharacter == '='
                    ? 0
                    : base64Value(fourthCharacter);

            decoded[outputIndex++] = (byte) ((first << 2) | (second >> 4));
            if (thirdCharacter != '=') {
                decoded[outputIndex++] = (byte) (
                        ((second & 0x0F) << 4) | (third >> 2)
                );
            } else if ((second & 0x0F) != 0) {
                throw invalid(name + " must be canonical padded Base64");
            }
            if (fourthCharacter != '=') {
                decoded[outputIndex++] = (byte) (
                        ((third & 0x03) << 6) | fourth
                );
            } else if (thirdCharacter != '=' && (third & 0x03) != 0) {
                throw invalid(name + " must be canonical padded Base64");
            }
        }
        return decoded;
    }

    private static int base64Value(char character)
            throws SfioraBridgeWriteRequestException {
        if (character >= 'A' && character <= 'Z') {
            return character - 'A';
        }
        if (character >= 'a' && character <= 'z') {
            return character - 'a' + 26;
        }
        if (character >= '0' && character <= '9') {
            return character - '0' + 52;
        }
        if (character == '+') {
            return 62;
        }
        if (character == '/') {
            return 63;
        }
        throw invalid("Base64 input contains an unsupported character");
    }

    private static Object required(
            Map<?, ?> values,
            String key,
            String name
    ) throws SfioraBridgeWriteRequestException {
        if (!values.containsKey(key) || values.get(key) == null) {
            throw invalid(name + " is required");
        }
        return values.get(key);
    }

    private static String requiredString(
            Map<?, ?> values,
            String key,
            String name,
            boolean allowEmpty
    ) throws SfioraBridgeWriteRequestException {
        Object value = required(values, key, name);
        if (!(value instanceof String)
                || !allowEmpty && ((String) value).isEmpty()) {
            throw invalid(
                    name + (allowEmpty
                            ? " must be a string"
                            : " must be a non-empty string")
            );
        }
        return (String) value;
    }

    private static Map<?, ?> objectMap(
            Object value,
            String name,
            boolean nullAsEmpty
    ) throws SfioraBridgeWriteRequestException {
        if (value == null && nullAsEmpty) {
            return Collections.emptyMap();
        }
        if (!(value instanceof Map<?, ?>)) {
            throw invalid(name + " must be an object");
        }
        return (Map<?, ?>) value;
    }

    private static void validateKeys(
            Map<?, ?> values,
            Set<String> allowedKeys,
            String name
    ) throws SfioraBridgeWriteRequestException {
        for (Object rawKey : values.keySet()) {
            if (!(rawKey instanceof String) || !allowedKeys.contains(rawKey)) {
                throw invalid(
                        name + " contains an unsupported field: " + rawKey
                );
            }
        }
    }

    private static long integer(Object value, String name)
            throws SfioraBridgeWriteRequestException {
        if (!(value instanceof Number)) {
            throw invalid(name + " must be an integer");
        }
        double number = ((Number) value).doubleValue();
        if (!Double.isFinite(number)
                || Math.rint(number) != number
                || number < Long.MIN_VALUE
                || number > Long.MAX_VALUE) {
            throw invalid(name + " must be an integer");
        }
        return (long) number;
    }

    private static SfioraBridgeWriteRequestException invalid(String message) {
        return new SfioraBridgeWriteRequestException(message);
    }

    private static Set<String> setOf(String... values) {
        return Collections.unmodifiableSet(new HashSet<>(Arrays.asList(values)));
    }
}
