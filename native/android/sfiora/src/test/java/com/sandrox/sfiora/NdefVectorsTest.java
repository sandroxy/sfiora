package com.sandrox.sfiora;

import static org.junit.Assert.assertArrayEquals;
import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import com.google.gson.Gson;

import org.junit.Test;

import java.io.InputStream;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

public final class NdefVectorsTest {
    private static final Fixture FIXTURE = loadFixture();

    @Test
    public void sharedRecordVectorsMatchPublicModel() {
        assertEquals(1, FIXTURE.fixtureVersion);
        assertTrue(FIXTURE.records.size() >= 5);

        for (RecordVector vector : FIXTURE.records) {
            NdefRecord record = createRecord(vector);
            assertEquals(
                    vector.name,
                    vector.expected.typeNameFormat,
                    record.getTypeNameFormat().getValue()
            );
            assertArrayEquals(
                    vector.name,
                    decodeHex(vector.expected.typeHex),
                    record.getType()
            );
            assertArrayEquals(
                    vector.name,
                    decodeHex(vector.identifierHex),
                    record.getIdentifier()
            );
            assertArrayEquals(
                    vector.name,
                    decodeHex(vector.expected.payloadHex),
                    record.getPayload()
            );

            NdefMessage message = new NdefMessage(List.of(record));
            assertArrayEquals(
                    vector.name,
                    decodeHex(vector.expected.messageHex),
                    message.getSerializedData()
            );
            assertDecodedValues(vector, record);
        }
    }

    @Test
    public void sharedMultiRecordVectorsSetMessageBoundaryFlags() {
        Map<String, NdefRecord> recordsByName = new LinkedHashMap<>();
        for (RecordVector vector : FIXTURE.records) {
            recordsByName.put(vector.name, createRecord(vector));
        }

        for (MessageVector vector : FIXTURE.messages) {
            List<NdefRecord> records = new ArrayList<>();
            for (String name : vector.recordNames) {
                NdefRecord record = recordsByName.get(name);
                assertNotNull(name, record);
                records.add(record);
            }
            NdefMessage message = new NdefMessage(records);
            assertArrayEquals(
                    vector.name,
                    decodeHex(vector.messageHex),
                    message.getSerializedData()
            );
        }
    }

    @Test
    public void sharedBoundaryVectorsSelectShortAndLongPayloadLengths() {
        for (BoundaryVector vector : FIXTURE.encodingBoundaries) {
            byte[] payload = new byte[vector.payloadLength];
            Arrays.fill(payload, decodeHex(vector.payloadByteHex)[0]);
            NdefRecord record = new NdefRecord(
                    typeNameFormat(vector.typeNameFormat),
                    decodeHex(vector.typeHex),
                    payload
            );
            NdefMessage message = new NdefMessage(List.of(record));
            assertEquals(vector.name, vector.messageByteCount, message.getByteCount());
            assertArrayEquals(
                    vector.name,
                    decodeHex(vector.messagePrefixHex),
                    Arrays.copyOf(
                            message.getSerializedData(),
                            decodeHex(vector.messagePrefixHex).length
                    )
            );
        }
    }

    private static NdefRecord createRecord(RecordVector vector) {
        byte[] identifier = decodeHex(vector.identifierHex);
        switch (vector.kind) {
            case "text":
                return NdefRecord.text(
                        vector.text,
                        vector.languageCode,
                        "UTF-16".equals(vector.encoding)
                                ? NdefTextEncoding.UTF_16
                                : NdefTextEncoding.UTF_8,
                        identifier
                );
            case "uri":
                return NdefRecord.uri(vector.uri, identifier);
            case "mime":
                return NdefRecord.mime(
                        vector.mediaType,
                        decodeHex(vector.payloadHex),
                        identifier
                );
            case "external":
                return NdefRecord.external(
                        vector.domain,
                        vector.externalTypeName,
                        decodeHex(vector.payloadHex),
                        identifier
                );
            default:
                throw new AssertionError("Unknown fixture kind: " + vector.kind);
        }
    }

    private static void assertDecodedValues(
            RecordVector vector,
            NdefRecord record
    ) {
        ExpectedRecord expected = vector.expected;
        if (expected.decodedText != null) {
            NdefText decoded = record.getDecodedText();
            assertNotNull(vector.name, decoded);
            assertEquals(expected.decodedText, decoded.getText());
            assertEquals(
                    expected.decodedLanguageCode,
                    decoded.getLanguageCode()
            );
            assertEquals(
                    expected.decodedTextEncoding,
                    decoded.getEncoding().getStandardName()
            );
        } else {
            assertNull(record.getDecodedText());
        }
        assertEquals(expected.decodedUri, record.getDecodedUri());
        assertEquals(expected.mediaType, record.getMediaType());
        assertEquals(expected.externalType, record.getExternalType());
    }

    private static Fixture loadFixture() {
        InputStream stream = NdefVectorsTest.class.getClassLoader()
                .getResourceAsStream("ndef-vectors.json");
        if (stream == null) {
            throw new AssertionError("Shared NDEF fixture is missing");
        }
        try (InputStreamReader reader = new InputStreamReader(
                stream,
                StandardCharsets.UTF_8
        )) {
            return new Gson().fromJson(reader, Fixture.class);
        } catch (Exception error) {
            throw new AssertionError("Unable to load shared NDEF fixture", error);
        }
    }

    private static byte[] decodeHex(String value) {
        if (value == null || (value.length() & 1) != 0) {
            throw new AssertionError("Fixture HEX must contain complete bytes");
        }
        byte[] result = new byte[value.length() / 2];
        for (int index = 0; index < value.length(); index += 2) {
            int high = Character.digit(value.charAt(index), 16);
            int low = Character.digit(value.charAt(index + 1), 16);
            if (high < 0 || low < 0) {
                throw new AssertionError("Fixture contains invalid HEX");
            }
            result[index / 2] = (byte) ((high << 4) | low);
        }
        return result;
    }

    private static NdefTypeNameFormat typeNameFormat(int value) {
        for (NdefTypeNameFormat candidate : NdefTypeNameFormat.values()) {
            if (candidate.getValue() == value) {
                return candidate;
            }
        }
        throw new AssertionError("Fixture contains an unsupported TNF: " + value);
    }

    private static final class Fixture {
        int fixtureVersion;
        List<RecordVector> records;
        List<MessageVector> messages;
        List<BoundaryVector> encodingBoundaries;
    }

    private static final class RecordVector {
        String name;
        String kind;
        String text;
        String languageCode;
        String encoding;
        String uri;
        String mediaType;
        String domain;
        String externalTypeName;
        String payloadHex;
        String identifierHex;
        ExpectedRecord expected;
    }

    private static final class ExpectedRecord {
        int typeNameFormat;
        String typeHex;
        String payloadHex;
        String messageHex;
        String decodedText;
        String decodedLanguageCode;
        String decodedTextEncoding;
        String decodedUri;
        String mediaType;
        String externalType;
    }

    private static final class MessageVector {
        String name;
        List<String> recordNames;
        String messageHex;
    }

    private static final class BoundaryVector {
        String name;
        int typeNameFormat;
        String typeHex;
        String payloadByteHex;
        int payloadLength;
        String messagePrefixHex;
        int messageByteCount;
    }
}
