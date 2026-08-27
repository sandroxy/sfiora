package com.sandrox.sfiora;

import android.net.Uri;
import android.nfc.NdefRecord;
import android.nfc.Tag;
import android.nfc.tech.IsoDep;
import android.nfc.tech.MifareClassic;
import android.nfc.tech.MifareUltralight;
import android.nfc.tech.Ndef;
import android.nfc.tech.NdefFormatable;
import android.nfc.tech.NfcA;
import android.nfc.tech.NfcB;
import android.nfc.tech.NfcBarcode;
import android.nfc.tech.NfcF;
import android.nfc.tech.NfcV;

import com.sandrox.sfiora.internal.ByteEncoding;
import com.sandrox.sfiora.internal.NdefPayloadCodec;
import com.sandrox.sfiora.internal.ReadOnlyTagProbe;

import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;

/** Builds typed snapshots without discarding bridge-visible native metadata. */
final class AndroidTagSnapshotFactory {
    static final class NdefObservation {
        private final NfcNdefStatus status;
        private final NfcNdefStatus accessStatus;
        private final Integer capacityBytes;
        private final Boolean writable;
        private final Boolean canMakeReadOnly;
        private final String type;
        private final android.nfc.NdefMessage platformMessage;
        private final NdefMessage message;
        private final Throwable readError;
        private final String warning;

        private NdefObservation(
                NfcNdefStatus status,
                NfcNdefStatus accessStatus,
                Integer capacityBytes,
                Boolean writable,
                Boolean canMakeReadOnly,
                String type,
                android.nfc.NdefMessage platformMessage,
                NdefMessage message,
                Throwable readError,
                String warning
        ) {
            this.status = status;
            this.accessStatus = accessStatus;
            this.capacityBytes = capacityBytes;
            this.writable = writable;
            this.canMakeReadOnly = canMakeReadOnly;
            this.type = type;
            this.platformMessage = platformMessage;
            this.message = message;
            this.readError = readError;
            this.warning = warning;
        }

        static NdefObservation notChecked() {
            return new NdefObservation(
                    NfcNdefStatus.NOT_CHECKED,
                    null,
                    null,
                    null,
                    null,
                    null,
                    null,
                    null,
                    null,
                    null
            );
        }

        static NdefObservation unsupported() {
            return new NdefObservation(
                    NfcNdefStatus.NOT_SUPPORTED,
                    null,
                    null,
                    null,
                    null,
                    null,
                    null,
                    null,
                    null,
                    null
            );
        }

        static NdefObservation message(
                NfcNdefStatus status,
                int capacityBytes,
                boolean writable,
                boolean canMakeReadOnly,
                String type,
                android.nfc.NdefMessage platformMessage,
                NdefMessage message,
                String warning
        ) {
            return new NdefObservation(
                    status,
                    null,
                    capacityBytes,
                    writable,
                    canMakeReadOnly,
                    type,
                    platformMessage,
                    message,
                    null,
                    warning
            );
        }

        static NdefObservation readError(
                NfcNdefStatus accessStatus,
                Integer capacityBytes,
                Boolean writable,
                Boolean canMakeReadOnly,
                String type,
                Throwable error,
                String warning
        ) {
            return new NdefObservation(
                    NfcNdefStatus.READ_ERROR,
                    accessStatus,
                    capacityBytes,
                    writable,
                    canMakeReadOnly,
                    type,
                    null,
                    null,
                    error,
                    warning
            );
        }
    }

    private AndroidTagSnapshotFactory() {
    }

