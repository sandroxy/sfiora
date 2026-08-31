package com.sandrox.sfiora.bridge;

import com.sandrox.sfiora.NfcReadConfiguration;
import com.sandrox.sfiora.NfcReadMode;
import com.sandrox.sfiora.ui.NfcScanPresentation;
import com.sandrox.sfiora.ui.NfcPresentationMessages;

import java.util.Arrays;
import java.util.Collections;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * Strict Android-side parser for the frozen bridge scan contract.
 */
public final class SfioraBridgeOptions {
    private static final Set<String> ROOT_KEYS = setOf(
            "mode",
            "timeoutMilliseconds",
            "android",
            "ios",
            "messages"
    );
    private static final Set<String> ANDROID_KEYS = setOf(
            "presentation",
            "deepReadEnabled",
            "presenceCheckDelayMilliseconds"
    );
    private static final Set<String> IOS_KEYS = setOf("pollingTechnologies");
    private static final Set<String> IOS_POLLING_TECHNOLOGIES = setOf(
            "iso14443",
            "iso15693",
            "iso18092"
    );

    private final NfcReadConfiguration readConfiguration;
    private final NfcScanPresentation presentation;
    private final NfcPresentationMessages.Scan messages;

    private SfioraBridgeOptions(
            NfcReadConfiguration readConfiguration,
            NfcScanPresentation presentation,
            NfcPresentationMessages.Scan messages
    ) {
        this.readConfiguration = readConfiguration;
        this.presentation = presentation;
        this.messages = messages;
    }

    public NfcReadConfiguration getReadConfiguration() {
        return readConfiguration;
    }

    public NfcScanPresentation getPresentation() {
        return presentation;
    }

    public NfcPresentationMessages.Scan getMessages() {
        return messages;
    }

    public static SfioraBridgeOptions parse(Object rawOptions)
            throws SfioraBridgeOptionsException {
        try {
            return parseValidated(rawOptions);
        } catch (IllegalArgumentException error) {
            throw new SfioraBridgeOptionsException(error.getMessage());
        }
    }

    private static SfioraBridgeOptions parseValidated(Object rawOptions)
            throws SfioraBridgeOptionsException {
        Map<?, ?> options = objectMap(rawOptions, "options", true);
        validateKeys(options, ROOT_KEYS, "options");

        NfcReadConfiguration.Builder configuration = NfcReadConfiguration.builder();
        if (options.containsKey("mode")) {
            configuration.mode(readMode(options.get("mode")));
        }
        if (options.containsKey("timeoutMilliseconds")) {
            configuration.timeoutMillis(integer(
                    options.get("timeoutMilliseconds"),
                    "timeoutMilliseconds"
            ));
        }

        NfcScanPresentation presentation = NfcScanPresentation.MANAGED;
        if (options.containsKey("android")) {
            Map<?, ?> androidOptions = objectMap(
                    options.get("android"),
                    "android",
                    false
            );
            validateKeys(androidOptions, ANDROID_KEYS, "android");
            if (androidOptions.containsKey("presentation")) {
                String value = string(
                        androidOptions.get("presentation"),
                        "android.presentation"
                );
                try {
                    presentation = NfcScanPresentation.fromBridgeValue(value);
                } catch (IllegalArgumentException error) {
                    throw new SfioraBridgeOptionsException(error.getMessage());
                }
            }
            if (androidOptions.containsKey("deepReadEnabled")) {
                configuration.deepReadEnabled(bool(
                        androidOptions.get("deepReadEnabled"),
                        "android.deepReadEnabled"
                ));
            }
            if (androidOptions.containsKey("presenceCheckDelayMilliseconds")) {
                long delay = integer(
                        androidOptions.get("presenceCheckDelayMilliseconds"),
                        "android.presenceCheckDelayMilliseconds"
                );
                if (delay < Integer.MIN_VALUE || delay > Integer.MAX_VALUE) {
                    throw new SfioraBridgeOptionsException(
                            "android.presenceCheckDelayMilliseconds is outside the integer range"
                    );
                }
                configuration.presenceCheckDelayMillis((int) delay);
            }
        }

        if (options.containsKey("ios")) {
            validateIosOptions(options.get("ios"));
        }

        try {
            NfcPresentationMessages.Scan messages = options.containsKey("messages")
                    ? SfioraBridgePresentationMessages.parseScan(options.get("messages"))
                    : null;
            return new SfioraBridgeOptions(
                    configuration.build(),
                    presentation,
                    messages
            );
        } catch (IllegalArgumentException error) {
            throw new SfioraBridgeOptionsException(error.getMessage());
        }
    }

