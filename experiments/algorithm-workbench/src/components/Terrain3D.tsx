import { useEffect, useRef, useState } from "react";
import * as THREE from "three";
import { OrbitControls } from "three/addons/controls/OrbitControls.js";
import { type TerrainDataset } from "../terrain/types";
import {
  terrainPositions,
  cellColor,
  projectUnits,
  groundHeight,
  projectedPoint,
  clippedSegment,
} from "../terrain/sceneData";
import {
  createUnitGeometry,
  disposeObject,
} from "../presentation/unitGeometry";
import { type Scenario, type Snapshot } from "../core/types";

interface Context {
  scene: THREE.Scene;
  camera: THREE.PerspectiveCamera;
  renderer: THREE.WebGLRenderer;
  controls: OrbitControls;
  units: THREE.Group;
  terrain: THREE.Mesh;
  reset: () => void;
  targets: Map<string, THREE.Vector3>;
  meshes: Map<string, THREE.Group>;
}
export function Terrain3D({
  terrain,
  level,
  snapshot,
  scenario,
  onSelectCell,
  onSelectEntity,
}: {
  terrain: TerrainDataset;
  level: 5 | 25 | 50;
  snapshot: Snapshot;
  scenario: Scenario;
  onSelectCell: (n: number) => void;
  onSelectEntity: (id: string) => void;
}) {
  const host = useRef<HTMLDivElement>(null),
    context = useRef<Context | null>(null),
    callbacks = useRef({ onSelectCell, onSelectEntity }),
    interpolation = useRef(false);
  const [error, setError] = useState(""),
    [exaggeration, setExaggeration] = useState(10),
    [smooth, setSmooth] = useState(false),
    [picked, setPicked] = useState("");
  callbacks.current = { onSelectCell, onSelectEntity };
  interpolation.current = smooth;
  const projected = projectUnits(terrain, scenario, snapshot.entities);
  useEffect(() => {
    if (!host.current) return;
    setError("");
    const container = host.current;
    let renderer: THREE.WebGLRenderer;
    try {
      renderer = new THREE.WebGLRenderer({ antialias: true, alpha: false });
    } catch (e) {
      setError(
        `WebGL不可用：${e instanceof Error ? e.message : e}；可返回平面检查。`,
      );
      return;
    }
    renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
    renderer.setClearColor(0xf5f8fa);
    renderer.domElement.setAttribute("aria-label", "同源地形立体视图");
    renderer.domElement.setAttribute("role", "img");
    container.appendChild(renderer.domElement);
    const scene = new THREE.Scene(),
      camera = new THREE.PerspectiveCamera(42, 1, 0.1, 3000),
      controls = new OrbitControls(camera, renderer.domElement);
    controls.enableDamping = true;
    controls.target.set(250, 0, -250);
    controls.minDistance = 20;
    controls.maxDistance = 1600;
    controls.maxPolarAngle = Math.PI * 0.49;
    const reset = () => {
      camera.position.set(660, 470, 400);
      controls.target.set(250, 0, -250);
      controls.update();
    };
    reset();
    scene.add(new THREE.HemisphereLight(0xffffff, 0xc4cbd2, 2));
    const light = new THREE.DirectionalLight(0xffffff, 2);
    light.position.set(-200, 600, 300);
    scene.add(light);
    const data = terrainPositions(terrain, level, exaggeration),
      geometry = new THREE.BufferGeometry();
    geometry.setAttribute(
      "position",
      new THREE.BufferAttribute(data.positions, 3),
    );
    const colors: number[] = [];
    for (const c of data.grid.cells) {
      const color = new THREE.Color(cellColor(c));
      for (let i = 0; i < 6; i++) colors.push(color.r, color.g, color.b);
    }
    geometry.setAttribute("color", new THREE.Float32BufferAttribute(colors, 3));
    geometry.computeVertexNormals();
    const surface = new THREE.Mesh(
      geometry,
      new THREE.MeshStandardMaterial({
        vertexColors: true,
        side: THREE.DoubleSide,
        roughness: 1,
      }),
    );
    scene.add(surface);
    const grid = new THREE.GridHelper(500, data.grid.width, 0x92a6b6, 0xc4d0d9);
    grid.position.set(250, 0.15, -250);
    scene.add(grid);
    for (const river of terrain.rivers) {
      const segments = river.coordinates
        .slice(1)
        .flatMap((point, i) =>
          clippedSegment(terrain, river.coordinates[i], point),
        );
      const points = segments.map(([x, y]) => {
        const p = projectedPoint(terrain, x, y)!;
        return new THREE.Vector3(
          p.eastKm,
          ((groundHeight(terrain, x, y) ?? 0) / 1000) * exaggeration + 1,
          -p.northKm,
        );
      });
      const line = new THREE.LineSegments(
        new THREE.BufferGeometry().setFromPoints(points),
        new THREE.LineBasicMaterial({ color: 0x397e9d }),
      );
      line.userData.riverId = river.id;
      scene.add(line);
    }
    for (const city of terrain.cities) {
      const p = projectedPoint(terrain, city.x, city.y);
      if (!p) continue;
      const marker = new THREE.Mesh(
        new THREE.CylinderGeometry(1.5, 1.5, 2, 8),
        new THREE.MeshStandardMaterial({ color: 0x6b5748 }),
      );
      marker.position.set(
        p.eastKm,
        ((groundHeight(terrain, city.x, city.y) ?? 0) / 1000) * exaggeration +
          1,
        -p.northKm,
      );
      scene.add(marker);
    }
    const units = new THREE.Group();
    scene.add(units);
    const value: Context = {
      scene,
      camera,
      renderer,
      controls,
      units,
      terrain: surface,
      reset,
      targets: new Map(),
      meshes: new Map(),
    };
    context.current = value;
    const resize = () => {
      const width = Math.max(200, container.clientWidth),
        height = 400;
      renderer.setSize(width, height);
      camera.aspect = width / height;
      camera.updateProjectionMatrix();
    };
    const observer = new ResizeObserver(resize);
    observer.observe(container);
    resize();
    const ray = new THREE.Raycaster(),
      mouse = new THREE.Vector2();
    let down: { x: number; y: number } | null = null;
    const pointerDown = (e: PointerEvent) => {
      down = { x: e.clientX, y: e.clientY };
    };
    const pointerUp = (e: PointerEvent) => {
      if (!down || Math.hypot(e.clientX - down.x, e.clientY - down.y) > 4)
        return;
      const rect = renderer.domElement.getBoundingClientRect();
      mouse.set(
        ((e.clientX - rect.left) / rect.width) * 2 - 1,
        (-(e.clientY - rect.top) / rect.height) * 2 + 1,
      );
      ray.setFromCamera(mouse, camera);
      const hit = ray.intersectObjects([...units.children, surface], true)[0];
      if (!hit) return;
      const id = hit.object.userData.entityId;
      if (id) {
        callbacks.current.onSelectEntity(id);
        setPicked(`单位 ${id} · 已选择事件追踪`);
      } else if (hit.faceIndex != null) {
        const index = data.cellIndices[hit.faceIndex];
        callbacks.current.onSelectCell(index);
        const cell = data.grid.cells[index];
        setPicked(
          `格 ${cell.col},${cell.row} · 源样本均值 ${cell.meanHeight ?? "未知"} m`,
        );
      }
    };
    renderer.domElement.addEventListener("pointerdown", pointerDown);
    renderer.domElement.addEventListener("pointerup", pointerUp);
    let frame = 0;
    const animate = () => {
      frame = requestAnimationFrame(animate);
      controls.update();
      for (const [id, mesh] of value.meshes) {
        const target = value.targets.get(id)!;
        if (interpolation.current) mesh.position.lerp(target, 0.22);
        else mesh.position.copy(target);
      }
      renderer.render(scene, camera);
    };
    animate();
    return () => {
      cancelAnimationFrame(frame);
      observer.disconnect();
      renderer.domElement.removeEventListener("pointerdown", pointerDown);
      renderer.domElement.removeEventListener("pointerup", pointerUp);
      controls.dispose();
      disposeObject(scene);
      renderer.dispose();
      renderer.forceContextLoss();
      renderer.domElement.remove();
      context.current = null;
    };
  }, [terrain, level, exaggeration]);
  useEffect(() => {
    const c = context.current;
    if (!c) return;
    const positions = projectUnits(terrain, scenario, snapshot.entities),
      present = new Set(positions.map((p) => p.entity.id));
    for (const [id, mesh] of c.meshes)
      if (!present.has(id)) {
        c.units.remove(mesh);
        disposeObject(mesh);
        c.meshes.delete(id);
        c.targets.delete(id);
      }
    for (const p of positions) {
      let mesh = c.meshes.get(p.entity.id);
      const target = new THREE.Vector3(
        p.eastKm,
        ((p.heightM ?? 0) / 1000) * exaggeration + 1,
        -p.northKm,
      );
      if (!mesh) {
        mesh = createUnitGeometry(p.entity);
        mesh.position.copy(target);
        c.units.add(mesh);
        c.meshes.set(p.entity.id, mesh);
      }
      c.targets.set(p.entity.id, target);
    }
  }, [snapshot, scenario, terrain, level, exaggeration]);
  return (
    <div
      className="terrain-three"
      data-testid="terrain-3d"
      data-entity-count={projected.length}
    >
      <div className="terrain-controls">
        <label>
          显示高度倍率
          <select
            aria-label="3D显示高度倍率"
            value={exaggeration}
            onChange={(e) => setExaggeration(Number(e.target.value))}
          >
            {[1, 5, 10, 20].map((n) => (
              <option value={n} key={n}>
                {n}×（仅显示）
              </option>
            ))}
          </select>
        </label>
        <label className="interpolation">
          <input
            type="checkbox"
            checked={smooth}
            onChange={(e) => setSmooth(e.target.checked)}
          />
          单位显示插值
        </label>
        <button onClick={() => context.current?.reset()}>复位镜头</button>
      </div>
      <div ref={host} className="terrain-webgl" />
      {error && (
        <p role="alert" className="error">
          {error}
        </p>
      )}
      <p className="small muted">
        拖动旋转 · 滚轮缩放 ·
        点击格子/标记检查。符号尺寸不代表单位体积；高度倍率和插值不写回算法。
      </p>
      <p className="small" role="status">
        {picked ||
          "同源格均值表面；缺失高度仅用平面显示，不能视为真实平地/海域。"}
      </p>
      {scenario.displayFrame ? (
        <p className="small muted">{scenario.displayFrame.label}</p>
      ) : (
        <p className="status undefined">
          单位未提供投影声明：不将其虚构放入地理地块。
        </p>
      )}
      <div className="three-unit-readout">
        {projected.map((p) => (
          <button
            data-3d-entity-id={p.entity.id}
            key={p.entity.id}
            onClick={() => onSelectEntity(p.entity.id)}
          >
            {p.entity.id} · 实际 x {p.entity.x} / y {p.entity.y} ·{" "}
            {p.entity.granularity ?? "粒度未声明"}
          </button>
        ))}
      </div>
    </div>
  );
}
