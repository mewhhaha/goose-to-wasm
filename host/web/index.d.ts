export type FileContents = string | Uint8Array;
export type FilePath = string | Uint8Array;
export type FileSnapshot = Record<string, Uint8Array>;

export interface FileSystemOptions {
  files?: Record<string, FileContents> | Map<string, FileContents>;
  dirs?: FilePath[];
  cwd?: FilePath;
}

export const MAX_PATH_BYTES: number;

export class MemoryFS {
  constructor(options?: FileSystemOptions);
  readFile(path: FilePath): Uint8Array | null;
  writeFile(path: FilePath, data: FileContents): boolean;
  writeFileAtomic(path: FilePath, data: FileContents): boolean;
  appendFile(path: FilePath, data: FileContents): boolean;
  fileExists(path: FilePath): boolean;
  removeFile(path: FilePath): boolean;
  renameFile(from: FilePath, to: FilePath): boolean;
  makeDir(path: FilePath): boolean;
  isDir(path: FilePath): boolean;
  removeDir(path: FilePath): boolean;
  listDir(path: FilePath): Uint8Array[] | null;
  snapshot(): FileSnapshot;
  readText(path: FilePath): string | null;
  writeText(path: FilePath, text: string): boolean;
}

export interface LocalStorageOptions extends FileSystemOptions {
  prefix?: string;
  storage?: Pick<Storage, "getItem" | "setItem" | "removeItem"> | null;
}

export class LocalStorageFS extends MemoryFS {
  constructor(options?: LocalStorageOptions);
  clearStorage(): void;
}

export interface OPFSOptions extends FileSystemOptions {
  root?: FileSystemDirectoryHandle;
  name?: string;
}

export class OPFSAdapter extends MemoryFS {
  static open(options?: OPFSOptions): Promise<OPFSAdapter>;
  syncToMemory(): Promise<MemoryFS>;
  syncToMemory<FS extends MemoryFS>(fs: FS): Promise<FS>;
  close(): void;
}

export class GooseExitError extends Error {
  constructor(code: number);
  code: number;
}

export class GooseAbortError extends Error {
  constructor(reason: string, line: number);
  reason: string;
  line: number;
  exitCode: number;
}

export const MAX_SOUNDS: number;
export const MAX_VOICES: number;

export interface AudioOptions {
  audioContext?: AudioContext;
}

export class GooseAudioMixer {
  constructor(options?: AudioOptions);
  lastError: string;
  available(): boolean;
  open(sampleRate?: number): boolean;
  openOffline(sampleRate?: number): boolean;
  close(): void | Promise<void>;
  createSound(samples: ArrayLike<number>, sampleRate?: number, channels?: number): bigint;
  releaseSound(soundId: bigint): boolean;
  play(soundId: bigint, volume?: number, pan?: number, pitch?: number, looping?: boolean): bigint;
  playing(voiceId: bigint): boolean;
  stop(voiceId: bigint): void;
  stopAll(): void;
  setVoice(voiceId: bigint, volume?: number, pan?: number, pitch?: number): boolean;
  voicePosition(voiceId: bigint): number;
  seek(voiceId: bigint, seconds: number): boolean;
  render(out: Float32Array): boolean;
}

export function gooseFloat(value: number, bits?: number): string;
export function gooseFloatDigits(value: number): { digits: Uint8Array; point: number };
export function detectMemory64(wasmBytes: Uint8Array): boolean;
export function supportsJspi(): boolean;

export interface GfxFrameInfo {
  frameCount: number;
  time: number;
  deltaTime: number;
  width: number;
  height: number;
}

export interface GooseGfx {
  stop(): void;
  close(): void;
  screenshotPngBytes(): Uint8Array | null;
  compositeCanvas2D(overlayCanvas: HTMLCanvasElement | OffscreenCanvas): boolean;
  injectKey(name: string, down: boolean): boolean;
  injectMouse(kind: number, x: number, y: number, button: number, wheel: number): void;
  injectText(text: string): void;
  injectFocus(focused: boolean): boolean;
  readonly width: number;
  readonly height: number;
  readonly gl: WebGL2RenderingContext | null;
  readonly canvas: HTMLCanvasElement | null;
}

