import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { randomBytes } from "node:crypto";
const DIR = join(homedir(), ".dsh", "dsh-notch");
const RUNTIME_PATH = join(DIR, "runtime.json");
const SEEN = join(DIR, "seen.json");
function ensureDir() {
  mkdirSync(DIR, { recursive: true, mode: 448 });
}
function readJson(path) {
  try {
    return JSON.parse(readFileSync(path, "utf8"));
  } catch {
    return void 0;
  }
}
function loadOrCreateToken() {
  const existing = readJson(RUNTIME_PATH);
  if (existing?.token && existing.token.length >= 16) return existing.token;
  return randomBytes(24).toString("hex");
}
function writeRuntime(file) {
  ensureDir();
  writeFileSync(RUNTIME_PATH, `${JSON.stringify(file, null, 2)}
`, { encoding: "utf8", mode: 384 });
}
function loadSeen() {
  const value = readJson(SEEN);
  if (!value || typeof value !== "object") return {};
  return value;
}
function saveSeen(map) {
  ensureDir();
  writeFileSync(SEEN, `${JSON.stringify(map)}
`, { encoding: "utf8", mode: 384 });
}
export {
  RUNTIME_PATH,
  loadOrCreateToken,
  loadSeen,
  saveSeen,
  writeRuntime
};

//# sourceMappingURL=store.js.map
