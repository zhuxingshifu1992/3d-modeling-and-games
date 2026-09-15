import * as THREE from 'three';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';

// Blender Z-up -> the glTF export's Y-up basis. Keep source coordinates intact.
const fromBlender = (x, y, z) => new THREE.Vector3(x, z, -y);
// Documented yard envelope: Blender X [-25,25], Y [-25,31], Z [0,9].
// Offsite transmission lines remain visible but never determine camera framing.
const SITE_BOUNDS = new THREE.Box3(fromBlender(-25, 31, 0), fromBlender(25, -25, 9));
const viewport = document.getElementById('viewport');
const loadingPanel = document.getElementById('loading-panel');
const progressLabel = document.getElementById('loading-progress');
const progressFill = document.getElementById('loading-fill');
const buttons = [...document.querySelectorAll('[data-view]')];
const reducedMotion = matchMedia('(prefers-reduced-motion: reduce)').matches;
const renderer = new THREE.WebGLRenderer({ antialias: true, powerPreference: 'high-performance' });
renderer.setPixelRatio(Math.min(devicePixelRatio || 1, 1.5));
renderer.setSize(viewport.clientWidth, viewport.clientHeight);
renderer.outputColorSpace = THREE.SRGBColorSpace;
renderer.toneMapping = THREE.ACESFilmicToneMapping;
renderer.toneMappingExposure = 1.10;
renderer.shadowMap.enabled = true;
renderer.shadowMap.type = THREE.PCFSoftShadowMap;
viewport.appendChild(renderer.domElement);

const scene = new THREE.Scene();
scene.background = new THREE.Color('#bcc7c7');
scene.fog = new THREE.Fog(scene.background, 110, 310);
const camera = new THREE.PerspectiveCamera(43, viewport.clientWidth / viewport.clientHeight, .08, 500);
camera.position.copy(fromBlender(44, -59, 38));
const controls = new OrbitControls(camera, renderer.domElement);
controls.enableDamping = true;
controls.dampingFactor = .085;
controls.target.copy(fromBlender(0, 3, 2));
controls.minDistance = 1.5;
controls.maxDistance = 170;
controls.maxPolarAngle = Math.PI * .493;
controls.zoomSpeed = .8;
controls.panSpeed = .75;
controls.screenSpacePanning = true;
controls.update();

// A compact generated sky provides readable metallic reflections offline.
// This is lighting data, independent of any model photo or downloaded HDRI.
function makeEnvironment() {
  const width = 256, height = 128;
  const data = new Float32Array(width * height * 4);
  const sky = new THREE.Color('#c9dde4');
  const horizon = new THREE.Color('#e6dfc8');
  const earth = new THREE.Color('#8e9388');
  const colour = new THREE.Color();
  for (let y = 0; y < height; y++) {
    // DataTexture row zero samples v=0, the bottom of an equirectangular sky.
    const v = 1 - y / (height - 1);
    colour.copy(v < .5 ? sky : horizon).lerp(v < .5 ? horizon : earth, v < .5 ? v * 2 : (v - .5) * 2);
    for (let x = 0; x < width; x++) {
      const u = x / width;
      const sun = Math.exp(-((u - .18) ** 2 / .003 + (v - .26) ** 2 / .012)) * 1.1;
      const i = (y * width + x) * 4;
      data[i] = colour.r + sun;
      data[i + 1] = colour.g + sun * .82;
      data[i + 2] = colour.b + sun * .61;
      data[i + 3] = 1;
    }
  }
  const map = new THREE.DataTexture(data, width, height, THREE.RGBAFormat, THREE.FloatType);
  map.mapping = THREE.EquirectangularReflectionMapping;
  map.needsUpdate = true;
  const pmrem = new THREE.PMREMGenerator(renderer);
  const result = pmrem.fromEquirectangular(map);
  map.dispose();
  pmrem.dispose();
  return result;
}
const environment = makeEnvironment();
scene.environment = environment.texture;
scene.environmentIntensity = .80;
scene.add(new THREE.HemisphereLight(0xe3eff6, 0x777365, 1.40));
const sun = new THREE.DirectionalLight(0xffe5b9, 3.20);
sun.position.copy(fromBlender(-26, -20, 42));
sun.castShadow = true;
sun.shadow.mapSize.set(2048, 2048);
sun.shadow.bias = -.00015;
sun.shadow.normalBias = .035;
sun.shadow.radius = 2;
scene.add(sun, sun.target);