    static NfcTagSnapshot create(
            Tag tag,
            NdefObservation observation,
            NfcReadConfiguration configuration
    ) {
        long discoveredAt = System.currentTimeMillis();
        List<String> warnings = new ArrayList<>();
        String[] nativeNames = safeNativeTechnologies(tag);
        List<NfcTechnology> technologies = technologies(nativeNames);

        Map<String, Object> androidDetails = inspectTechnologyDetails(tag, warnings);
        Map<String, Object> platformDetails = new LinkedHashMap<>();
        platformDetails.put("android", androidDetails);

        if (observation.warning != null) {
            warnings.add(observation.warning);
        }

        Map<String, Object> root = new LinkedHashMap<>();
        root.put("schemaVersion", NfcTagSnapshot.SCHEMA_VERSION);
        root.put("platform", "android");
        root.put("discoveredAtEpochMs", discoveredAt);
        root.put("id", bytesValue(tag.getId()));
        root.put("nativeTechnologies", Arrays.asList(nativeNames));
        root.put("technologies", technologyValues(technologies));
        root.put("platformDetails", platformDetails);

        Map<String, Object> ndef = ndefValue(observation, warnings);
        if (ndef != null) {
            root.put("ndef", ndef);
        }

        Map<String, Object> probes = null;
        if (configuration != null && configuration.isDeepReadEnabled()) {
            probes = ReadOnlyTagProbe.inspect(tag, warnings);
            root.put("readOnlyProbes", probes);
        }
        root.put("warnings", warnings);

        return NfcTagSnapshot.builder()
                .identifier(tag.getId())
                .technologies(technologies)
                .nativeTechnologies(Arrays.asList(nativeNames))
                .ndefStatus(observation.status)
                .ndefAccessStatus(observation.accessStatus)
                .ndefCapacityBytes(observation.capacityBytes)
                .ndefWritable(observation.writable)
                .ndefCanMakeReadOnly(observation.canMakeReadOnly)
                .ndefType(observation.type)
                .ndefMessage(observation.message)
                .warnings(warnings)
                .platformDetails(platformDetails)
                .ndefReadError(
                        observation.readError == null
                                ? null
                                : errorValue(observation.readError)
                )
                .readOnlyProbes(probes)
                .discoveredAtEpochMillis(discoveredAt)
                .values(root)
                .build();
    }

    private static Map<String, Object> ndefValue(
            NdefObservation observation,
            List<String> warnings
    ) {
        if (observation.status == NfcNdefStatus.NOT_CHECKED) {
            return null;
        }

        Map<String, Object> result = new LinkedHashMap<>();
        result.put("status", bridgeStatus(observation.status));
        if (observation.accessStatus != null) {
            result.put("accessStatus", bridgeStatus(observation.accessStatus));
        }
        if (observation.writable != null) {
            result.put("writable", observation.writable);
        }
        if (observation.canMakeReadOnly != null) {
            result.put("canMakeReadOnly", observation.canMakeReadOnly);
        }
        if (observation.capacityBytes != null) {
            result.put("maxSize", observation.capacityBytes);
        }
        if (observation.type != null) {
            result.put("type", observation.type);
        }
        if (observation.readError != null) {
            result.put("readError", errorValue(observation.readError));
        }
        if (observation.platformMessage != null) {
            addMessage(result, observation.platformMessage, warnings);
        } else {
            result.put("recordCount", 0);
            result.put("records", new ArrayList<>());
        }
        return result;
    }

    private static String bridgeStatus(NfcNdefStatus status) {
        switch (status) {
            case NOT_CHECKED:
                return "notChecked";
            case NOT_SUPPORTED:
                return "unsupported";
            case READ_ONLY:
                return "readOnly";
            case READ_WRITE:
                return "writable";
            case READ_ERROR:
                return "readError";
            case UNKNOWN:
                return "unknown";
            default:
                throw new IllegalStateException("Unhandled NDEF status: " + status);
        }
    }

