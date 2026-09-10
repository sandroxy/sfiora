export type {
  NfcCapabilities,
  NfcErrorCode,
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
  NfcScanOptions,
  NfcScanMessages,
  NfcTagSnapshot,
  NfcWriteOptions,
  NfcWriteMessages,
  NfcWriteResult,
} from '../../contract/types';

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
} from '../../contract/types';

export declare class SfioraError extends Error {
  readonly code: NfcErrorCode;
  readonly recoverable: boolean;
  readonly nativeError?: NfcNativeError;
  readonly cause?: unknown;
}

export declare function getCapabilities(): Promise<NfcCapabilities>;
export declare function startScan(
  options?: NfcScanOptions
): Promise<NfcTagSnapshot>;
export declare function cancelScan(): Promise<void>;
export declare function isScanning(): Promise<boolean>;
export declare function writeNdef(
  message: NfcNdefMessageInput,
  options?: NfcWriteOptions
): Promise<NfcWriteResult>;
export declare function initializeNdef(
  message: NfcNdefMessageInput,
  marker: NfcNdefExternalTypeMarker,
  options?: NfcWriteOptions
): Promise<NfcNdefInitializationResult>;
export declare function cancelWrite(): Promise<void>;
export declare function isWriting(): Promise<boolean>;

export interface NfcWaitForIdleOptions {
  /** Integer 1–60000; default 5000 milliseconds. */
  timeoutMilliseconds?: number;
}
/** Wait for this bridge's session to close. Does not cancel it or reserve the next session.
 * Rejects with SESSION_CLOSE_TIMEOUT on deadline; native busy state is unchanged.
 */
export function waitForIdle(options?: NfcWaitForIdleOptions): Promise<void>;
