import type { TurboModule } from 'react-native';
import type { UnsafeObject } from 'react-native/Libraries/Types/CodegenTypes';
import { TurboModuleRegistry } from 'react-native';

export interface Spec extends TurboModule {
  getCapabilities(): Promise<UnsafeObject>;
  startScan(options: UnsafeObject): Promise<UnsafeObject>;
  cancelScan(): Promise<void>;
  isScanning(): Promise<boolean>;
  writeNdef(
    message: UnsafeObject,
    options: UnsafeObject
  ): Promise<UnsafeObject>;
  initializeNdef(
    message: UnsafeObject,
    marker: UnsafeObject,
    options: UnsafeObject
  ): Promise<UnsafeObject>;
  cancelWrite(): Promise<void>;
  isWriting(): Promise<boolean>;
}

export default TurboModuleRegistry.get<Spec>('Sfiora');
