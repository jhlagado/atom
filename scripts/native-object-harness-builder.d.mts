export type NativeObjectHarnessOptions = {
  origin?: number;
  imageOrigin?: number;
  workspaceOrigin?: number;
  preludeSource?: string;
  gatewaySource?: string;
  /** Z80 label called by the Atom core for each source byte. Defaults to NA_SREAD. */
  sourceReadTarget?: string;
  registerContractsProfile?: string;
  registerContractsInterfaces?: string[];
};

export type NativeObjectHarnessReport = {
  format: "atom-native-object-harness-census";
  version: 1;
  loadAddress: number;
  coreOrigin?: number;
  assembleEntry: number;
  adapterInitEntry: number;
  gatewayEntry: number;
  sourceReadEntry: number;
  configuredSourceReadEntry: number;
  residentEnd: number;
  residentBytes: number;
  nativeCoreResidentBytes: number;
  adapterResidentDeltaBytes: number;
  commonWorkspaceBytes: number;
  transferBufferBytes: number;
  maximumSourceParts: number;
  sourceNameTableBytes: number;
  maximumObjectNameBytes: number;
  maximumSourceObjectBytes: number;
  maximumOutputObjectBytes: number;
  sha256: string;
  symbols: Record<string, number>;
  fixedWorkspaceStart?: number;
  fixedWorkspaceEnd?: number;
  fixedWorkspaceBytes?: number;
  nativeCoreFixedWorkspaceBytes?: number;
  adapterFixedWorkspaceBytes?: number;
  workspaceSha256?: string;
};

export type NativeObjectHarnessBuild = {
  bytes: Uint8Array;
  workspaceBytes?: Uint8Array;
  debugMap: Record<string, unknown>;
  report: NativeObjectHarnessReport;
};

export function buildNativeObjectHarness(
  options?: NativeObjectHarnessOptions,
): Promise<NativeObjectHarnessBuild>;
