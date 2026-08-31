package com.sandrox.sfiora.bridge;

import com.sandrox.sfiora.ui.NfcPresentationMessages;

import java.util.Arrays;
import java.util.Collections;
import java.util.HashSet;
import java.util.Map;
import java.util.Set;

final class SfioraBridgePresentationMessages {
    private static final Set<String> SCAN_KEYS = setOf(
            "title",
            "instruction",
            "cancel",
            "done",
            "success",
            "failureTitle",
            "timeout",
            "nfcDisabled",
            "nfcUnsupported",
            "multipleTags",
            "reading",
            "tagLost",
            "unsupportedTag",
            "readFailed"
    );
    private static final Set<String> WRITE_KEYS = setOf(
            "title",
            "instruction",
            "cancel",
            "done",
            "success",
            "failureTitle",
            "timeout",
            "nfcDisabled",
            "nfcUnsupported",
            "multipleTags",
            "checking",
            "writing",
            "verifying",
            "tagLost",
            "tagReadOnly",
            "capacityExceeded",
            "unsupportedTag",
            "writeFailed",
            "verificationFailed"
    );

    private SfioraBridgePresentationMessages() {}

    static NfcPresentationMessages.Scan parseScan(Object raw)
            throws SfioraBridgeOptionsException {
        Map<?, ?> messages = objectMap(raw, "messages");
        validateExactKeys(messages, SCAN_KEYS, "messages");
        return new NfcPresentationMessages.Scan(
                text(messages, "title"),
                text(messages, "instruction"),
                text(messages, "cancel"),
                text(messages, "done"),
                text(messages, "success"),
                text(messages, "failureTitle"),
                text(messages, "timeout"),
                text(messages, "nfcDisabled"),
                text(messages, "nfcUnsupported"),
                text(messages, "multipleTags"),
                text(messages, "reading"),
                text(messages, "tagLost"),
                text(messages, "unsupportedTag"),
                text(messages, "readFailed")
        );
    }

    static NfcPresentationMessages.Write parseWrite(Object raw)
            throws SfioraBridgeWriteRequestException {
        try {
            Map<?, ?> messages = objectMap(raw, "messages");
            validateExactKeys(messages, WRITE_KEYS, "messages");
            return new NfcPresentationMessages.Write(
                    text(messages, "title"),
                    text(messages, "instruction"),
                    text(messages, "cancel"),
                    text(messages, "done"),
                    text(messages, "success"),
                    text(messages, "failureTitle"),
                    text(messages, "timeout"),
                    text(messages, "nfcDisabled"),
                    text(messages, "nfcUnsupported"),
                    text(messages, "multipleTags"),
                    text(messages, "checking"),
                    text(messages, "writing"),
                    text(messages, "verifying"),
                    text(messages, "tagLost"),
                    text(messages, "tagReadOnly"),
                    text(messages, "capacityExceeded"),
                    text(messages, "unsupportedTag"),
                    text(messages, "writeFailed"),
                    text(messages, "verificationFailed")
            );
        } catch (SfioraBridgeOptionsException error) {
            throw new SfioraBridgeWriteRequestException(error.getMessage(), error);
        }
    }

    private static Map<?, ?> objectMap(Object value, String name)
            throws SfioraBridgeOptionsException {
        if (!(value instanceof Map<?, ?>)) {
            throw new SfioraBridgeOptionsException(name + " must be an object");
        }
        return (Map<?, ?>) value;
    }

    private static void validateExactKeys(
            Map<?, ?> values,
            Set<String> expectedKeys,
            String name
    ) throws SfioraBridgeOptionsException {
        for (String key : expectedKeys) {
            if (!values.containsKey(key)) {
                throw new SfioraBridgeOptionsException(name + "." + key + " is required");
            }
        }
        for (Object rawKey : values.keySet()) {
            if (!(rawKey instanceof String) || !expectedKeys.contains(rawKey)) {
                throw new SfioraBridgeOptionsException(
                        name + " contains an unsupported field: " + rawKey
                );
            }
        }
    }

    private static String text(Map<?, ?> values, String key)
            throws SfioraBridgeOptionsException {
        Object value = values.get(key);
        if (!(value instanceof String) || ((String) value).trim().isEmpty()) {
            throw new SfioraBridgeOptionsException(
                    "messages." + key + " must be a non-empty string"
            );
        }
        return (String) value;
    }

    private static Set<String> setOf(String... values) {
        return Collections.unmodifiableSet(new HashSet<>(Arrays.asList(values)));
    }
}
