import { readFile, writeFile } from "node:fs/promises";

const file = process.argv[2];
const title = process.argv[3];
if (!file || title === undefined) {
  throw new Error("usage: set-web-title.mjs <index.html> <title>");
}

const source = await readFile(file, "utf8");
const titleTags = source.match(/<title>[^<]*<\/title>/g) ?? [];
if (titleTags.length !== 1) {
  throw new Error(`expected exactly one simple <title> in ${file}`);
}

const escaped = title
  .replaceAll("&", "&amp;")
  .replaceAll("<", "&lt;")
  .replaceAll(">", "&gt;")
  .replaceAll('"', "&quot;")
  .replaceAll("'", "&#39;");
await writeFile(file, source.replace(titleTags[0], `<title>${escaped}</title>`));
