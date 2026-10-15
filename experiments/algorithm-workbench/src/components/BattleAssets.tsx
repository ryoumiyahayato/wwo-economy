import { useEffect, useRef, useState } from "react";
import * as THREE from "three";
import { battleModel } from "../presentation/battleModels";
import { disposeObject } from "../presentation/unitGeometry";
import type { BattleEntity } from "../presentation/battle";
import { GLTFLoader } from "three/examples/jsm/loaders/GLTFLoader.js";

export function PlainsBackdrop() {
  const ref = useRef<HTMLDivElement>(null);
  const [status, setStatus] = useState("平原素材加载中");
  useEffect(() => {
    const host = ref.current!;
    let disposed = false;
    const renderer = new THREE.WebGLRenderer({ alpha: true, antialias: true });
    renderer.setPixelRatio(Math.min(window.devicePixelRatio, 1.5));
    renderer.outputColorSpace = THREE.SRGBColorSpace;
    host.appendChild(renderer.domElement);
    const scene = new THREE.Scene();
    const camera = new THREE.OrthographicCamera(-6, 6, 4, -4, 0.1, 100);
    camera.position.set(0, 12, 5);
    camera.lookAt(0, 0, 0);
    scene.add(new THREE.HemisphereLight(0xd7eaff, 0x354225, 2.1));
    const light = new THREE.DirectionalLight(0xffe8b2, 2.3);
    light.position.set(-4, 10, 5);
    scene.add(light);
    const draw = () => {
      renderer.setSize(host.clientWidth, host.clientHeight);
      renderer.render(scene, camera);
    };
    const ro = new ResizeObserver(draw);
    ro.observe(host);
    const disposeObject = (object: THREE.Object3D) =>
      object.traverse((o) => {
        if (o instanceof THREE.Mesh) {
          o.geometry.dispose();
          for (const m of Array.isArray(o.material) ? o.material : [o.material])
            m.dispose();
        }
      });
    new GLTFLoader().load(
      "/private-assets/plains.glb",
      (g) => {
        if (disposed) {
          disposeObject(g.scene);
          return;
        }
        scene.add(g.scene);
        setStatus("平原 GLB 已载入 · 美术层，不参与地形计算");
        draw();
      },
      undefined,
      () => setStatus("平原素材不可用 · 保留坐标网格"),
    );
    return () => {
      disposed = true;
      ro.disconnect();
      disposeObject(scene);
      renderer.dispose();
      renderer.domElement.remove();
    };
  }, []);
  return (
    <div
      className="plains-backdrop"
      ref={ref}
      aria-label={status}
      data-asset-status={status}
    />
  );
}
export function AssetBench() {
  const [frame, setFrame] = useState(3);
  const [kind, setKind] = useState("muzzle");
  const [open, setOpen] = useState(false);
  return (
    <details
      className="asset-bench"
      onToggle={(e) => setOpen(e.currentTarget.open)}
    >
      <summary>素材测试台 · 独立演出，非算法事件</summary>
      {open && <PlaceholderBench />}
      <div className="asset-body">
        <div
          className="atlas-frame"
          role="img"
          aria-label={`${kind} 独立测试第 ${frame} 帧`}
          style={{
            backgroundImage: `url(/private-assets/${kind}-atlas.webp)`,
            backgroundPosition: `${((frame % 4) * 100) / 3}% ${(Math.floor(frame / 4) * 100) / 3}%`,
          }}
        />
        <div>
          <strong>独立素材测试 / 16 帧</strong>
          <p>没有绑定算法事件。炮口焰包含炮管；金属火花不能代替人员受伤。</p>
          <select
            aria-label="测试特效"
            value={kind}
            onChange={(e) => setKind(e.target.value)}
          >
            <option value="muzzle">炮口焰纹理</option>
            <option value="sparks">金属火花纹理</option>
          </select>
          <input
            aria-label="特效帧"
            type="range"
            min={0}
            max={15}
            value={frame}
            onChange={(e) => setFrame(+e.target.value)}
          />
          <p>
            帧 {frame} / 15 · 按原 4×4 图集裁切；Godot
            光流、法线热度、HDR、粒子与折射未移植。
          </p>
        </div>
      </div>
    </details>
  );
}

function PlaceholderBench() {
  const host = useRef<HTMLDivElement>(null);
  useEffect(() => {
    const container = host.current!,
      scene = new THREE.Scene(),
      camera = new THREE.PerspectiveCamera(40, 1, 0.1, 100),
      renderer = new THREE.WebGLRenderer({ antialias: true });
    renderer.setClearColor(0x293b40);
    renderer.setPixelRatio(1);
    container.appendChild(renderer.domElement);
    camera.position.set(7, 5, 10);
    camera.lookAt(0, 1, 0);
    scene.add(new THREE.HemisphereLight(0xffffff, 0x3b4938, 3));
    for (const [i, kind] of ["person", "vehicle"].entries()) {
      const entity: BattleEntity = {
        id: `independent_${kind}`,
        label: `独立 ${kind}`,
        x: 0,
        y: 0,
        sourcePath: "independent-test-only",
        kind: kind === "person" ? "person" : "unit",
        team: "blue",
        state: "ABLE",
        raw: { raw: { type: kind } },
      };
      const model = battleModel(entity);
      model.position.x = i === 0 ? -2.5 : 1.7;
      scene.add(model);
    }
    const draw = () => {
      renderer.setSize(container.clientWidth, 190);
      camera.aspect = container.clientWidth / 190;
      camera.updateProjectionMatrix();
      renderer.render(scene, camera);
    };
    const observer = new ResizeObserver(draw);
    observer.observe(container);
    draw();
    return () => {
      observer.disconnect();
      disposeObject(scene);
      renderer.dispose();
      renderer.domElement.remove();
    };
  }, []);
  return (
    <div className="placeholder-bench">
      <p>
        独立简模测试：人形 / 车辆，可替换；不是本局算法实体。当前云端 A3
        未接出车辆或乘车关系。
      </p>
      <div ref={host} aria-label="独立人形车辆简模测试" />
    </div>
  );
}
