export const MAX_PATH_BYTES = 4096;

const encoder = new TextEncoder();
const decoder = new TextDecoder("utf-8", { ignoreBOM: true });
const strictDecoder = new TextDecoder("utf-8", { fatal: true, ignoreBOM: true });

export function validatePathBytes(bytes) {
  return bytes.length === 0 || bytes.length >= MAX_PATH_BYTES || bytes.includes(0)
    ? null : bytes;
}

export function compareBytesUnsigned(a, b) {
  const length = Math.min(a.length, b.length);
  for (let i = 0; i < length; i++) {
    if (a[i] !== b[i]) return a[i] - b[i];
  }
  return a.length - b.length;
}

function asBytes(value) {
  return typeof value === "string" ? encoder.encode(value) : value;
}

// Keys have one code unit per byte so even non-UTF-8 POSIX names stay distinct.
function byteString(bytes) {
  const chunks = [];
  for (let at = 0; at < bytes.length; at += 24576) {
    chunks.push(String.fromCharCode(...bytes.subarray(at, at + 24576)));
  }
  return chunks.join("");
}

function stringBytes(text) {
  return Uint8Array.from(text, (character) => character.charCodeAt(0));
}

function snapshotName(name) {
  const bytes = stringBytes(name);
  try {
    return strictDecoder.decode(bytes);
  } catch {
    // Unpaired surrogates distinguish raw names from decoded UTF-8 in snapshots.
    return Array.from(bytes, (byte) => String.fromCharCode(0xdc00 + byte)).join("");
  }
}

function parsePath(path) {
  const bytes = validatePathBytes(asBytes(path));
  if (!bytes) return null;
  const text = byteString(bytes);
  return {
    absolute: text.startsWith("/"),
    trailing: text.endsWith("/"),
    names: text.split("/").filter(Boolean),
  };
}

function directory() {
  return { type: "dir", children: new Map() };
}

function* treeEntries(root) {
  const pending = [["", root.children.entries()]];
  while (pending.length) {
    const [parent, entries] = pending.at(-1);
    const { value, done } = entries.next();
    if (done) {
      pending.pop();
      continue;
    }
    const [name, node] = value;
    const path = parent + "/" + name;
    yield [path, node];
    if (node.type === "dir") pending.push([path, node.children.entries()]);
  }
}

function serialize(root) {
  const entries = [];
  for (const [path, node] of treeEntries(root)) {
    entries.push([path, node.type === "file" ? btoa(byteString(node.data)) : null]);
  }
  return JSON.stringify(entries);
}

function deserialize(entries) {
  const root = directory();
  const parents = new Map([["", root]]);
  for (const [path, data] of entries) {
    const split = path.lastIndexOf("/");
    const parent = parents.get(path.slice(0, split));
    const name = path.slice(split + 1);
    if (!parent || !name || name === "." || name === ".." || /[^\x01-\xff]/.test(name)
        || (data !== null && typeof data !== "string") || parent.children.has(name)) {
      throw new Error("Invalid virtual filesystem snapshot");
    }
    const node = data === null ? directory() : { type: "file", data: stringBytes(atob(data)) };
    parent.children.set(name, node);
    if (node.type === "dir") parents.set(path, node);
  }
  return root;
}

function copyEntries(source, target) {
  const pending = [[source, target]];
  while (pending.length) {
    const [from, to] = pending.pop();
    for (const [name, node] of from.children) {
      if (node.type === "dir") {
        const existing = to.children.get(name);
        const child = existing?.type === "dir" ? existing : directory();
        to.children.set(name, child);
        pending.push([node, child]);
      } else {
        to.children.set(name, { type: "file", data: node.data.slice() });
      }
    }
  }
}

export class MemoryFS {
  #root = directory();
  #cwd;

  constructor(options = {}) {
    const cwd = parsePath(options.cwd ?? "/");
    this.#cwd = [];
    if (cwd) {
      for (const name of cwd.names) {
        if (name === "..") this.#cwd.pop();
        else if (name !== ".") this.#cwd.push(name);
      }
      this.#resolve({ absolute: true, names: this.#cwd }, true);
    }

    for (const path of options.dirs ?? []) {
      const parsed = parsePath(path);
      if (parsed) this.#resolve(parsed, true);
    }
    const files = options.files instanceof Map ? options.files : Object.entries(options.files ?? {});
    for (const [path, data] of files) {
      const parsed = parsePath(path);
      if (!parsed || parsed.trailing || [".", ".."].includes(parsed.names.at(-1))) continue;
      const entry = this.#resolve(parsed, false, true);
      if (entry?.parent && entry.node?.type !== "dir") {
        entry.parent.children.set(entry.name, { type: "file", data: new Uint8Array(asBytes(data)) });
      }
    }
  }