    private static NfcReadMode readMode(Object value)
            throws SfioraBridgeOptionsException {
        String mode = string(value, "mode");
        switch (mode) {
            case "automatic":
                return NfcReadMode.AUTOMATIC;
            case "ndef":
                return NfcReadMode.NDEF;
            case "discover":
                return NfcReadMode.DISCOVER;
            default:
                throw new SfioraBridgeOptionsException(
                        "mode must be automatic, ndef, or discover"
                );
        }
    }

    private static void validateIosOptions(Object value)
            throws SfioraBridgeOptionsException {
        Map<?, ?> iosOptions = objectMap(value, "ios", false);
        validateKeys(iosOptions, IOS_KEYS, "ios");
        if (!iosOptions.containsKey("pollingTechnologies")) {
            return;
        }
        Object technologiesValue = iosOptions.get("pollingTechnologies");
        if (!(technologiesValue instanceof List<?>)) {
            throw new SfioraBridgeOptionsException(
                    "ios.pollingTechnologies must be an array"
            );
        }
        List<?> technologies = (List<?>) technologiesValue;
        if (technologies.isEmpty()) {
            throw new SfioraBridgeOptionsException(
                    "ios.pollingTechnologies must not be empty"
            );
        }
        Set<String> unique = new HashSet<>();
        for (int index = 0; index < technologies.size(); index++) {
            String technology = string(
                    technologies.get(index),
                    "ios.pollingTechnologies[" + index + "]"
            );
            if (!IOS_POLLING_TECHNOLOGIES.contains(technology)) {
                throw new SfioraBridgeOptionsException(
                        "ios.pollingTechnologies contains an unsupported value"
                );
            }
            if (!unique.add(technology)) {
                throw new SfioraBridgeOptionsException(
                        "ios.pollingTechnologies must not contain duplicates"
                );
            }
        }
    }

    private static Map<?, ?> objectMap(
            Object value,
            String name,
            boolean nullAsEmpty
    ) throws SfioraBridgeOptionsException {
        if (value == null && nullAsEmpty) {
            return Collections.emptyMap();
        }
        if (!(value instanceof Map<?, ?>)) {
            throw new SfioraBridgeOptionsException(name + " must be an object");
        }
        return (Map<?, ?>) value;
    }

    private static void validateKeys(
            Map<?, ?> values,
            Set<String> allowedKeys,
            String name
    ) throws SfioraBridgeOptionsException {
        for (Object rawKey : values.keySet()) {
            if (!(rawKey instanceof String) || !allowedKeys.contains(rawKey)) {
                throw new SfioraBridgeOptionsException(
                        name + " contains an unsupported field: " + rawKey
                );
            }
        }
    }

    private static String string(Object value, String name)
            throws SfioraBridgeOptionsException {
        if (!(value instanceof String) || ((String) value).isEmpty()) {
            throw new SfioraBridgeOptionsException(name + " must be a non-empty string");
        }
        return (String) value;
    }

    private static boolean bool(Object value, String name)
            throws SfioraBridgeOptionsException {
        if (!(value instanceof Boolean)) {
            throw new SfioraBridgeOptionsException(name + " must be a boolean");
        }
        return (Boolean) value;
    }

    private static long integer(Object value, String name)
            throws SfioraBridgeOptionsException {
        if (!(value instanceof Number)) {
            throw new SfioraBridgeOptionsException(name + " must be an integer");
        }
        double number = ((Number) value).doubleValue();
        if (!Double.isFinite(number)
                || Math.rint(number) != number
                || number < Long.MIN_VALUE
                || number > Long.MAX_VALUE) {
            throw new SfioraBridgeOptionsException(name + " must be an integer");
        }
        return (long) number;
    }

    private static Set<String> setOf(String... values) {
        return Collections.unmodifiableSet(new HashSet<>(Arrays.asList(values)));
    }
}