let dirty = true;
let loaded = false;
let transition = null;
let overview = null;
let bounds = null;
const presets = {
  entrance: { position: fromBlender(23, -33, 12), target: fromBlender(2, -2, 2.4) },
  charging: { position: fromBlender(9, -11, 9), target: fromBlender(-7.5, 5.5, 1.8) },
  trucks: { position: fromBlender(24, -1, 10), target: fromBlender(11.7, 12.5, 2.1) },
};
controls.addEventListener('change', () => { dirty = true; });
controls.addEventListener('start', () => { transition = null; });

function computeModelBounds(root) {
  const result = new THREE.Box3();
  const local = new THREE.Box3();
  root.updateMatrixWorld(true);
  root.traverse((object) => {
    if (!object.isMesh) return;
    for (let ancestor = object; ancestor; ancestor = ancestor.parent) {
      if (!ancestor.visible || /utilities|horizon|backdrop|distant|offsite/i.test(ancestor.name)) return;
    }
    object.geometry.computeBoundingBox();
    local.copy(object.geometry.boundingBox).applyMatrix4(object.matrixWorld);
    local.intersect(SITE_BOUNDS);
    if (local.isEmpty()) return;
    result.union(local);
  });
  if (result.isEmpty()) throw Object.assign(new Error('The GLB contains no visible geometry.'), { userMessage: '模型中没有可见几何体，请重新导出 GLB 后载入。' });
  return result;
}

function fitOverview() {
  const target = fromBlender(0, 4, 1.7);
  const direction = fromBlender(33, -43, 27).sub(target).normalize();
  const right = new THREE.Vector3(0, 1, 0).cross(direction).normalize();
  const up = direction.clone().cross(right).normalize();
  const vertical = THREE.MathUtils.degToRad(camera.fov);
  const tanVertical = Math.tan(vertical / 2);
  const tanHorizontal = tanVertical * camera.aspect;
  let distance = 0;
  // Fit the eight actual yard corners instead of an oversized bounding sphere.
  // 0.86 leaves a little room for the title and camera controls on all aspect ratios.
  for (const x of [bounds.min.x, bounds.max.x]) {
    for (const y of [bounds.min.y, bounds.max.y]) {
      for (const z of [bounds.min.z, bounds.max.z]) {
        const corner = new THREE.Vector3(x, y, z).sub(target);
        const depth = corner.dot(direction);
        distance = Math.max(distance,
          depth + Math.abs(corner.dot(right)) / (tanHorizontal * .86),
          depth + Math.abs(corner.dot(up)) / (tanVertical * .86));
      }
    }
  }
  return { target, position: target.clone().addScaledVector(direction, distance) };
}

function setView(name, immediate = false) {
  if (!loaded) return;
  const view = name === 'overview' ? overview : presets[name];
  if (!view) return;
  for (const button of buttons) button.setAttribute('aria-pressed', String(button.dataset.view === name));
  if (immediate || reducedMotion) {
    transition = null;
    camera.position.copy(view.position);
    controls.target.copy(view.target);
    controls.update();
  } else {
    transition = {
      started: performance.now(),
      position: camera.position.clone(), target: controls.target.clone(),
      nextPosition: view.position.clone(), nextTarget: view.target.clone(),
    };
  }
  dirty = true;
}
for (const button of buttons) button.addEventListener('click', () => setView(button.dataset.view));