  #resolve(path, createDirs = false, createParents = false) {
    if (!path) return null;
    const names = path.absolute ? path.names : [...this.#cwd, ...path.names];
    const stack = [{ node: this.#root }];
    for (let i = 0; i < names.length; i++) {
      const name = names[i];
      const { node: parent } = stack.at(-1);
      if (parent?.type !== "dir") return null;
      if (name === ".") continue;
      if (name === "..") {
        if (stack.length > 1) stack.pop();
        continue;
      }
      let node = parent.children.get(name);
      if (!node && (createDirs || (createParents && i < names.length - 1))) {
        node = directory();
        parent.children.set(name, node);
      }
      stack.push({ node, parent, name });
    }

    const entry = stack.at(-1);
    if (path.trailing && entry.node?.type === "file") return null;
    const last = path.names.at(-1);
    return { ...entry, special: last === undefined || last === "." || last === "..", stack };
  }

  #update(...changes) {
    const previous = changes.map(([children, name]) => children.get(name));
    for (const [children, name, node] of changes) {
      if (node) children.set(name, node);
      else children.delete(name);
    }
    try {
      this._persist(this.#root);
      return true;
    } catch {
      changes.forEach(([children, name], index) => {
        const node = previous[index];
        if (node) children.set(name, node);
        else children.delete(name);
      });
      return false;
    }
  }

  _persist(_root) {}

  _restore(root) {
    this.#root = root;
  }

  _mergeFrom(root) {
    copyEntries(root, this.#root);
  }

  readFile(path) {
    const node = this.#resolve(parsePath(path))?.node;
    return node?.type === "file" ? node.data.slice() : null;
  }

  #put(path, data, append) {
    const parsed = parsePath(path);
    if (!parsed || parsed.trailing) return false;
    const entry = this.#resolve(parsed);
    if (!entry?.parent || entry.special || entry.node?.type === "dir") return false;
    const input = asBytes(data);
    const existing = append ? entry.node?.data : null;
    const bytes = new Uint8Array((existing?.length ?? 0) + input.length);
    if (existing) bytes.set(existing);
    bytes.set(input, existing?.length ?? 0);
    return this.#update([entry.parent.children, entry.name, { type: "file", data: bytes }]);
  }

  writeFile(path, data) {
    return this.#put(path, data, false);
  }

  writeFileAtomic(path, data) {
    return this.#put(path, data, false);
  }

  appendFile(path, data) {
    return this.#put(path, data, true);
  }

  fileExists(path) {
    return this.#resolve(parsePath(path))?.node?.type === "file";
  }

  removeFile(path) {
    const entry = this.#resolve(parsePath(path));
    if (entry?.node?.type !== "file") return false;
    return this.#update([entry.parent.children, entry.name]);
  }

  renameFile(from, to) {
    const source = this.#resolve(parsePath(from));
    const targetPath = parsePath(to);
    const target = this.#resolve(targetPath);
    if (!source?.node || source.special || !target?.parent || target.special || target.node?.type === "dir") {
      return false;
    }
    if (source.node === target.node) return true;
    if (source.node.type === "dir") {
      if (target.node || target.stack.some(({ node }) => node === source.node)) return false;
    } else if (targetPath.trailing) {
      return false;
    }
    return this.#update(
      [source.parent.children, source.name],
      [target.parent.children, target.name, source.node],
    );
  }

  makeDir(path) {
    const entry = this.#resolve(parsePath(path));
    if (entry?.node) return entry.node.type === "dir";
    if (!entry?.parent || entry.special) return false;
    return this.#update([entry.parent.children, entry.name, directory()]);
  }

  isDir(path) {
    return this.#resolve(parsePath(path))?.node?.type === "dir";
  }

  removeDir(path) {
    const entry = this.#resolve(parsePath(path));
    if (!entry?.parent || entry.special || entry.node?.type !== "dir" || entry.node.children.size) {
      return false;
    }
    return this.#update([entry.parent.children, entry.name]);
  }

  listDir(path) {
    const node = this.#resolve(parsePath(path))?.node;
    if (node?.type !== "dir") return null;
    return Array.from(node.children.keys())
      .filter((name) => name !== "." && name !== ".." && !name.includes("\n"))
      .map(stringBytes)
      .sort(compareBytesUnsigned);
  }

  snapshot() {
    const files = {};
    for (const [path, node] of treeEntries(this.#root)) {
      if (node.type === "file") files[path.split("/").map(snapshotName).join("/")] = node.data.slice();
    }
    return files;
  }

  readText(path) {
    const bytes = this.readFile(path);
    return bytes === null ? null : decoder.decode(bytes);
  }

  writeText(path, text) {
    return this.writeFile(path, text);
  }

  _copyTo(target) {
    const root = directory();
    copyEntries(this.#root, root);
    target._restore(root);
    return target;
  }
}

function browserStorage() {
  try {
    return globalThis.localStorage;
  } catch {
    return undefined;
  }
}

function storageKey(prefix = "goose_fs:") {
  return prefix + "snapshot";
}

export function clearStorage({ storage = browserStorage(), prefix } = {}) {
  storage?.removeItem(storageKey(prefix));
}

export class LocalStorageFS extends MemoryFS {
  #storage;
  #key;

  constructor(options = {}) {
    super(options);
    this.#storage = options.storage === undefined ? browserStorage() : options.storage;
    this.#key = storageKey(options.prefix);
    let snapshot;
    try {
      snapshot = this.#storage?.getItem(this.#key);
    } catch {
      this.#storage = undefined;
    }
    if (snapshot != null) this._restore(deserialize(JSON.parse(snapshot)));
  }

  _persist(root) {
    this.#storage?.setItem(this.#key, serialize(root));
  }

  clearStorage() {
    this.#storage?.removeItem(this.#key);
  }
}

function readAccess(handle) {
  const bytes = new Uint8Array(handle.getSize());
  let at = 0;
  while (at < bytes.length) {
    const count = handle.read(bytes.subarray(at), { at });
    if (count <= 0) throw new Error("Incomplete OPFS read");
    at += count;
  }
  return bytes;
}

async function importDirectory(handle, target, excludedName) {
  for await (const [name, child] of handle.entries()) {
    if (name === excludedName) continue;
    const key = byteString(encoder.encode(name));
    if (child.kind === "directory") {
      const node = directory();
      await importDirectory(child, node);
      target.children.set(key, node);
    } else {
      let data;
      if (typeof child.createSyncAccessHandle === "function") {
        const access = await child.createSyncAccessHandle();
        try {
          data = readAccess(access);
        } finally {
          access.close();
        }
      } else {
        data = new Uint8Array(await (await child.getFile()).arrayBuffer());
      }
      target.children.set(key, { type: "file", data });
    }
  }
}

function readSlot(handle) {
  const bytes = readAccess(handle);
  if (bytes.length === 0) return null;
  // A partially written slot is recoverable from the other slot.
  try {
    const [generation, entries] = JSON.parse(strictDecoder.decode(bytes));
    if (!Number.isSafeInteger(generation) || generation < 1 || !Array.isArray(entries)) return null;
    return { generation, root: deserialize(entries) };
  } catch {
    return null;
  }
}

export class OPFSAdapter extends MemoryFS {
  #slots = [];
  #generation = 0;

  static async open(options = {}) {
    const root = options.root ?? await globalThis.navigator.storage.getDirectory();
    const name = options.name ?? ".goose-vfs";
    const adapter = new OPFSAdapter(options);
    const store = await root.getDirectoryHandle(name, { create: true });
    try {
      for (const slot of ["0", "1"]) {
        const file = await store.getFileHandle(slot, { create: true });
        adapter.#slots.push(await file.createSyncAccessHandle());
      }
      const snapshots = adapter.#slots.map(readSlot);
      const latest = snapshots.reduce((best, slot) =>
        slot && (!best || slot.generation > best.generation) ? slot : best, null);
      if (latest) {
        adapter.#generation = latest.generation;
        adapter._restore(latest.root);
      } else {
        const initial = directory();
        await importDirectory(root, initial, name);
        // Keep configured seeds where the OPFS tree has no corresponding entry.
        adapter._mergeFrom(initial);
      }
      return adapter;
    } catch (error) {
      adapter.close();
      throw error;
    }
  }

  _persist(root) {
    if (this.#slots.length !== 2) throw new Error("OPFS adapter is closed");
    // OPFS namespace changes are asynchronous. Store the logical tree in two
    // pre-opened files so synchronous imports can commit, including renames.
    const generation = this.#generation + 1;
    const slot = this.#slots[generation % 2];
    const bytes = encoder.encode(`[${generation},${serialize(root)}]`);
    try {
      slot.truncate(0);
      let at = 0;
      while (at < bytes.length) {
        const count = slot.write(bytes.subarray(at), { at });
        if (count <= 0) throw new Error("Incomplete OPFS write");
        at += count;
      }
      slot.flush();
      this.#generation = generation;
    } catch (error) {
      // Keep the last committed slot available on a failed write.
      try {
        slot.truncate(0);
        slot.flush();
      } catch {}
      throw error;
    }
  }

  async syncToMemory(memFs = new MemoryFS()) {
    return this._copyTo(memFs);
  }

  close() {
    for (const handle of this.#slots.splice(0)) handle.close();
  }
}
