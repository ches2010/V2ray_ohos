/** 只把更高的语义版本视为升级；不能因版本字符串不同就提示降级。 */
export function isNewerVersion(current: string, candidate: string): boolean {
  let a: RegExpMatchArray | null = current.match(/^v?(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?$/);
  let b: RegExpMatchArray | null = candidate.match(/^v?(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?$/);
  if (a === null || b === null) return false;
  for (let i: number = 1; i <= 3; i++) {
    let left: number = Number(a[i]);
    let right: number = Number(b[i]);
    if (right > left) return true;
    if (right < left) return false;
  }
  // GitHub latest 不返回预发布；同版本的正式版高于本地预发布版。
  return Boolean(a[4]) && !Boolean(b[4]);
}
