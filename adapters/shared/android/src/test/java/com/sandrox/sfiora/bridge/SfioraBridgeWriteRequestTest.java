package com.sandrox.sfiora.bridge;

import static org.junit.Assert.assertArrayEquals;
import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertThrows;

import com.google.gson.Gson;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import com.sandrox.sfiora.NdefExternalType;

import org.junit.Test;

import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

public final class SfioraBridgeWriteRequestTest {
    private static final Gson GSON = new Gson();

    @Test
    public void parsesSharedWriteFixtureWithoutChangingEncodedBytes()
            throws Exception {
        JsonObject fixture = sharedFixture();
        Object message = GSON.fromJson(fixture.get("message"), Object.class);
        Object options = GSON.fromJson(fixture.get("options"), Object.class);

        SfioraBridgeWriteRequest request = SfioraBridgeWriteRequest.parse(
                message,
                options
        );

        JsonObject expected = fixture.getAsJsonObject("expected");
        assertEquals(
                expected.get("recordCount").getAsInt(),
                request.getMessage().getRecords().size()
        );
        assertEquals(
                expected.get("byteCount").getAsInt(),
                request.getMessage().getByteCount()
        );
        assertArrayEquals(
                fromHex(expected.get("messageHex").getAsString()),
                request.getMessage().getSerializedData()
        );
        assertEquals(
                12_000L,
                request.getWriteConfiguration().getTimeoutMillis()
        );
    }

    @Test
    public void appliesFrozenDefaultsAndAllowsEmptyText() throws Exception {
        Map<String, Object> text = new LinkedHashMap<>();
        text.put("kind", "text");
        text.put("text", "");
        text.put("languageCode", "en");

        SfioraBridgeWriteRequest request = SfioraBridgeWriteRequest.parse(
                messageWith(text),
                null
        );

        assertEquals(1, request.getMessage().getRecords().size());
        assertEquals(
                30_000L,
                request.getWriteConfiguration().getTimeoutMillis()
        );
    }

    @Test
    public void parsesStrictExternalTypeInitializationMarker() throws Exception {
        NdefExternalType marker =
                SfioraBridgeWriteRequest.parseExternalTypeMarker(
                        singleton("domain", "io.sfiora", "type", "credential")
                );
        assertEquals("io.sfiora:credential", marker.getValue());

        assertThrows(
                SfioraBridgeWriteRequestException.class,
                () -> SfioraBridgeWriteRequest.parseExternalTypeMarker(
                        singleton("domain", "Io.Sfiora", "type", "credential")
                )
        );
        assertThrows(
                SfioraBridgeWriteRequestException.class,
                () -> SfioraBridgeWriteRequest.parseExternalTypeMarker(
                        singleton(
                                "domain",
                                "io.sfiora",
                                "type",
                                "credential",
                                "extra",
                                true
                        )
                )
        );
    }

    @Test
    public void rejectsUnknownFieldsInvalidKindsAndInvalidTimeouts() {
        Map<String, Object> message = messageWith(uriRecord());
        message.put("unexpected", true);
        assertInvalid(message, null);

        Map<String, Object> uri = uriRecord();
        uri.put("unexpected", true);
        assertInvalid(messageWith(uri), null);

        Map<String, Object> unknown = new LinkedHashMap<>();
        unknown.put("kind", "raw");
        assertInvalid(messageWith(unknown), null);

        assertInvalid(
                messageWith(uriRecord()),
                singleton("timeoutMilliseconds", true)
        );
        assertInvalid(
                messageWith(uriRecord()),
                singleton("timeoutMilliseconds", 999)
        );
        assertInvalid(
                messageWith(uriRecord()),
                singleton("unexpected", true)
        );
    }

    @Test
    public void rejectsMissingPaddingAndNonCanonicalBase64() {
        assertInvalid(
                messageWith(mimeRecord("AQI")),
                Collections.emptyMap()
        );
        assertInvalid(
                messageWith(mimeRecord("AB==")),
                Collections.emptyMap()
        );
    }

    @Test
    public void parsesOnlyCompletePresentationMessages() throws Exception {
        Map<String, Object> messages = writeMessages();
        SfioraBridgeWriteRequest request = SfioraBridgeWriteRequest.parse(
                messageWith(uriRecord()),
                singleton("messages", messages)
        );

        assertEquals("writing", request.getMessages().writing);

        messages.remove("verifying");
        assertInvalid(messageWith(uriRecord()), singleton("messages", messages));
        messages.put("verifying", "verifying");
        messages.put("unexpected", "unexpected");
        assertInvalid(messageWith(uriRecord()), singleton("messages", messages));
        messages.remove("unexpected");
        messages.put("verifying", " \n");
        assertInvalid(messageWith(uriRecord()), singleton("messages", messages));
    }

    private static JsonObject sharedFixture() {
        ClassLoader classLoader =
                SfioraBridgeWriteRequestTest.class.getClassLoader();
        try (InputStream stream = classLoader.getResourceAsStream(
                "bridge-contract.json"
        )) {
            if (stream == null) {
                throw new IllegalStateException(
                        "Missing shared NFC contract fixture"
                );
            }
            try (InputStreamReader reader = new InputStreamReader(
                    stream,
                    StandardCharsets.UTF_8
            )) {
                return JsonParser.parseReader(reader)
                        .getAsJsonObject()
                        .getAsJsonObject("bridgeWriteRequest");
            }
        } catch (IOException error) {
            throw new IllegalStateException(
                    "Unable to read shared NFC contract fixture",
                    error
            );
        }
    }

    private static void assertInvalid(Object message, Object options) {
        assertThrows(
                SfioraBridgeWriteRequestException.class,
                () -> SfioraBridgeWriteRequest.parse(message, options)
        );
    }

    private static Map<String, Object> messageWith(
            Map<String, Object> record
    ) {
        List<Map<String, Object>> records = new ArrayList<>();
        records.add(record);
        return singleton("records", records);
    }

    private static Map<String, Object> uriRecord() {
        Map<String, Object> record = new LinkedHashMap<>();
        record.put("kind", "uri");
        record.put("uri", "https://example.com");
        return record;
    }

    private static Map<String, Object> mimeRecord(String payloadBase64) {
        Map<String, Object> record = new LinkedHashMap<>();
        record.put("kind", "mime");
        record.put("mediaType", "application/octet-stream");
        record.put("payloadBase64", payloadBase64);
        return record;
    }

    private static Map<String, Object> singleton(String key, Object value) {
        Map<String, Object> result = new LinkedHashMap<>();
        result.put(key, value);
        return result;
    }

    private static Map<String, Object> singleton(
            Object... keysAndValues
    ) {
        Map<String, Object> result = new LinkedHashMap<>();
        for (int index = 0; index < keysAndValues.length; index += 2) {
            result.put(
                    (String) keysAndValues[index],
                    keysAndValues[index + 1]
            );
        }
        return result;
    }

    private static byte[] fromHex(String value) {
        byte[] result = new byte[value.length() / 2];
        for (int index = 0; index < value.length(); index += 2) {
            result[index / 2] = (byte) Integer.parseInt(
                    value.substring(index, index + 2),
                    16
            );
        }
        return result;
    }

    private static Map<String, Object> writeMessages() {
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
                "checking",
                "writing",
                "verifying",
                "tagLost",
                "tagReadOnly",
                "capacityExceeded",
                "unsupportedTag",
                "writeFailed",
                "verificationFailed"
        )) {
            messages.put(key, key);
        }
        return messages;
    }
}