    private static void addMessage(
            Map<String, Object> destination,
            android.nfc.NdefMessage message,
            List<String> warnings
    ) {
        byte[] messageBytes = message.toByteArray();
        destination.put("messageHex", ByteEncoding.toHex(messageBytes));
        destination.put("messageBase64", ByteEncoding.toBase64(messageBytes));
        List<Map<String, Object>> records = new ArrayList<>();
        NdefRecord[] rawRecords = message.getRecords();
        for (int index = 0; index < rawRecords.length; index++) {
            records.add(inspectRecord(rawRecords[index], index, warnings));
        }
        destination.put("recordCount", records.size());
        destination.put("records", records);
    }

    private static Map<String, Object> inspectRecord(
            NdefRecord record,
            int index,
            List<String> warnings
    ) {
        Map<String, Object> result = new LinkedHashMap<>();
        byte[] type = record.getType();
        byte[] identifier = record.getId();
        byte[] payload = record.getPayload();

        result.put("index", index);
        result.put("tnf", (int) record.getTnf());
        result.put("tnfName", tnfName(record.getTnf()));
        putBytes(result, "type", type);
        putBytes(result, "id", identifier);
        putBytes(result, "payload", payload);

        String printableType = printableAscii(type);
        if (printableType != null) {
            result.put("typeAscii", printableType);
        }

        try {
            if (record.getTnf() == NdefRecord.TNF_WELL_KNOWN
                    && Arrays.equals(type, NdefRecord.RTD_TEXT)) {
                Map<String, Object> decoded = NdefPayloadCodec.decodeText(payload);
                if (decoded.isEmpty()) {
                    warnings.add(
                            "NDEF Text record " + index + " has an invalid payload header"
                    );
                } else {
                    result.putAll(decoded);
                }
            }

            if (record.getTnf() == NdefRecord.TNF_WELL_KNOWN
                    && Arrays.equals(type, NdefRecord.RTD_URI)) {
                String uri = NdefPayloadCodec.decodeUri(payload);
                if (uri != null) {
                    result.put("uri", uri);
                }
            } else {
                Uri uri = record.toUri();
                if (uri != null) {
                    result.put("uri", uri.toString());
                }
            }

            String mimeType = record.toMimeType();
            if (mimeType != null) {
                result.put("mimeType", mimeType);
            }

            if (record.getTnf() == NdefRecord.TNF_EXTERNAL_TYPE
                    && printableType != null) {
                result.put("externalType", printableType);
            }
        } catch (RuntimeException error) {
            warnings.add(
                    "NDEF record " + index + " standard decoding failed: "
                            + error.getClass().getSimpleName()
            );
        }
        return result;
    }

