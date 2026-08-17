export declare const VERSION_RE: RegExp;
export declare function parseVersion(
  version: string,
): [number, number, number, number] | null;
export declare function compareVersions(a: string, b: string): number;
