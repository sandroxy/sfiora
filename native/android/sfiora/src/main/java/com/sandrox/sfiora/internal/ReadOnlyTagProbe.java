package com.sandrox.sfiora.internal;

import android.nfc.Tag;
import android.nfc.TagLostException;
import android.nfc.tech.MifareClassic;
import android.nfc.tech.MifareUltralight;
import android.nfc.tech.NfcA;

import java.io.IOException;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Optional read-only probes for common memory tags.
 *
 * No method in this class issues write, format, lock or key-changing commands.
 */
public final class ReadOnlyTagProbe {
    private static final int MAX_TYPE_2_START_PAGE = 252;

    private ReadOnlyTagProbe() {
    }

    public static Map<String, Object> inspect(Tag tag, List<String> warnings) {
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("enabled", true);
        List<String> attempted = new ArrayList<>();

        MifareUltralight ultralight = null;
        try {
            ultralight = MifareUltralight.get(tag);
        } catch (RuntimeException error) {
            warnings.add("Android could not create MifareUltralight technology");
        }

        if (ultralight != null) {
            attempted.add("mifareUltralightMemory");
            result.put(
                    "mifareUltralightMemory",
                    probeMifareUltralight(ultralight)
            );
        } else {
            NfcA nfcA = null;
            try {
                nfcA = NfcA.get(tag);
            } catch (RuntimeException error) {
                warnings.add("Android could not create NfcA technology for Type 2 probe");
            }
            if (nfcA != null && (nfcA.getSak() & 0xFF) == 0x00) {
                attempted.add("nfcAType2Memory");
                result.put("nfcAType2Memory", probeType2ViaNfcA(nfcA));
            }
        }

        if (!Thread.currentThread().isInterrupted()) {
            MifareClassic classic = null;
            try {
                classic = MifareClassic.get(tag);
            } catch (RuntimeException error) {
                warnings.add(
                        "MIFARE Classic is reported by the tag but unsupported "
                                + "by this Android NFC stack"
                );
            }
            if (classic != null) {
                attempted.add("mifareClassicDefaultKeys");
                result.put("mifareClassicDefaultKeys", probeMifareClassic(classic));
            }
        }

        result.put("attempted", attempted);
        if (attempted.isEmpty()) {
            result.put(
                    "note",
                    "No built-in read-only memory probe matches this tag technology"
            );
        }
        return result;
    }

    private static Map<String, Object> probeMifareUltralight(MifareUltralight tech) {
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("driver", "MifareUltralight.readPages");
        result.put("writeCommandsIssued", false);
        List<Map<String, Object>> chunks = new ArrayList<>();
        byte[] firstChunk = null;
        String termination = "maximumProbeRangeReached";

        try {
            tech.connect();
            tech.setTimeout(1_000);
            for (int startPage = 0; startPage <= MAX_TYPE_2_START_PAGE; startPage += 4) {
                if (Thread.currentThread().isInterrupted()) {
                    termination = "scanStopped";
                    break;
                }
                byte[] response;
                try {
                    response = tech.readPages(startPage);
                } catch (TagLostException error) {
                    termination = "tagLost";
                    break;
                } catch (IOException error) {
                    termination = "readStopped:" + error.getClass().getSimpleName();
                    break;
                }
                if (response == null || response.length == 0) {
                    termination = "emptyResponse";
                    break;
                }
                if (firstChunk == null) {
                    firstChunk = response.clone();
                } else if (startPage >= 16 && Arrays.equals(firstChunk, response)) {
                    termination = "memoryWrapDetected";
                    break;
                }
                chunks.add(memoryChunk(startPage, response));
            }
        } catch (IOException | RuntimeException error) {
            result.put("error", errorValue(error));
            termination = "connectionOrReadFailure";
        } finally {
            closeQuietly(tech);
        }

        result.put("termination", termination);
        result.put("chunkCount", chunks.size());
        result.put("bytesRead", totalBytes(chunks));
        result.put("chunks", chunks);
        return result;
    }

