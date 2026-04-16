// Stub for Tauri APIs in the web build.
// Shared modules (e.g. wikilinks.ts) import from @tauri-apps — these
// aliases resolve here so the web build compiles. The functions throw
// at runtime if called, but the web entry point never calls them.

export function invoke(): Promise<never> {
  return Promise.reject(new Error("Tauri IPC not available in web build"));
}

export function open(): Promise<null> {
  return Promise.resolve(null);
}

export function save(): Promise<null> {
  return Promise.resolve(null);
}

export function ask(): Promise<boolean> {
  return Promise.resolve(false);
}

export function listen(): Promise<() => void> {
  return Promise.resolve(() => {});
}

export function getCurrentWindow(): Record<string, unknown> {
  return {};
}