function finishScene(gltf) {
  const root = gltf.scene;
  bounds = computeModelBounds(root);
  const size = bounds.getSize(new THREE.Vector3());
  const center = bounds.getCenter(new THREE.Vector3());
  const anisotropy = Math.min(4, renderer.capabilities.getMaxAnisotropy());
  root.traverse((object) => {
    if (object.isLight) object.visible = false; // Consistent inspection lighting.
    if (!object.isMesh) return;
    object.castShadow = true;
    object.receiveShadow = true;
    const materials = Array.isArray(object.material) ? object.material : [object.material];
    for (const material of materials) {
      for (const key of ['map', 'normalMap', 'roughnessMap', 'metalnessMap']) {
        if (material[key]) material[key].anisotropy = anisotropy;
      }
    }
  });
  scene.add(root);

  // Extend subdued soil beyond the camera far plane; no pale square border.
  // Fog merges this floor into the background before the clipping horizon.
  const floor = new THREE.Mesh(new THREE.PlaneGeometry(2400, 2400), new THREE.MeshStandardMaterial({ color: '#686b5e', roughness: 1 }));
  floor.name = 'Viewer ground';
  floor.rotation.x = -Math.PI / 2;
  floor.position.set(center.x, bounds.min.y - .035, center.z);
  floor.receiveShadow = true;
  scene.add(floor);

  const extent = Math.max(size.x, size.z) * .68;
  Object.assign(sun.shadow.camera, { left: -extent, right: extent, top: extent, bottom: -extent, near: 1, far: 145 });
  sun.target.position.set(center.x, bounds.min.y, center.z);
  sun.shadow.camera.updateProjectionMatrix();
  sun.shadow.needsUpdate = true;
  renderer.shadowMap.autoUpdate = false;
  renderer.shadowMap.needsUpdate = true;
  camera.far = Math.max(300, size.length() * 8);
  camera.updateProjectionMatrix();
  controls.maxDistance = Math.max(140, size.length() * 2.8);
  overview = fitOverview();
  loaded = true;
  for (const button of buttons) button.disabled = false;
  setView('overview', true);
  loadingPanel.hidden = true;
  loadingPanel.setAttribute('aria-busy', 'false');
  document.getElementById('scene-status').textContent = '模型已就绪';
  dirty = true;
}

const modelURL = new URL('../exports/废土充电场.glb', import.meta.url).href;
const loader = new GLTFLoader();
loader.load(modelURL, (gltf) => {
  try { finishScene(gltf); } catch (error) { window.showViewerError(error); }
}, (event) => {
  if (event.lengthComputable && event.total > 0) {
    const percent = Math.min(100, Math.round(event.loaded / event.total * 100));
    progressFill.style.width = `${Math.max(3, percent)}%`;
    progressLabel.textContent = percent < 100 ? `${percent}%` : '正在整理场景…';
    if (percent === 100) document.getElementById('loading-message').textContent = '模型读取完成，正在准备材质与几何体。';
  } else if (event.loaded) {
    progressLabel.textContent = `已读取 ${(event.loaded / 1048576).toFixed(1)} MB`;
    progressFill.style.width = '35%';
  }
}, (error) => {
  const status = error?.target?.status || error?.status;
  if (status === 404 || String(error?.message).includes('404')) error.userMessage = '找不到 exports/废土充电场.glb。请先生成模型，再重新载入。';
  window.showViewerError(error);
});

new ResizeObserver(() => {
  const width = viewport.clientWidth, height = viewport.clientHeight;
  if (!width || !height) return;
  camera.aspect = width / height;
  camera.updateProjectionMatrix();
  renderer.setPixelRatio(Math.min(devicePixelRatio || 1, 1.5));
  renderer.setSize(width, height);
  if (loaded) overview = fitOverview();
  dirty = true;
}).observe(viewport);

renderer.domElement.addEventListener('webglcontextlost', (event) => {
  event.preventDefault();
  window.showViewerError({ userMessage: '浏览器的三维显示暂时中断。请关闭其他占用显卡的页面后重新载入。' });
});
document.addEventListener('visibilitychange', () => { dirty = true; });
renderer.setAnimationLoop((now) => {
  if (document.hidden) return;
  if (transition) {
    const t = Math.min(1, (now - transition.started) / 720);
    const smooth = t * t * (3 - 2 * t);
    camera.position.lerpVectors(transition.position, transition.nextPosition, smooth);
    controls.target.lerpVectors(transition.target, transition.nextTarget, smooth);
    dirty = true;
    if (t === 1) transition = null;
  }
  controls.update();
  if (dirty) {
    renderer.render(scene, camera);
    dirty = false;
  }
});