    private static Map<String, Object> inspectTechnologyDetails(
            Tag tag,
            List<String> warnings
    ) {
        Map<String, Object> result = new LinkedHashMap<>();

        inspectDetail(result, warnings, "nfcA", () -> {
            NfcA tech = NfcA.get(tag);
            if (tech == null) {
                return null;
            }
            Map<String, Object> values = new LinkedHashMap<>();
            putBytes(values, "atqa", tech.getAtqa());
            values.put("sak", tech.getSak() & 0xFFFF);
            values.put(
                    "sakHex",
                    String.format(Locale.ROOT, "%04X", tech.getSak() & 0xFFFF)
            );
            values.put("maxTransceiveLength", tech.getMaxTransceiveLength());
            return values;
        });

        inspectDetail(result, warnings, "nfcB", () -> {
            NfcB tech = NfcB.get(tag);
            if (tech == null) {
                return null;
            }
            Map<String, Object> values = new LinkedHashMap<>();
            putBytes(values, "applicationData", tech.getApplicationData());
            putBytes(values, "protocolInfo", tech.getProtocolInfo());
            values.put("maxTransceiveLength", tech.getMaxTransceiveLength());
            return values;
        });

        inspectDetail(result, warnings, "nfcF", () -> {
            NfcF tech = NfcF.get(tag);
            if (tech == null) {
                return null;
            }
            Map<String, Object> values = new LinkedHashMap<>();
            putBytes(values, "manufacturer", tech.getManufacturer());
            putBytes(values, "systemCode", tech.getSystemCode());
            values.put("maxTransceiveLength", tech.getMaxTransceiveLength());
            return values;
        });

        inspectDetail(result, warnings, "nfcV", () -> {
            NfcV tech = NfcV.get(tag);
            if (tech == null) {
                return null;
            }
            Map<String, Object> values = new LinkedHashMap<>();
            values.put("dsfId", tech.getDsfId() & 0xFF);
            values.put("responseFlags", tech.getResponseFlags() & 0xFF);
            values.put("maxTransceiveLength", tech.getMaxTransceiveLength());
            return values;
        });

        inspectDetail(result, warnings, "isoDep", () -> {
            IsoDep tech = IsoDep.get(tag);
            if (tech == null) {
                return null;
            }
            Map<String, Object> values = new LinkedHashMap<>();
            putBytes(values, "historicalBytes", tech.getHistoricalBytes());
            putBytes(values, "hiLayerResponse", tech.getHiLayerResponse());
            values.put("maxTransceiveLength", tech.getMaxTransceiveLength());
            values.put(
                    "extendedLengthApduSupported",
                    tech.isExtendedLengthApduSupported()
            );
            return values;
        });

        inspectDetail(result, warnings, "mifareUltralight", () -> {
            MifareUltralight tech = MifareUltralight.get(tag);
            if (tech == null) {
                return null;
            }
            Map<String, Object> values = new LinkedHashMap<>();
            values.put("type", mifareUltralightType(tech.getType()));
            values.put("typeValue", tech.getType());
            values.put("maxTransceiveLength", tech.getMaxTransceiveLength());
            return values;
        });

        inspectDetail(result, warnings, "mifareClassic", () -> {
            MifareClassic tech = MifareClassic.get(tag);
            if (tech == null) {
                return null;
            }
            Map<String, Object> values = new LinkedHashMap<>();
            values.put("type", mifareClassicType(tech.getType()));
            values.put("typeValue", tech.getType());
            values.put("sizeBytes", tech.getSize());
            values.put("sectorCount", tech.getSectorCount());
            values.put("blockCount", tech.getBlockCount());
            values.put("maxTransceiveLength", tech.getMaxTransceiveLength());
            return values;
        });

        inspectDetail(result, warnings, "nfcBarcode", () -> {
            NfcBarcode tech = NfcBarcode.get(tag);
            if (tech == null) {
                return null;
            }
            Map<String, Object> values = new LinkedHashMap<>();
            values.put("type", nfcBarcodeType(tech.getType()));
            values.put("typeValue", tech.getType());
            return values;
        });
        return result;
    }

    private interface DetailReader {
        Map<String, Object> read();
    }

    private static void inspectDetail(
            Map<String, Object> destination,
            List<String> warnings,
            String name,
            DetailReader reader
    ) {
        try {
            Map<String, Object> values = reader.read();
            if (values != null) {
                destination.put(name, values);
            }
        } catch (RuntimeException error) {
            warnings.add(
                    "Unable to inspect Android " + name + " metadata: "
                            + error.getClass().getSimpleName()
            );
        }
    }

    private static String[] safeNativeTechnologies(Tag tag) {
        String[] result = tag.getTechList();
        return result == null ? new String[0] : result;
    }

