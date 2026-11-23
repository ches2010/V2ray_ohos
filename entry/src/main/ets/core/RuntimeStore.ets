import fs from '@ohos.file.fs';
import { buffer } from '@kit.ArkTS';
import { common } from '@kit.AbilityKit';
import { RUNTIME_SCHEMA, RuntimeSnapshot } from './RuntimeSnapshot';

/** 进程间通信走原子文件快照；preferences/AppStorage 不承担 VPN 运行状态同步。 */
export class RuntimeStore {
  static init(context: common.Context): void {
    let dir: string = context.filesDir + '/assets';
    if (!fs.accessSync(dir)) {
      fs.mkdirSync(dir, true);
    }
  }

  static fileReady(path: string): boolean {
    try {
      return fs.statSync(path).size > 0;
    } catch (e) {
      return false;
    }
  }

  static write(context: common.Context, snapshot: RuntimeSnapshot): void {
    snapshot.updatedAt = Date.now();
    let path: string = context.filesDir + '/vpn-runtime.json';
    let temporary: string = path + '.' + snapshot.sessionId + '.tmp';
    let file: fs.File = fs.openSync(temporary,
      fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    try {
      let encoded: buffer.Buffer = buffer.from(JSON.stringify(snapshot), 'utf-8');
      let bytes: ArrayBuffer = encoded.buffer.slice(encoded.byteOffset, encoded.byteOffset + encoded.byteLength);
      // writeSync 的返回值不保证一次写完，循环写入防止截断状态文件。
      let view: Uint8Array = new Uint8Array(bytes);
      let offset: number = 0;
      while (offset < view.byteLength) {
        let rest: ArrayBuffer = view.slice(offset).buffer;
        let count: number = fs.writeSync(file.fd, rest);
        if (count <= 0) {
          throw new Error('运行状态文件写入失败');
        }
        offset += count;
      }
      fs.fsyncSync(file.fd);
    } finally {
      fs.closeSync(file.fd);
    }
    fs.renameSync(temporary, path);
  }

  static read(context: common.Context): RuntimeSnapshot | null {
    let text: string = RuntimeStore.readTail(context.filesDir + '/vpn-runtime.json', 65536);
    if (text === '') {
      return null;
    }
    try {
      let snapshot: RuntimeSnapshot = JSON.parse(text) as RuntimeSnapshot;
      if (snapshot.schema !== RUNTIME_SCHEMA || snapshot.native === undefined) {
        return null;
      }
      return snapshot;
    } catch (e) {
      return null;
    }
  }

  static readTail(path: string, maximum: number): string {
    let file: fs.File | null = null;
    try {
      file = fs.openSync(path, fs.OpenMode.READ_ONLY);
      let size: number = fs.statSync(file.fd).size;
      let length: number = Math.min(size, maximum);
      if (length <= 0) {
        return '';
      }
      let bytes: ArrayBuffer = new ArrayBuffer(length);
      let count: number = fs.readSync(file.fd, bytes, { offset: Math.max(0, size - length), length: length });
      return buffer.from(bytes.slice(0, count)).toString('utf-8');
    } catch (e) {
      return '';
    } finally {
      if (file !== null) {
        fs.closeSync(file.fd);
      }
    }
  }

  static redact(text: string): string {
    return text.replace(/[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/g, '[UUID已隐藏]')
      .replace(/(password|token|authorization|uuid)(["'\s:=]+)[^\s,}\n]+/gi, '$1$2[已隐藏]');
  }
}