    private static Map<String, Object> probeType2ViaNfcA(NfcA tech) {
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("driver", "NfcA Type 2 READ (0x30)");
        result.put("writeCommandsIssued", false);
        List<Map<String, Object>> chunks = new ArrayList<>();
        byte[] firstChunk = null;
        String termination = "maximumProbeRangeReached";

        try {
            tech.connect();
            tech.setTimeout(1_000);
            for (int startPage = 0; startPage <= MAX_TYPE_2_START_PAGE; startPage += 4) {
                if (Thread.currentThread().isInterrupted()) {
                    termination = "scanStopped";
                    break;
                }
                byte[] command = new byte[]{0x30, (byte) (startPage & 0xFF)};
                byte[] response;
                try {
                    response = tech.transceive(command);
                } catch (TagLostException error) {
                    termination = "tagLost";
                    break;
                } catch (IOException error) {
                    termination = "readStopped:" + error.getClass().getSimpleName();
                    break;
                }
                if (response == null || response.length == 0) {
                    termination = "emptyResponse";
                    break;
                }
                if (firstChunk == null) {
                    firstChunk = response.clone();
                } else if (startPage >= 16 && Arrays.equals(firstChunk, response)) {
                    termination = "memoryWrapDetected";
                    break;
                }
                chunks.add(memoryChunk(startPage, response));
            }
        } catch (IOException | RuntimeException error) {
            result.put("error", errorValue(error));
            termination = "connectionOrReadFailure";
        } finally {
            closeQuietly(tech);
        }

        result.put("termination", termination);
        result.put("chunkCount", chunks.size());
        result.put("bytesRead", totalBytes(chunks));
        result.put("chunks", chunks);
        return result;
    }

    private static Map<String, Object> probeMifareClassic(MifareClassic tech) {
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("driver", "MifareClassic common factory keys");
        result.put("writeCommandsIssued", false);
        result.put("sizeBytes", tech.getSize());
        result.put("sectorCount", tech.getSectorCount());
        result.put("blockCount", tech.getBlockCount());

        List<Map<String, Object>> sectors = new ArrayList<>();
        String termination = "complete";
        try {
            tech.connect();
            tech.setTimeout(1_000);
            for (int sectorIndex = 0; sectorIndex < tech.getSectorCount(); sectorIndex++) {
                if (Thread.currentThread().isInterrupted()) {
                    termination = "scanStopped";
                    break;
                }
                Map<String, Object> sector = new LinkedHashMap<>();
                sector.put("sectorIndex", sectorIndex);
                int firstBlock = tech.sectorToBlock(sectorIndex);
                int blockCount = tech.getBlockCountInSector(sectorIndex);
                sector.put("firstBlock", firstBlock);
                sector.put("blockCount", blockCount);

                KeyMatch keyMatch;
                try {
                    keyMatch = authenticateWithCommonKeys(tech, sectorIndex);
                } catch (TagLostException error) {
                    sector.put("authenticated", false);
                    sector.put("error", errorValue(error));
                    sectors.add(sector);
                    termination = "tagLost";
                    break;
                } catch (IOException error) {
                    sector.put("authenticated", false);
                    sector.put("error", errorValue(error));
                    sectors.add(sector);
                    termination = "authenticationIoFailure";
                    break;
                }

                if (keyMatch == null) {
                    sector.put("authenticated", false);
                    sectors.add(sector);
                    continue;
                }

                sector.put("authenticated", true);
                sector.put("keyName", keyMatch.name);
                sector.put("keyType", keyMatch.keyA ? "A" : "B");
                List<Map<String, Object>> blocks = new ArrayList<>();
                for (int offset = 0; offset < blockCount; offset++) {
                    if (Thread.currentThread().isInterrupted()) {
                        termination = "scanStopped";
                        break;
                    }
                    int blockIndex = firstBlock + offset;
                    try {
                        byte[] bytes = tech.readBlock(blockIndex);
                        Map<String, Object> block = new LinkedHashMap<>();
                        block.put("blockIndex", blockIndex);
                        block.put("hex", ByteEncoding.toHex(bytes));
                        block.put("base64", ByteEncoding.toBase64(bytes));
                        blocks.add(block);
                    } catch (TagLostException error) {
                        sector.put("readError", errorValue(error));
                        termination = "tagLost";
                        break;
                    } catch (IOException | RuntimeException error) {
                        sector.put("readError", errorValue(error));
                        break;
                    }
                }
                sector.put("blocks", blocks);
                sectors.add(sector);
                if ("tagLost".equals(termination) || "scanStopped".equals(termination)) {
                    break;
                }
            }
        } catch (IOException | RuntimeException error) {
            result.put("error", errorValue(error));
            termination = "connectionOrReadFailure";
        } finally {
            closeQuietly(tech);
        }

        result.put("termination", termination);
        result.put("sectors", sectors);
        return result;
    }