    private static List<NfcTechnology> technologies(String[] nativeNames) {
        Set<NfcTechnology> result = new LinkedHashSet<>();
        for (String name : nativeNames) {
            if (NfcA.class.getName().equals(name)) {
                result.add(NfcTechnology.NFC_A);
            } else if (NfcB.class.getName().equals(name)) {
                result.add(NfcTechnology.NFC_B);
            } else if (NfcF.class.getName().equals(name)) {
                result.add(NfcTechnology.NFC_F);
            } else if (NfcV.class.getName().equals(name)) {
                result.add(NfcTechnology.NFC_V);
                result.add(NfcTechnology.ISO_15693);
            } else if (IsoDep.class.getName().equals(name)) {
                result.add(NfcTechnology.ISO_DEP);
            } else if (MifareClassic.class.getName().equals(name)) {
                result.add(NfcTechnology.MIFARE);
                result.add(NfcTechnology.MIFARE_CLASSIC);
            } else if (MifareUltralight.class.getName().equals(name)) {
                result.add(NfcTechnology.MIFARE);
                result.add(NfcTechnology.MIFARE_ULTRALIGHT);
            } else if (Ndef.class.getName().equals(name)) {
                result.add(NfcTechnology.NDEF);
            } else if (NdefFormatable.class.getName().equals(name)) {
                result.add(NfcTechnology.NDEF_FORMATABLE);
            } else if (NfcBarcode.class.getName().equals(name)) {
                result.add(NfcTechnology.NFC_BARCODE);
            } else if (name != null) {
                result.add(NfcTechnology.UNKNOWN);
            }
        }
        return new ArrayList<>(result);
    }

    private static List<String> technologyValues(List<NfcTechnology> technologies) {
        List<String> result = new ArrayList<>(technologies.size());
        for (NfcTechnology technology : technologies) {
            result.add(technology.getValue());
        }
        return result;
    }

    private static Map<String, Object> bytesValue(byte[] bytes) {
        Map<String, Object> value = new LinkedHashMap<>();
        value.put("hex", ByteEncoding.toHex(bytes));
        value.put("base64", ByteEncoding.toBase64(bytes));
        value.put("length", bytes == null ? 0 : bytes.length);
        return value;
    }

    private static void putBytes(Map<String, Object> map, String name, byte[] bytes) {
        map.put(name + "Hex", ByteEncoding.toHex(bytes));
        map.put(name + "Base64", ByteEncoding.toBase64(bytes));
    }

    private static Map<String, Object> errorValue(Throwable error) {
        Map<String, Object> value = new LinkedHashMap<>();
        value.put("type", error.getClass().getSimpleName());
        value.put(
                "message",
                error.getMessage() == null
                        ? "No native error message"
                        : error.getMessage()
        );
        return value;
    }

    private static String printableAscii(byte[] bytes) {
        if (bytes == null || bytes.length == 0) {
            return null;
        }
        for (byte value : bytes) {
            int unsigned = value & 0xFF;
            if (unsigned < 0x20 || unsigned > 0x7E) {
                return null;
            }
        }
        return new String(bytes, StandardCharsets.US_ASCII);
    }

    private static String tnfName(short tnf) {
        switch (tnf) {
            case NdefRecord.TNF_EMPTY:
                return "empty";
            case NdefRecord.TNF_WELL_KNOWN:
                return "wellKnown";
            case NdefRecord.TNF_MIME_MEDIA:
                return "mimeMedia";
            case NdefRecord.TNF_ABSOLUTE_URI:
                return "absoluteUri";
            case NdefRecord.TNF_EXTERNAL_TYPE:
                return "externalType";
            case NdefRecord.TNF_UNKNOWN:
                return "unknown";
            case NdefRecord.TNF_UNCHANGED:
                return "unchanged";
            default:
                return "reserved";
        }
    }

    private static String mifareUltralightType(int type) {
        switch (type) {
            case MifareUltralight.TYPE_ULTRALIGHT:
                return "ultralight";
            case MifareUltralight.TYPE_ULTRALIGHT_C:
                return "ultralightC";
            default:
                return "unknown";
        }
    }

    private static String mifareClassicType(int type) {
        switch (type) {
            case MifareClassic.TYPE_CLASSIC:
                return "classic";
            case MifareClassic.TYPE_PLUS:
                return "plus";
            case MifareClassic.TYPE_PRO:
                return "pro";
            default:
                return "unknown";
        }
    }

    private static String nfcBarcodeType(int type) {
        return type == NfcBarcode.TYPE_KOVIO ? "kovio" : "unknown";
    }
}
