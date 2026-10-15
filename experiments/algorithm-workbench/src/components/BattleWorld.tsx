import { useEffect, useRef, useState } from "react";
import * as T from "three";
import { OrbitControls } from "three/addons/controls/OrbitControls.js";
import { GLTFLoader } from "three/addons/loaders/GLTFLoader.js";
import type {
  BattleFrame,
  BattleEvent,
  BattleEntity,
} from "../presentation/battle";
import { fmt } from "../presentation/battle";
import { battleModel } from "../presentation/battleModels";
import { disposeObject } from "../presentation/unitGeometry";
import { cellAt, GRID_ORIGIN } from "../presentation/battleGrid";

type Props = {
  frame: BattleFrame;
  frames: BattleFrame[];
  selected: string;
  allocation?: BattleEvent;
  art: boolean;
  onEntity: (id: string) => void;
  onEvent: (event: BattleEvent) => void;
};
type ScreenLabel = {
  id: string;
  left: number;
  top: number;
  anchorX: number;
  anchorY: number;
  entity: BattleEntity;
};
type Context = {
  update: (props: Props) => void;
  focus: (level: number, x?: number, y?: number) => void;
  setArt: (v: boolean) => void;
};
export function BattleWorld(props: Props) {
  const host = useRef<HTMLDivElement>(null),
    context = useRef<Context | null>(null),
    latest = useRef(props);
  latest.current = props;
  const [labels, setLabels] = useState<ScreenLabel[]>([]),
    [level, setLevel] = useState(0.5),
    [status, setStatus] = useState("平原素材加载中"),
    [error, setError] = useState("");
  const [area, setArea] = useState({ x: 0, y: 0 }),
    [viewWidth, setViewWidth] = useState(500);
  useEffect(() => {
    const container = host.current!;
    let stopped = false,
      raf = 0,
      dirty = true,
      moving = false;
    const renderSamples: number[] = [];
    let renderer: T.WebGLRenderer;
    try {
      renderer = new T.WebGLRenderer({ antialias: true });
    } catch (e) {
      setError("WebGL 不可用，请选择坐标审阅。" + String(e));
      return;
    }
    renderer.setPixelRatio(Math.min(devicePixelRatio, 1.5));
    renderer.setClearColor(0x1b3034);
    renderer.outputColorSpace = T.SRGBColorSpace;
    renderer.domElement.setAttribute("aria-label", "同一战场 · 广角斜俯视");
    container.appendChild(renderer.domElement);
    const scene = new T.Scene(),
      camera = new T.PerspectiveCamera(50, 1, 0.1, 180000),
      controls = new OrbitControls(camera, renderer.domElement);
    controls.enableDamping = false;
    controls.minDistance = 25;
    controls.maxDistance = 90000;
    controls.maxPolarAngle = Math.PI * 0.46;
    scene.add(new T.HemisphereLight(0xeaf6fa, 0x46533a, 2));
    const sun = new T.DirectionalLight(0xffefcb, 2.4);
    sun.position.set(-300, 500, 100);
    scene.add(sun);
    const ground = new T.Mesh(
      new T.PlaneGeometry(50000, 50000),
      new T.MeshStandardMaterial({
        color: 0x3e5145,
        roughness: 1,
        side: T.DoubleSide,
      }),
    );
    ground.rotation.x = -Math.PI / 2;
    ground.position.set(22500, -0.1, -22500);
    scene.add(ground);
    const grid = new T.Group();
    scene.add(grid);
    for (const size of [5, 25] as const) {
      const points: T.Vector3[] = [];
      for (let i = 0; i <= 50 / size; i++) {
        const p = (GRID_ORIGIN + i * size) * 1000;
        points.push(
          new T.Vector3(-2500, 0.3, -p),
          new T.Vector3(47500, 0.3, -p),
          new T.Vector3(p, 0.3, 2500),
          new T.Vector3(p, 0.3, -47500),
        );
      }
      grid.add(
        new T.LineSegments(
          new T.BufferGeometry().setFromPoints(points),
          new T.LineBasicMaterial({
            color: size === 25 ? 0xb8d1bf : 0x648779,
            transparent: true,
            opacity: size === 25 ? 0.8 : 0.4,
          }),
        ),
      );
    }
    const detailGrid = new T.GridHelper(800, 40, 0x647b6d, 0x4b6255);
    detailGrid.position.set(100, 0.15, -100);
    scene.add(detailGrid);
    const artGroup = new T.Group();
    scene.add(artGroup);
    new GLTFLoader().load(
      "/private-assets/plains.glb",
      (g) => {
        if (stopped) {
          disposeObject(g.scene);
          return;
        }
        const bounds = new T.Box3().setFromObject(g.scene),
          center = bounds.getCenter(new T.Vector3());
        g.scene.position.sub(center);
        const tile = new T.Group();
        tile.add(g.scene);
        tile.scale.setScalar(65);
        tile.position.set(70, -1, -100);
        artGroup.add(tile);
        setStatus("平原 GLB 已载入 · 装饰比例，非真实地形");
        dirty = true;
      },
      undefined,
      () => setStatus("平原素材不可用 · 保留原坐标地面"),
    );
    let objects = new T.Group(),
      links = new T.Group();
    scene.add(objects, links);
    const modelCache = new Map<
      string,
      { signature: string; wrapper: T.Group }
    >();
    const anchors = new Map<string, T.Vector3>(),
      displays = new Map<string, T.Vector3>();
    let currentLevel = 0.5;
    let destination: T.Vector3 | null = null,
      targetDestination: T.Vector3 | null = null;
    let transitionStarted = 0;
    const cameraFrom = new T.Vector3(),
      targetFrom = new T.Vector3();
    function focus(next: number, x = 60, y = 60) {
      // A preset may be selected before ResizeObserver has delivered a resize.
      camera.aspect = container.clientWidth / container.clientHeight;
      camera.updateProjectionMatrix();
      currentLevel = next;
      setLevel(next);
      setArea({ x, y });
      const span = next * 1000;
      const target = new T.Vector3(x, 0, -y);
      targetDestination = target;
      const distance =
        next < 1
          ? span /
            (2 * Math.tan(T.MathUtils.degToRad(camera.fov / 2)) * camera.aspect)
          : span * 1.16;
      destination = target
        .clone()
        .add(
          new T.Vector3(0.5, 0.62, 0.85).normalize().multiplyScalar(distance),
        );
      cameraFrom.copy(camera.position);
      targetFrom.copy(controls.target);
      transitionStarted = performance.now();
      moving = true;
      dirty = true;
    }
    camera.position.set(245, 248, 230);
    controls.target.set(60, 0, -60);
    controls.update();
    const line = (
      from: T.Vector3,
      to: T.Vector3,
      color: number,
      dashed = false,
    ) => {
      const material = dashed
        ? new T.LineDashedMaterial({ color, dashSize: 4, gapSize: 3 })
        : new T.LineBasicMaterial({ color });
      const l = new T.Line(
        new T.BufferGeometry().setFromPoints([from, to]),
        material,
      );
      if (dashed) l.computeLineDistances();
      links.add(l);
      return l;
    };
    function update(p: Props) {
      // Keep native-ID models and GPU resources between committed states.
      for (const [id, cached] of modelCache) {
        cached.wrapper.removeFromParent();
        if (!p.frame.entities.some((e) => e.id === id)) {
          disposeObject(cached.wrapper);
          modelCache.delete(id);
        }
      }
      scene.remove(objects, links);
      disposeObject(objects);
      disposeObject(links);
      objects = new T.Group();
      links = new T.Group();
      scene.add(objects, links);
      anchors.clear();
      displays.clear();
      const cohorts = new Map<string, BattleEntity[]>();
      for (const e of p.frame.entities) {
        const key = `${e.x.toFixed(8)},${e.y.toFixed(8)}`;
        cohorts.set(key, [...(cohorts.get(key) ?? []), e]);
      }
      for (const e of p.frame.entities) {
        const anchor = new T.Vector3(e.x * 1000, 0.6, -e.y * 1000);
        anchors.set(e.id, anchor);
        const group = cohorts.get(`${e.x.toFixed(8)},${e.y.toFixed(8)}`)!,
          i = group.findIndex((v) => v.id === e.id);
        const angle = (i / group.length) * Math.PI * 2;
        const radius = group.length > 1 ? 30 : 0;
        const display = anchor
          .clone()
          .add(
            new T.Vector3(
              Math.cos(angle) * radius,
              0,
              Math.sin(angle) * radius,
            ),
          );
        displays.set(e.id, display);
        const signature = [
          e.kind,
          e.state,
          e.team,
          e.raw.raw?.type,
          e.weapon?.custody,
          e.id === p.selected,
        ].join(":");
        let cached = modelCache.get(e.id);
        if (cached?.signature !== signature) {
          if (cached) disposeObject(cached.wrapper);
          const wrapper = new T.Group();
          const model = battleModel(e);
          model.scale.setScalar(e.kind === "person" ? 7 : 9);
          wrapper.add(model);
          // Unknown body bearing is never invented. A source movement arrow is separate.
          const ring = new T.Mesh(
            new T.RingGeometry(7, 9, 24),
            new T.MeshBasicMaterial({
              color:
                e.id === p.selected
                  ? 0xffffff
                  : e.team === "red"
                    ? 0xee8d7b
                    : 0x70d9ec,
              side: T.DoubleSide,
            }),
          );
          ring.rotation.x = -Math.PI / 2;
          ring.position.y = 0.25;
          wrapper.add(ring);
          cached = { signature, wrapper };
          modelCache.set(e.id, cached);
        }
        const wrapper = cached!.wrapper;
        wrapper.position.copy(display);
        objects.add(wrapper);
        if (radius)
          line(anchor, display, e.team === "red" ? 0xa26458 : 0x5c9ba8);
        const dot = new T.Mesh(
          new T.SphereGeometry(1.7, 8, 6),
          new T.MeshBasicMaterial({ color: 0xddeade }),
        );
        dot.position.copy(anchor);
        objects.add(dot);
        if (e.movement) {
          const a = new T.Vector3(
              e.movement.from[0] * 1000,
              1,
              -e.movement.from[1] * 1000,
            ),
            v = anchor.clone().sub(a);
          if (v.length() > 0)
            links.add(
              new T.ArrowHelper(
                v.clone().normalize(),
                a,
                v.length(),
                0x83ebd5,
                Math.min(v.length(), 6),
                3,
              ),
            );
        }
        const trail = p.frames.flatMap((f) => {
          const v = f.entities.find((v) => v.id === e.id);
          return v ? [new T.Vector3(v.x * 1000, 0.7, -v.y * 1000)] : [];
        });
        if (trail.length > 1)
          links.add(
            new T.Line(
              new T.BufferGeometry().setFromPoints(trail),
              new T.LineBasicMaterial({
                color: e.team === "red" ? 0x98756c : 0x6da6b4,
              }),
            ),
          );
      }
      for (const e of p.frame.entities) {
        if (e.weapon?.mode !== "FIRE") continue;
        const a = anchors.get(e.id),
          b = anchors.get(String(e.weapon.target_ref));
        if (!a || !b) continue;
        const intent = line(
          a.clone().setY(12),
          b.clone().setY(12),
          0xa4ecfa,
          true,
        );
        intent.userData.entityId = e.id; // Native weapon state, not a projectile/hit.
      }
      const allocations = p.allocation
        ? [p.allocation]
        : p.frame.events.filter((e) => e.kind === "shared_fire_allocation");
      for (const e of allocations)
        for (const c of e.raw.detail?.prepared_contacts ?? []) {
          const a = anchors.get(c.source),
            b = anchors.get(c.target);
          if (!a || !b) continue;
          const l = line(a.clone().setY(7), b.clone().setY(7), 0xf4c36c, true);
          l.userData.event = e;
          const d = b.clone().sub(a);
          links.add(
            new T.ArrowHelper(
              d.clone().normalize(),
              a.clone().setY(7),
              d.length(),
              0xf4c36c,
              8,
              4,
            ),
          );
        }
      artGroup.visible = p.art;
      dirty = true;
    }
    const resize = () => {
      const w = container.clientWidth,
        h = container.clientHeight;
      renderer.setSize(w, h);
      camera.aspect = w / h;
      camera.updateProjectionMatrix();
      dirty = true;
    };
    const ro = new ResizeObserver(resize);
    ro.observe(container);
    resize();
    const changed = () => {
      dirty = true;
    };
    controls.addEventListener("change", changed);
    const ray = new T.Raycaster();
    ray.params.Line = { threshold: 4 };
    let down: { x: number; y: number } | null = null;
    const pointerdown = (e: PointerEvent) => {
      down = { x: e.clientX, y: e.clientY };
      destination = null;
      targetDestination = null;
      moving = false;
    };
    const pointerup = (e: PointerEvent) => {
      if (!down || Math.hypot(e.clientX - down.x, e.clientY - down.y) > 4)
        return;
      const b = renderer.domElement.getBoundingClientRect();
      ray.setFromCamera(
        new T.Vector2(
          ((e.clientX - b.left) / b.width) * 2 - 1,
          (-(e.clientY - b.top) / b.height) * 2 + 1,
        ),
        camera,
      );
      if (currentLevel < 1) {
        const hit = ray
          .intersectObjects([...objects.children, ...links.children], true)
          .find((h) => h.object.userData.entityId || h.object.userData.event);
        if (hit) {
          if (hit.object.userData.entityId)
            latest.current.onEntity(hit.object.userData.entityId);
          else latest.current.onEvent(hit.object.userData.event);
          return;
        }
      }
      const point = ray.intersectObject(ground)[0]?.point;
      if (!point) return;
      if (currentLevel >= 50) {
        const c = cellAt(point.x / 1000, -point.z / 1000, 25);
        if (c) focus(25, (c.x + 12.5) * 1000, (c.y + 12.5) * 1000);
      } else if (currentLevel >= 25) {
        const c = cellAt(point.x / 1000, -point.z / 1000, 5);
        if (c) focus(5, (c.x + 2.5) * 1000, (c.y + 2.5) * 1000);
      } else if (currentLevel >= 5) {
        focus(0.5, point.x, -point.z);
      }
    };
    renderer.domElement.addEventListener("pointerdown", pointerdown);
    renderer.domElement.addEventListener("pointerup", pointerup);
    const project = (p: T.Vector3) => {
      const v = p.clone().project(camera);
      return {
        x: ((v.x + 1) * container.clientWidth) / 2,
        y: ((1 - v.y) * container.clientHeight) / 2,
        z: v.z,
      };
    };
    function render() {
      if (stopped) return;
      raf = requestAnimationFrame(render);
      if (moving && destination && targetDestination) {
        const progress = Math.min(
          1,
          (performance.now() - transitionStarted) / 1000,
        );
        const eased = 1 - Math.pow(1 - progress, 3);
        camera.position.lerpVectors(cameraFrom, destination, eased);
        controls.target.lerpVectors(targetFrom, targetDestination, eased);
        controls.update();
        moving = progress < 1;
        dirty = true;
      }
      if (!dirty) return;
      dirty = false;
      const groundPlane = new T.Plane(new T.Vector3(0, 1, 0), 0),
        a = new T.Vector3(),
        b = new T.Vector3();
      ray.setFromCamera(new T.Vector2(-1, 0), camera);
      ray.ray.intersectPlane(groundPlane, a);
      ray.setFromCamera(new T.Vector2(1, 0), camera);
      ray.ray.intersectPlane(groundPlane, b);
      const viewWidth = a.distanceTo(b);
      const detailed = viewWidth < 1800;
      objects.visible = detailed;
      links.visible = detailed;
      detailGrid.visible = detailed;
      artGroup.visible = latest.current.art && detailed;
      const started = performance.now();
      renderer.render(scene, camera);
      renderSamples.push(performance.now() - started);
      if (renderSamples.length > 400) renderSamples.shift();
      container.dataset.renderSamples = JSON.stringify(renderSamples);
      setViewWidth(viewWidth);
      container.dataset.viewWidthM = String(viewWidth);
      container.dataset.cameraTransition = String(moving);
      container.dataset.drawCalls = String(renderer.info.render.calls);
      container.dataset.triangles = String(renderer.info.render.triangles);
      container.dataset.lod = detailed ? "near-models" : "grid-only";
      const items: ScreenLabel[] = [];
      if (detailed) {
        for (const entity of latest.current.frame.entities) {
          const display = displays.get(entity.id),
            anchor = anchors.get(entity.id);
          if (!display || !anchor) continue;
          const p = project(
              display.clone().setY(entity.kind === "person" ? 21 : 27),
            ),
            a = project(anchor);
          if (
            p.z < -1 ||
            p.z > 1 ||
            p.x < 0 ||
            p.x > container.clientWidth ||
            p.y < 0 ||
            p.y > container.clientHeight
          )
            continue;
          items.push({
            id: entity.id,
            left: Math.max(
              65,
              Math.min(
                container.clientWidth - 65,
                p.x + (entity.team === "blue" ? -85 : 85),
              ),
            ),
            top: Math.max(60, p.y - 24),
            anchorX: a.x,
            anchorY: a.y,
            entity,
          });
        }
        items.sort((a, b) => a.top - b.top);
        for (let i = 0; i < items.length; i++)
          for (let j = 0; j < i; j++)
            if (
              Math.abs(items[i].left - items[j].left) < 123 &&
              Math.abs(items[i].top - items[j].top) < 43
            )
              items[i].top = items[j].top + 43;
      }
      setLabels(items);
      const a3 = project(new T.Vector3(60, 1, -80));
      container.dataset.a3X = String(a3.x);
      container.dataset.a3Y = String(a3.y);
      container.dataset.level = String(currentLevel);
      container.dataset.camera = JSON.stringify(camera.position.toArray());
    }
    focus(0.5);
    update(latest.current);
    context.current = {
      update,
      focus,
      setArt: (v) => {
        artGroup.visible = v;
        dirty = true;
      },
    };
    render();
    return () => {
      stopped = true;
      cancelAnimationFrame(raf);
      ro.disconnect();
      controls.dispose();
      renderer.domElement.removeEventListener("pointerdown", pointerdown);
      renderer.domElement.removeEventListener("pointerup", pointerup);
      disposeObject(scene);
      renderer.dispose();
      renderer.domElement.remove();
      context.current = null;
    };
  }, []);
  useEffect(
    () => context.current?.update(props),
    [props.frame, props.frames, props.selected, props.allocation],
  );
  useEffect(() => context.current?.setArt(props.art), [props.art]);
  function focus(size: number) {
    if (size < 1) {
      context.current?.focus(size);
      return;
    }
    const c = cellAt(
      area.x / 1000,
      area.y / 1000,
      size === 50 ? 25 : size === 25 ? 25 : 5,
    );
    context.current?.focus(
      size,
      size === 50 ? 22500 : c ? (c.x + c.size / 2) * 1000 : 0,
      size === 50 ? 22500 : c ? (c.y + c.size / 2) * 1000 : 0,
    );
  }
  return (
    <div className="battle-world">
      <div className="world-navigation" aria-label="同图连续展开">
        <strong>本人：squad · 仅原人物权限</strong>
        {[50, 25, 5, 0.5].map((s) => (
          <button key={s} aria-pressed={level === s} onClick={() => focus(s)}>
            {s === 50
              ? "50 km 父格"
              : s === 25
                ? "25 km 战区"
                : s === 5
                  ? "5 km 作战格"
                  : "本人附近"}
          </button>
        ))}
        <label>
          近景试档{" "}
          <select
            aria-label="近景取景宽度"
            value={level < 1 ? String(level) : ".5"}
            onChange={(e) => context.current?.focus(+e.target.value)}
          >
            <option value="0.5">500m</option>
            <option value="0.3">300m</option>
            <option value="0.2">200m</option>
          </select>
        </label>
      </div>
      <div className="world-surface" ref={host} data-asset-status={status}>
        {error && <p role="alert">{error}</p>}
        <div className="world-hud">
          <span>
            同一场景 ·{" "}
            {viewWidth < 1800 ? "广角斜俯视" : `${level} × ${level} km`} ·
            中心地面横向 ≈
            {viewWidth < 1000
              ? `${Math.round(viewWidth)}m`
              : `${(viewWidth / 1000).toFixed(1)}km`}{" "}
            · 拖动旋转 / 滚轮缩放
          </span>
          <span>
            tick {props.frame.tick} · {fmt(props.frame.time)}s
          </span>
        </div>
        <svg className="world-label-lines" aria-hidden="true">
          {labels.map((l) => (
            <line
              key={l.id}
              x1={l.anchorX}
              y1={l.anchorY}
              x2={l.left}
              y2={l.top}
              stroke={l.entity.team === "red" ? "#ef9986" : "#8cdae5"}
              strokeOpacity=".4"
            />
          ))}
        </svg>
        {labels.map((l) => (
          <button
            key={l.id}
            data-battle-entity={l.id}
            className={`world-entity ${l.entity.team} ${props.selected === l.id ? "selected" : ""}`}
            style={{ left: l.left, top: l.top }}
            onClick={() => props.onEntity(l.id)}
          >
            <b>
              {l.id}
              {l.id === "squad" ? " · 我" : ""}
            </b>
            <small>
              {l.entity.kind === "person"
                ? l.entity.state === "WOUNDED"
                  ? "受伤"
                  : l.entity.state === "ABLE"
                    ? "可行动"
                    : l.entity.state
                : `${l.entity.raw.raw?.type ?? "单位"} · ${l.entity.state}`}
              {l.entity.movement ? " · 移动→" : ""}
              {l.entity.weapon?.mode === "FIRE"
                ? ` · 射击 ${l.entity.weapon.target_ref ?? ""}`
                : ""}
            </small>
          </button>
        ))}
        {viewWidth >= 1800 && (
          <button
            className="world-a3"
            onClick={() => context.current?.focus(0.5)}
          >
            A3 · {props.frame.entities.length} 个已定位实体
            <br />
            原地展开本人附近
          </button>
        )}
        {viewWidth >= 1800 && (
          <div className="world-coverage">
            50 km 父格 = 4 个 25 km 战区 = 100 个 5 km 格<br />
            网格用于显示导航；当前只接通 A3 局部实例，其余格无战况输出。
            <br />
            点击地面格继续展开，不创建战场实例。
          </div>
        )}
      </div>
      <p className="world-footnote">
        引线端点是原坐标；同点对象作显示展开，模型尺寸夸张且可替换。黄色线=原区间火力关联，浅蓝线=本人
        FIRE 状态目标；身体朝向未知。GLB 为装饰，不代表掩体/水文/季节。
      </p>
    </div>
  );
}
