// Animated 3D university scene behind the whole site: a classical faculty building with a dome and columns,
// floating graduation caps and books, and drifting gold particles. The camera glides with page scroll and
// follows the pointer; everything keeps moving slowly over time. Pauses when hidden, respects reduced motion.
import {
  WebGLRenderer, Scene, PerspectiveCamera, Color, Fog, HemisphereLight, DirectionalLight, AmbientLight,
  Group, Mesh, BoxGeometry, CylinderGeometry, SphereGeometry, PlaneGeometry, ExtrudeGeometry, Shape,
  MeshStandardMaterial, MeshBasicMaterial, BufferGeometry, Float32BufferAttribute, Points, PointsMaterial,
  CircleGeometry, TorusGeometry, MathUtils, AdditiveBlending, SRGBColorSpace,
} from "three";

const canvas = document.getElementById("bg3d");
const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;
const mobile = matchMedia("(max-width: 700px)").matches;

function supported() {
  try { const c = document.createElement("canvas"); return !!(c.getContext("webgl2") || c.getContext("webgl")); } catch { return false; }
}

if (canvas && supported()) start();

function start() {
  const renderer = new WebGLRenderer({ canvas, antialias: !mobile, alpha: true, powerPreference: "low-power" });
  renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, mobile ? 1.25 : 1.75));
  renderer.outputColorSpace = SRGBColorSpace;
  renderer.shadowMap.enabled = false;

  const BG = new Color("#f5f2ec");
  const scene = new Scene();
  scene.fog = new Fog(BG, 26, 70);

  const camera = new PerspectiveCamera(42, 1, 0.1, 200);

  // Light: warm sun + sky fill, like late afternoon on campus.
  scene.add(new HemisphereLight("#fff8ec", "#c9c1b0", 1.15));
  scene.add(new AmbientLight("#ffffff", 0.25));
  const sun = new DirectionalLight("#ffe2b8", 1.6);
  sun.position.set(-12, 18, 10);
  scene.add(sun);

  const stone = new MeshStandardMaterial({ color: "#efe7d6", roughness: 0.85 });
  const stoneDark = new MeshStandardMaterial({ color: "#d9cdb4", roughness: 0.9 });
  const navy = new MeshStandardMaterial({ color: "#1f2a44", roughness: 0.55, metalness: 0.15 });
  const gold = new MeshStandardMaterial({ color: "#c8a364", roughness: 0.35, metalness: 0.65 });
  const glass = new MeshStandardMaterial({ color: "#2d3b5e", roughness: 0.2, metalness: 0.4, transparent: true, opacity: 0.85 });

  // ---------- Ground: a soft circular plaza with rings ----------
  const ground = new Mesh(new CircleGeometry(60, 64), new MeshStandardMaterial({ color: "#e8e1d3", roughness: 1 }));
  ground.rotation.x = -Math.PI / 2;
  scene.add(ground);
  for (const r of [9, 13, 18]) {
    const ring = new Mesh(new TorusGeometry(r, 0.05, 6, 96), new MeshBasicMaterial({ color: "#d6c9ad" }));
    ring.rotation.x = -Math.PI / 2; ring.position.y = 0.02;
    scene.add(ring);
  }

  // ---------- The faculty building ----------
  const uni = new Group();
  scene.add(uni);
  // Stepped podium
  for (let i = 0; i < 4; i++) {
    const step = new Mesh(new BoxGeometry(16 - i * 0.6, 0.35, 8 - i * 0.6), i % 2 ? stone : stoneDark);
    step.position.y = 0.175 + i * 0.35;
    uni.add(step);
  }
  const base = 1.4;
  // Main hall behind the colonnade
  const hall = new Mesh(new BoxGeometry(13, 5.2, 5), stone);
  hall.position.set(0, base + 2.6, -0.9);
  uni.add(hall);
  // Windows on the hall (two rows)
  for (let row = 0; row < 2; row++) for (let i = -5; i <= 5; i += 1.25) {
    const w = new Mesh(new BoxGeometry(0.55, 1.1, 0.08), glass);
    w.position.set(i, base + 1.6 + row * 2, 1.62);
    uni.add(w);
  }
  // Colonnade
  const colGeo = new CylinderGeometry(0.28, 0.32, 4.6, 14);
  const capGeo = new BoxGeometry(0.85, 0.22, 0.85);
  for (let i = 0; i < 8; i++) {
    const x = -5.6 + i * 1.6;
    const col = new Mesh(colGeo, stone);
    col.position.set(x, base + 2.3, 2.3);
    uni.add(col);
    const top = new Mesh(capGeo, stoneDark); top.position.set(x, base + 4.7, 2.3); uni.add(top);
    const foot = new Mesh(capGeo, stoneDark); foot.position.set(x, base + 0.11, 2.3); uni.add(foot);
  }
  // Entablature
  const beam = new Mesh(new BoxGeometry(13.6, 0.7, 1.4), stoneDark);
  beam.position.set(0, base + 5.15, 2.2);
  uni.add(beam);
  const band = new Mesh(new BoxGeometry(13.62, 0.18, 1.42), navy);
  band.position.set(0, base + 5.1, 2.2);
  uni.add(band);
  // Pediment (triangular gable)
  const tri = new Shape();
  tri.moveTo(-6.8, 0); tri.lineTo(6.8, 0); tri.lineTo(0, 2.1); tri.lineTo(-6.8, 0);
  const ped = new Mesh(new ExtrudeGeometry(tri, { depth: 1.4, bevelEnabled: false }), stone);
  ped.position.set(0, base + 5.5, 1.5);
  uni.add(ped);
  // Gold medallion on the gable
  const medal = new Mesh(new CylinderGeometry(0.45, 0.45, 0.12, 32), gold);
  medal.rotation.x = Math.PI / 2; medal.position.set(0, base + 6.25, 2.95);
  uni.add(medal);
  // Drum + dome + lantern
  const drum = new Mesh(new CylinderGeometry(2.4, 2.6, 1.6, 40), stone);
  drum.position.set(0, base + 6.1, -0.9);
  uni.add(drum);
  for (let i = 0; i < 16; i++) {
    const a = (i / 16) * Math.PI * 2;
    const p = new Mesh(new BoxGeometry(0.18, 1.2, 0.18), stoneDark);
    p.position.set(Math.cos(a) * 2.55, base + 6.1, -0.9 + Math.sin(a) * 2.55);
    uni.add(p);
  }
  const dome = new Mesh(new SphereGeometry(2.4, 40, 20, 0, Math.PI * 2, 0, Math.PI / 2), navy);
  dome.position.set(0, base + 6.9, -0.9);
  uni.add(dome);
  const lantern = new Mesh(new CylinderGeometry(0.35, 0.4, 0.9, 16), gold);
  lantern.position.set(0, base + 9.6, -0.9);
  uni.add(lantern);
  const spire = new Mesh(new SphereGeometry(0.22, 16, 12), gold);
  spire.position.set(0, base + 10.2, -0.9);
  uni.add(spire);
  // Side wings
  for (const s of [-1, 1]) {
    const wing = new Mesh(new BoxGeometry(5, 3.6, 4.2), stone);
    wing.position.set(s * 9.6, base + 0.4, -1.2);
    uni.add(wing);
    const roof = new Mesh(new BoxGeometry(5.3, 0.35, 4.5), navy);
    roof.position.set(s * 9.6, base + 2.35, -1.2);
    uni.add(roof);
    for (let i = -1.6; i <= 1.6; i += 0.8) {
      const w = new Mesh(new BoxGeometry(0.42, 0.9, 0.08), glass);
      w.position.set(s * 9.6 + i, base + 0.6, 0.92);
      uni.add(w);
    }
  }
  // A few trees on the plaza
  const leaf = new MeshStandardMaterial({ color: "#7d9a6a", roughness: 0.9 });
  const trunk = new MeshStandardMaterial({ color: "#8a6e4b", roughness: 1 });
  for (const [x, z] of [[-14, 4], [14, 4], [-17, -4], [17, -4], [-11, 8], [11, 8]]) {
    const t = new Mesh(new CylinderGeometry(0.15, 0.2, 1.4, 8), trunk); t.position.set(x, 0.7, z); scene.add(t);
    const c = new Mesh(new SphereGeometry(1.1, 14, 10), leaf); c.position.set(x, 2.1, z); c.scale.y = 1.2; scene.add(c);
  }

  // ---------- Floating graduation caps & books ----------
  const floaters = [];
  function gradCap() {
    const g = new Group();
    const board = new Mesh(new BoxGeometry(1.5, 0.08, 1.5), navy); g.add(board);
    const crown = new Mesh(new CylinderGeometry(0.5, 0.55, 0.5, 20), navy); crown.position.y = -0.28; g.add(crown);
    const button = new Mesh(new CylinderGeometry(0.08, 0.08, 0.06, 10), gold); button.position.y = 0.07; g.add(button);
    const cord = new Mesh(new BoxGeometry(0.04, 0.04, 0.75), gold); cord.position.set(0.35, 0.06, 0.35); cord.rotation.y = Math.PI / 4; g.add(cord);
    const tassel = new Mesh(new CylinderGeometry(0.06, 0.09, 0.45, 8), gold); tassel.position.set(0.66, -0.17, 0.66); g.add(tassel);
    return g;
  }
  const bookColors = ["#7a2232", "#1f4e79", "#2f6b4f", "#c8a364", "#3b3f5c"];
  function book(i) {
    const g = new Group();
    const cover = new Mesh(new BoxGeometry(1.1, 0.26, 1.5), new MeshStandardMaterial({ color: bookColors[i % bookColors.length], roughness: 0.6 }));
    const pages = new Mesh(new BoxGeometry(1.0, 0.2, 1.42), new MeshStandardMaterial({ color: "#fbf8f1", roughness: 0.9 }));
    pages.position.x = 0.06;
    g.add(cover, pages);
    return g;
  }
  const count = mobile ? 10 : 18;
  for (let i = 0; i < count; i++) {
    const obj = i % 3 === 0 ? book(i) : gradCap();
    const a = (i / count) * Math.PI * 2;
    const radius = 10 + (i % 4) * 3.2;
    obj.userData = { a, radius, h: 4 + (i % 5) * 1.6, speed: 0.04 + (i % 7) * 0.008, spin: 0.2 + (i % 5) * 0.12, bob: Math.random() * Math.PI * 2 };
    obj.scale.setScalar(i % 3 === 0 ? 0.9 : 0.75);
    scene.add(obj);
    floaters.push(obj);
  }

  // ---------- Gold dust ----------
  const n = mobile ? 350 : 800;
  const pos = new Float32Array(n * 3);
  for (let i = 0; i < n; i++) {
    const r = 6 + Math.random() * 34, a = Math.random() * Math.PI * 2;
    pos[i * 3] = Math.cos(a) * r; pos[i * 3 + 1] = Math.random() * 18; pos[i * 3 + 2] = Math.sin(a) * r;
  }
  const dustGeo = new BufferGeometry();
  dustGeo.setAttribute("position", new Float32BufferAttribute(pos, 3));
  const dust = new Points(dustGeo, new PointsMaterial({ color: "#c8a364", size: mobile ? 0.09 : 0.07, transparent: true, opacity: 0.75, depthWrite: false, blending: AdditiveBlending }));
  scene.add(dust);

  // ---------- Camera motion: scroll + pointer + time ----------
  let scrollT = 0, targetScroll = 0, px = 0, py = 0, tx = 0, ty = 0;
  const readScroll = () => {
    const max = Math.max(1, document.documentElement.scrollHeight - innerHeight);
    targetScroll = Math.min(1, scrollY / max);
  };
  addEventListener("scroll", readScroll, { passive: true });
  addEventListener("pointermove", (e) => { tx = (e.clientX / innerWidth) * 2 - 1; ty = (e.clientY / innerHeight) * 2 - 1; }, { passive: true });
  if (window.DeviceOrientationEvent && mobile) {
    addEventListener("deviceorientation", (e) => { if (e.gamma != null) { tx = MathUtils.clamp(e.gamma / 30, -1, 1); ty = MathUtils.clamp((e.beta - 45) / 30, -1, 1); } }, { passive: true });
  }

  function resize() {
    const w = innerWidth, h = innerHeight;
    renderer.setSize(w, h, false);
    camera.aspect = w / h;
    camera.fov = w < 700 ? 55 : 42;
    camera.updateProjectionMatrix();
  }
  addEventListener("resize", resize);
  resize();
  readScroll();

  let running = true, last = performance.now(), time = 0;
  document.addEventListener("visibilitychange", () => {
    running = !document.hidden;
    if (running) { last = performance.now(); requestAnimationFrame(frame); }
  });

  function frame(now) {
    if (!running) return;
    const dt = Math.min(0.05, (now - last) / 1000);
    last = now;
    time += reduce ? dt * 0.15 : dt;
    scrollT += (targetScroll - scrollT) * 0.06;
    px += (tx - px) * 0.04; py += (ty - py) * 0.04;

    // Orbit around the building as the page scrolls, rising and closing in; slow drift over time.
    const orbit = -0.55 + scrollT * 1.6 + Math.sin(time * 0.05) * 0.12 + px * 0.18;
    const narrow = camera.aspect < 1 ? 1.7 : 1; // portrait phones: step back so the whole campus fits
    const dist = (30 - scrollT * 9) * narrow;
    const height = (7 + scrollT * 7) * (narrow > 1 ? 1.35 : 1) - py * 1.5;
    camera.position.set(Math.sin(orbit) * dist, height, Math.cos(orbit) * dist);
    camera.lookAt(0, 4.2 + scrollT * 1.5 - (narrow > 1 ? 12 : 0), 0);
    scene.fog.near = dist - 6; scene.fog.far = dist + 42;

    uni.rotation.y = Math.sin(time * 0.08) * 0.04;
    lantern.rotation.y = time * 0.6;
    medal.rotation.z = time * 0.4;
    for (const o of floaters) {
      const u = o.userData;
      const a = u.a + time * u.speed;
      o.position.set(Math.cos(a) * u.radius, u.h + Math.sin(time * 0.9 + u.bob) * 0.6, Math.sin(a) * u.radius);
      o.rotation.y = time * u.spin;
      o.rotation.x = Math.sin(time * 0.7 + u.bob) * 0.25;
      o.rotation.z = Math.cos(time * 0.5 + u.bob) * 0.15;
    }
    dust.rotation.y = time * 0.02;
    dust.position.y = Math.sin(time * 0.3) * 0.4;

    renderer.render(scene, camera);
    requestAnimationFrame(frame);
  }
  requestAnimationFrame(frame);
  document.documentElement.classList.add("has-3d");
}
