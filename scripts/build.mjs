// Build step: self-host the fonts and make pptxgenjs's ESM build loadable on Vercel.
import { mkdirSync, copyFileSync, existsSync, readFileSync, writeFileSync } from "node:fs";

// 1) Fonts (Amiri for documents, Cairo for the interface) copied from npm packages into public/fonts.
const files = [
  ["amiri", "amiri-arabic-400-normal.woff2"], ["amiri", "amiri-arabic-700-normal.woff2"],
  ["amiri", "amiri-latin-400-normal.woff2"], ["amiri", "amiri-latin-700-normal.woff2"],
  ["cairo", "cairo-arabic-400-normal.woff2"], ["cairo", "cairo-latin-400-normal.woff2"],
  ["cairo", "cairo-arabic-600-normal.woff2"], ["cairo", "cairo-latin-600-normal.woff2"],
  ["cairo", "cairo-arabic-700-normal.woff2"], ["cairo", "cairo-latin-700-normal.woff2"],
];
mkdirSync("public/fonts", { recursive: true });
for (const [pkg, f] of files) if (!existsSync(`public/fonts/${f}`)) copyFileSync(`node_modules/@fontsource/${pkg}/files/${f}`, `public/fonts/${f}`);

// 2) pptxgenjs ships its ES module as plain .js without "type": "module"; the serverless runtime then
//    loads it as CommonJS and crashes. Marking the package as ESM fixes the import (its CJS build is unused).
const pkgPath = "node_modules/pptxgenjs/package.json";
const pkg = JSON.parse(readFileSync(pkgPath, "utf8"));
if (pkg.type !== "module") {
  pkg.type = "module";
  pkg.exports = { ".": { types: "./types/index.d.ts", import: "./dist/pptxgen.es.js", default: "./dist/pptxgen.es.js" } };
  writeFileSync(pkgPath, JSON.stringify(pkg, null, 2));
}
console.log("build ready");
