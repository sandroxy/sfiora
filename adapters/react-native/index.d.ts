export type {
  AndroidScanPresentation,
  NdefRecordSnapshot,
  NdefSnapshot,
  NdefStatus,
  NfcAndroidScanOptions,
  NfcByteValue,
  NfcCapabilities,
  NfcErrorCode,
  NfcErrorPayload,
  NfcIosScanOptions,
  NfcJsonObject,
  NfcJsonPrimitive,
  NfcJsonValue,
  NfcNativeError,
  NfcNdefExternalRecordInput,
  NfcNdefExternalTypeMarker,
  NfcNdefInitializationMarkerResult,
  NfcNdefInitializationResult,
  NfcNdefInitializedResult,
  NfcNdefPreservedResult,
  NfcNdefMessageInput,
  NfcNdefMimeRecordInput,
  NfcNdefRecordInput,
  NfcNdefTextEncoding,
  NfcNdefTextRecordInput,
  NfcNdefUriRecordInput,
  NfcPlatform,
  NfcPlatformDetails,
  NfcPollingTechnology,
  NfcReadMode,
  NfcScanOptions,
  NfcScanMessages,
  NfcTagSnapshot,
  NfcTechnology,
  NfcWriteOptions,
  NfcWriteMessages,
  NfcWriteResult,
} from './contract/types';

import type {
  NfcCapabilities,
  NfcErrorCode,
  NfcNativeError,
  NfcNdefExternalTypeMarker,
  NfcNdefInitializationResult,
  NfcNdefMessageInput,
  NfcScanOptions,
  NfcTagSnapshot,
  NfcWriteOptions,
  NfcWriteResult,
} from './contract/types';

export class SfioraError extends Error {
  readonly code: NfcErrorCode;
  readonly recoverable: boolean;
  readonly nativeError?: NfcNativeError;
  readonly cause?: unknown;
}

export function getCapabilities(): Promise<NfcCapabilities>;
export function startScan(options?: NfcScanOptions): Promise<NfcTagSnapshot>;
export function cancelScan(): Promise<void>;
export function isScanning(): Promise<boolean>;
export function writeNdef(
  message: NfcNdefMessageInput,
  options?: NfcWriteOptions
): Promise<NfcWriteResult>;
export function initializeNdef(
  message: NfcNdefMessageInput,
  marker: NfcNdefExternalTypeMarker,
  options?: NfcWriteOptions
): Promise<NfcNdefInitializationResult>;
export function cancelWrite(): Promise<void>;
export function isWriting(): Promise<boolean>;

export interface NfcWaitForIdleOptions {
  /** Integer 1–60000; default 5000 milliseconds. */
  timeoutMilliseconds?: number;
}
/** Wait for this bridge's session to close. Does not cancel it or reserve the next session.
 * Rejects with SESSION_CLOSE_TIMEOUT on deadline; native busy state is unchanged.
 */
export function waitForIdle(options?: NfcWaitForIdleOptions): Promise<void>;
