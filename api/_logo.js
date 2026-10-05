// Logo processing: strip a plain background (flood fill from the edges), trim, and normalise to PNG.
import sharp from "sharp";

/**
 * Makes the outer background transparent when it is a near-uniform colour (white sheets, scans, JPG logos).
 * Only pixels connected to the image border and close to the corner colour are removed, so white parts
 * inside the emblem stay intact.
 */
export async function removeBackground(input) {
  const img = sharp(input, { limitInputPixels: 40_000_000 }).rotate().resize({ width: 900, height: 900, fit: "inside", withoutEnlargement: true }).ensureAlpha();
  const { data, info } = await img.raw().toBuffer({ resolveWithObject: true });
  const { width: w, height: h } = info;
  const px = (i) => [data[i * 4], data[i * 4 + 1], data[i * 4 + 2], data[i * 4 + 3]];
  const corners = [0, w - 1, (h - 1) * w, h * w - 1].map(px);
  // Already transparent background → nothing to do.
  if (corners.every((c) => c[3] < 20)) return sharp(data, { raw: info }).trim().png().toBuffer({ resolveWithObject: true });
  const bg = corners.filter((c) => c[3] > 200);
  const ref = bg.length ? bg.reduce((a, c) => a.map((v, k) => v + c[k] / bg.length), [0, 0, 0, 0]) : [255, 255, 255, 255];
  const similar = (i) => {
    const o = i * 4;
    return Math.abs(data[o] - ref[0]) + Math.abs(data[o + 1] - ref[1]) + Math.abs(data[o + 2] - ref[2]) < 60;
  };
  // Corners must agree on one background colour, otherwise it is a photo — leave it alone.
  const agree = corners.every((c) => Math.abs(c[0] - ref[0]) + Math.abs(c[1] - ref[1]) + Math.abs(c[2] - ref[2]) < 60);
  if (agree) {
    const seen = new Uint8Array(w * h);
    const stack = [];
    for (let x = 0; x < w; x++) stack.push(x, (h - 1) * w + x);
    for (let y = 0; y < h; y++) stack.push(y * w, y * w + w - 1);
    while (stack.length) {
      const i = stack.pop();
      if (seen[i] || !similar(i)) continue;
      seen[i] = 1;
      data[i * 4 + 3] = 0;
      const x = i % w, y = (i / w) | 0;
      if (x > 0) stack.push(i - 1); if (x < w - 1) stack.push(i + 1);
      if (y > 0) stack.push(i - w); if (y < h - 1) stack.push(i + w);
    }
  }
  return sharp(data, { raw: info }).trim({ threshold: 5 }).png({ compressionLevel: 9 }).toBuffer({ resolveWithObject: true });
}