export interface GooseUi {
  readonly drawCommandCount: number;
  dispose(): void;
}

export interface GoosePhysics {
  dispose(): void;
}

export type OutputCallback = (chunk: Uint8Array, text: string) => void;
export type Stdin = Uint8Array | string | (() => Uint8Array | null);
export type FileSystem = MemoryFS | LocalStorageFS | OPFSAdapter;

export interface HostOptions extends AudioOptions {
  memory64?: boolean;
  fs?: FileSystem;
  files?: Record<string, FileContents>;
  dirs?: string[];
  cwd?: string;
  args?: string[];
  env?: Record<string, string> | Map<string, string>;
  resourceDir?: string | null;
  stdin?: Stdin;
  onStdout?: OutputCallback;
  onStderr?: OutputCallback;
  captureOutput?: boolean;
  sleepMs?: (ms: number) => void;
  maxMainThreadSleepMs?: number;
  canvas?: HTMLCanvasElement | null;
  asyncFrame?: boolean;
  maxFrames?: number;
  onFrame?: (info: GfxFrameInfo) => void;
  onTitle?: (title: string) => void;
  physicsEnabled?: boolean;
  imports?: Record<string, Record<string, unknown>>;
}

export interface HostState {
  memory: WebAssembly.Memory | null;
  memory64: boolean;
  reserve: ((control: number | bigint, count: number | bigint) => number | bigint) | null;
}

export interface GooseHost {
  imports: WebAssembly.Imports;
  fs: FileSystem;
  audio: GooseAudioMixer;
  gfx: GooseGfx;
  ui: GooseUi;
  physics: GoosePhysics;
  state: HostState;
  bind(instance: WebAssembly.Instance, options?: { memory64?: boolean }): void;
  stop(): void;
  stdoutBytes(): Uint8Array;
  stdoutText(): string;
  stderrBytes(): Uint8Array;
  stderrText(): string;
  resetOutput(): void;
  resetStdin(input?: Stdin): void;
  dispose(): Promise<void>;
}

export interface LoadOptions extends HostOptions {
  streaming?: boolean;
  throwOnError?: boolean;
}

export interface RunOptions extends LoadOptions {
  entry?: string;
  entryArgs?: unknown[];
  keepAlive?: boolean;
}

export interface RunResult {
  exitCode: number;
  aborted: boolean;
  abortReason: string | null;
  abortLine: number | null;
  returnValue: unknown;
  stdout: string;
  stderr: string;
  stdoutBytes: Uint8Array;
  stderrBytes: Uint8Array;
  durationMs: number;
}

export interface LoadedGoose {
  module: WebAssembly.Module;
  instance: WebAssembly.Instance;
  exports: WebAssembly.Exports;
  host: GooseHost;
  memory64: boolean;
  run(entry?: string, ...args: unknown[]): RunResult;
  runAsync(entry?: string, ...args: unknown[]): Promise<RunResult>;
  dispose(): Promise<void>;
}

export type WorkerSource = ArrayBuffer | ArrayBufferView | Response | Promise<Response> | URL | string;
export type WasmSource = WorkerSource | WebAssembly.Module;
export function createGooseHost(options?: HostOptions): GooseHost;
export function loadGoose(source: WasmSource, options?: LoadOptions): Promise<LoadedGoose>;
export function runGoose(source: WasmSource, options?: RunOptions): Promise<RunResult & { fs: FileSystem }>;

export interface WorkerOptions {
  worker?: Pick<Worker, "addEventListener" | "removeEventListener" | "postMessage" | "terminate">;
}

export interface WorkerRunOptions extends Pick<
  RunOptions,
  "args" | "env" | "files" | "dirs" | "cwd" | "resourceDir" | "memory64" | "entry" | "entryArgs" | "onStdout" | "onStderr"
> {
  stdin?: Uint8Array | string;
  sab?: SharedArrayBuffer;
}

export interface WorkerRunResult extends Omit<RunResult, "returnValue"> {
  files: FileSnapshot;
}

export interface GooseWorker {
  run(source: WorkerSource, options?: WorkerRunOptions): Promise<WorkerRunResult>;
  terminate(): void;
}

export function createGooseWorker(options?: WorkerOptions): GooseWorker;
