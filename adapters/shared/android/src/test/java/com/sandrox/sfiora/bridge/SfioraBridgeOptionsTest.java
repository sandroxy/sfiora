package com.sandrox.sfiora.bridge;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertThrows;
import static org.junit.Assert.assertTrue;

import com.sandrox.sfiora.NfcReadConfiguration;
import com.sandrox.sfiora.NfcReadMode;
import com.sandrox.sfiora.ui.NfcScanPresentation;

import org.junit.Test;

import java.util.Arrays;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.Map;

public final class SfioraBridgeOptionsTest {
    @Test
    public void defaultsMatchFrozenContract() throws Exception {
        SfioraBridgeOptions options = SfioraBridgeOptions.parse(null);

        assertEquals(NfcReadMode.AUTOMATIC, options.getReadConfiguration().getMode());
        assertEquals(30_000L, options.getReadConfiguration().getTimeoutMillis());
        assertFalse(options.getReadConfiguration().isDeepReadEnabled());
        assertEquals(
                250,
                options.getReadConfiguration().getPresenceCheckDelayMillis()
        );
        assertEquals(NfcScanPresentation.MANAGED, options.getPresentation());
        assertEquals(null, options.getMessages());
    }

    @Test
    public void parsesOnlyCompletePresentationMessages() throws Exception {
        Map<String, Object> messages = scanMessages();
        SfioraBridgeOptions options = SfioraBridgeOptions.parse(singleton(
                "messages",
                messages
        ));

        assertEquals("scan instruction", options.getMessages().instruction);

        messages.remove("done");
        assertInvalid(singleton("messages", messages));
        messages.put("done", "done");
        messages.put("unexpected", "unexpected");
        assertInvalid(singleton("messages", messages));
        messages.remove("unexpected");
        messages.put("done", " \n");
        assertInvalid(singleton("messages", messages));
    }

    @Test
    public void parsesPlatformSpecificOptions() throws Exception {
        Map<String, Object> android = new LinkedHashMap<>();
        android.put("presentation", "none");
        android.put("deepReadEnabled", true);
        android.put("presenceCheckDelayMilliseconds", 400);

        Map<String, Object> ios = new LinkedHashMap<>();
        ios.put(
                "pollingTechnologies",
                Arrays.asList("iso14443", "iso18092")
        );

        Map<String, Object> rawOptions = new LinkedHashMap<>();
        rawOptions.put("mode", "discover");
        rawOptions.put("timeoutMilliseconds", 12_000);
        rawOptions.put("android", android);
        rawOptions.put("ios", ios);

        SfioraBridgeOptions options = SfioraBridgeOptions.parse(rawOptions);

        assertEquals(
                NfcReadMode.DISCOVER,
                options.getReadConfiguration().getMode()
        );
        assertEquals(12_000L, options.getReadConfiguration().getTimeoutMillis());
        assertTrue(options.getReadConfiguration().isDeepReadEnabled());
        assertEquals(
                400,
                options.getReadConfiguration().getPresenceCheckDelayMillis()
        );
        assertEquals(NfcScanPresentation.NONE, options.getPresentation());
    }

    @Test
    public void rejectsUnknownFieldsOnEitherPlatform() {
        assertInvalid(singleton("unexpected", true));
        assertInvalid(singleton(
                "android",
                singleton("unexpected", true)
        ));
        assertInvalid(singleton(
                "ios",
                singleton("unexpected", true)
        ));
    }

    @Test
    public void rejectsInvalidScalarTypesRangesAndEnums() {
        assertInvalid(singleton("timeoutMilliseconds", true));
        assertInvalid(singleton("timeoutMilliseconds", 1_500.5));
        assertInvalid(singleton("timeoutMilliseconds", 999));
        assertInvalid(singleton(
                "android",
                singleton("presenceCheckDelayMilliseconds", 49)
        ));
        assertInvalid(singleton(
                "android",
                singleton("presentation", " Managed ")
        ));
    }

    @Test
    public void rejectsInvalidPollingTechnologyCollections() {
        assertInvalid(singleton(
                "ios",
                singleton("pollingTechnologies", Collections.emptyList())
        ));
        assertInvalid(singleton(
                "ios",
                singleton(
                        "pollingTechnologies",
                        Arrays.asList("iso14443", "iso14443")
                )
        ));
        assertInvalid(singleton(
                "ios",
                singleton(
                        "pollingTechnologies",
                        Collections.singletonList("unsupported")
                )
        ));
    }

    private static void assertInvalid(Map<String, Object> options) {
        assertThrows(
                SfioraBridgeOptionsException.class,
                () -> SfioraBridgeOptions.parse(options)
        );
    }

    private static Map<String, Object> singleton(String key, Object value) {
        Map<String, Object> result = new LinkedHashMap<>();
        result.put(key, value);
        return result;
    }

    private static Map<String, Object> scanMessages() {
        Map<String, Object> messages = new LinkedHashMap<>();
        for (String key : Arrays.asList(
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
        )) {
            messages.put(key, key.equals("instruction") ? "scan instruction" : key);
        }
        return messages;
    }
}
