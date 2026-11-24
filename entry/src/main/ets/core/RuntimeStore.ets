import fs from '@ohos.file.fs';
import { buffer } from '@kit.ArkTS';
import { common } from '@kit.AbilityKit';
import { RUNTIME_SCHEMA, RuntimeSnapshot } from './RuntimeSnapshot';

/** 进程间通信走原子文件快照；preferences/AppStorage 不承担 VPN 运行状态同步。 */
export class RuntimeStore {
  // 最近一次读取失败的原因（文件缺失/为空/读取异常/解析失败/版本不符），供诊断轨迹展示。
  static lastReadError: string = '';
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

  static writeSeq: number = 0;

  static write(context: common.Context, snapshot: RuntimeSnapshot): void {
    snapshot.updatedAt = Date.now();
    let dir: string = context.filesDir;
    let encoded: buffer.Buffer = buffer.from(JSON.stringify(snapshot), 'utf-8');
    let bytes: ArrayBuffer = encoded.buffer.slice(encoded.byteOffset, encoded.byteOffset + encoded.length);
    if (bytes.byteLength === 0) {
      throw new Error('运行状态序列化为空');
    }
    // 真机轨迹显示单份快照文件会被系统间歇清空（stat size=0）。
    // 轮换写 3 个编号副本 + 1 个兼容副本，读取端取 updatedAt 最新的可解析快照，
    // 单份文件异常不影响其余副本。
    let slot: number = RuntimeStore.writeSeq % 3;
    RuntimeStore.writeSeq = RuntimeStore.writeSeq + 1;
    let targets: Array<string> = [dir + '/vpn-runtime-' + slot + '.json', dir + '/vpn-runtime.json'];
    for (let i = 0; i < targets.length; i++) {
      let temporary: string = targets[i] + '.' + snapshot.sessionId + '.tmp';
      let file: fs.File = fs.openSync(temporary,
        fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      try {
        let offset: number = 0;
        while (offset < bytes.byteLength) {
          let rest: ArrayBuffer = bytes.slice(offset);
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
      fs.renameSync(temporary, targets[i]);
    }
  }

  static read(context: common.Context): RuntimeSnapshot | null {
    let dir: string = context.filesDir;
    let candidates: Array<string> = [
      dir + '/vpn-runtime.json',
      dir + '/vpn-runtime-0.json',
      dir + '/vpn-runtime-1.json',
      dir + '/vpn-runtime-2.json'
    ];
    let best: RuntimeSnapshot | null = null;
    let errors: string = '';
    for (let i = 0; i < candidates.length; i++) {
      let text: string = RuntimeStore.readTail(candidates[i], 65536);
      if (text === '') {
        errors += RuntimeStore.lastReadError + ';';
        continue;
      }
      try {
        let snapshot: RuntimeSnapshot = JSON.parse(text) as RuntimeSnapshot;
        if (snapshot.schema !== RUNTIME_SCHEMA || snapshot.native === undefined) {
          errors += 'schema(' + snapshot.schema + ');';
          continue;
        }
        if (best === null || snapshot.updatedAt > best.updatedAt) {
          best = snapshot;
        }
      } catch (e) {
        errors += 'parse(' + candidates[i].substring(candidates[i].length - 20) + ');';
      }
    }
    if (best === null) {
      RuntimeStore.lastReadError = errors;
      return null;
    }
    RuntimeStore.lastReadError = '';
    return best;
  }

  static readTail(path: string, maximum: number): string {
    let file: fs.File | null = null;
    try {
      file = fs.openSync(path, fs.OpenMode.READ_ONLY);
      let size: number = fs.statSync(file.fd).size;
      let length: number = Math.min(size, maximum);
      if (length <= 0) {
        RuntimeStore.lastReadError = '文件为空(0 字节)';
        return '';
      }
      let bytes: ArrayBuffer = new ArrayBuffer(length);
      let count: number = fs.readSync(file.fd, bytes, { offset: Math.max(0, size - length), length: length });
      RuntimeStore.lastReadError = '';
      return buffer.from(bytes.slice(0, count)).toString('utf-8');
    } catch (e) {
      RuntimeStore.lastReadError = '打开/读取失败: ' + String(e);
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
