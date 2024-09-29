export function isValidJson(jsonString: string): boolean {
  if (jsonString.trim().length === 0) {
    return true;
  }
  try {
    JSON.parse(jsonString);
    return true;
  } catch {
    return false;
  }
}

export function decodeNotifyValue(hex: string): string {
  return `${hex.slice(0, 66)}${Buffer.from(hex.slice(66), "hex").toString()}`;
}