    private static KeyMatch authenticateWithCommonKeys(
            MifareClassic tech,
            int sectorIndex
    ) throws IOException {
        KeyCandidate[] candidates = {
                new KeyCandidate("KEY_DEFAULT", MifareClassic.KEY_DEFAULT),
                new KeyCandidate(
                        "KEY_MIFARE_APPLICATION_DIRECTORY",
                        MifareClassic.KEY_MIFARE_APPLICATION_DIRECTORY
                ),
                new KeyCandidate("KEY_NFC_FORUM", MifareClassic.KEY_NFC_FORUM)
        };

        for (KeyCandidate candidate : candidates) {
            if (Thread.currentThread().isInterrupted()) {
                return null;
            }
            if (tech.authenticateSectorWithKeyA(sectorIndex, candidate.key)) {
                return new KeyMatch(candidate.name, true);
            }
            if (Thread.currentThread().isInterrupted()) {
                return null;
            }
            if (tech.authenticateSectorWithKeyB(sectorIndex, candidate.key)) {
                return new KeyMatch(candidate.name, false);
            }
        }
        return null;
    }

    private static Map<String, Object> memoryChunk(int startPage, byte[] bytes) {
        Map<String, Object> chunk = new LinkedHashMap<>();
        chunk.put("startPage", startPage);
        chunk.put("endPage", startPage + Math.max(0, bytes.length / 4) - 1);
        chunk.put("length", bytes.length);
        chunk.put("hex", ByteEncoding.toHex(bytes));
        chunk.put("base64", ByteEncoding.toBase64(bytes));
        return chunk;
    }

    private static int totalBytes(List<Map<String, Object>> chunks) {
        int total = 0;
        for (Map<String, Object> chunk : chunks) {
            Object length = chunk.get("length");
            if (length instanceof Number) {
                total += ((Number) length).intValue();
            }
        }
        return total;
    }

    private static Map<String, Object> errorValue(Throwable error) {
        Map<String, Object> value = new LinkedHashMap<>();
        value.put("type", error.getClass().getSimpleName());
        value.put(
                "message",
                error.getMessage() == null ? "No native error message" : error.getMessage()
        );
        return value;
    }

    private static void closeQuietly(MifareUltralight tech) {
        try {
            tech.close();
        } catch (IOException ignored) {
        }
    }

    private static void closeQuietly(NfcA tech) {
        try {
            tech.close();
        } catch (IOException ignored) {
        }
    }

    private static void closeQuietly(MifareClassic tech) {
        try {
            tech.close();
        } catch (IOException ignored) {
        }
    }

    private static final class KeyCandidate {
        final String name;
        final byte[] key;

        KeyCandidate(String name, byte[] key) {
            this.name = name;
            this.key = key;
        }
    }

    private static final class KeyMatch {
        final String name;
        final boolean keyA;

        KeyMatch(String name, boolean keyA) {
            this.name = name;
            this.keyA = keyA;
        }
    }
}
