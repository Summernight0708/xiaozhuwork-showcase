declare namespace Deno {
  interface FsFile {
    seek(offset: number, whence?: number): Promise<void>;
    read(buffer: Uint8Array): Promise<number | null>;
    write(buffer: Uint8Array): Promise<number>;
    close(): void;
  }

  function makeTempFile(options?: {
    dir?: string;
    prefix?: string;
    suffix?: string;
  }): Promise<string>;
  function open(
    path: string,
    options: { read?: boolean; write?: boolean; truncate?: boolean },
  ): Promise<FsFile>;
  function readFile(path: string): Promise<Uint8Array>;
  function remove(path: string): Promise<void>;
}
