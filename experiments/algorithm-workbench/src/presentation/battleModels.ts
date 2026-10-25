import * as T from "three";
import type { BattleEntity } from "./battle";
/** Replace this factory with GLTF models keyed by the SAME source ID. No anonymous troops are spawned. */
export function battleModel(entity: BattleEntity) {
  const group = new T.Group();
  group.userData.entityId = entity.id;
  const color = entity.team === "red" ? 0xc86454 : 0x53a9c4;
  const cloth = new T.MeshStandardMaterial({ color, roughness: 0.9 });
  const dark = new T.MeshStandardMaterial({ color: 0x202b2d, roughness: 0.9 });
  const skin = new T.MeshStandardMaterial({ color: 0xe0bf94, roughness: 0.9 });
  const box = (
    w: number,
    h: number,
    d: number,
    x: number,
    y: number,
    z: number,
    m: T.Material = cloth,
  ) => {
    const o = new T.Mesh(new T.BoxGeometry(w, h, d), m);
    o.position.set(x, y, z);
    group.add(o);
    return o;
  };
  if (entity.kind === "person") {
    box(0.6, 0.68, 0.32, 0, 1.05, 0);
    box(0.19, 0.7, 0.22, -0.18, 0.35, 0, dark);
    box(0.19, 0.7, 0.22, 0.18, 0.35, 0, dark);
    box(0.18, 0.62, 0.22, -0.43, 1.03, 0);
    box(0.18, 0.62, 0.22, 0.43, 1.03, 0);
    const head = new T.Mesh(new T.SphereGeometry(0.22, 10, 8), skin);
    head.position.y = 1.65;
    group.add(head);
    const helmet = new T.Mesh(
      new T.SphereGeometry(0.25, 10, 8, 0, Math.PI * 2, 0, Math.PI / 2),
      cloth,
    );
    helmet.position.y = 1.71;
    group.add(helmet);
    if (entity.weapon?.custody === "HELD")
      box(0.12, 0.12, 0.9, 0.43, 0.95, -0.2, dark);
    if (entity.state === "WOUNDED")
      box(
        0.66,
        0.12,
        0.35,
        0,
        1.12,
        0,
        new T.MeshStandardMaterial({ color: 0xf3c568 }),
      );
    if (["INCAPACITATED", "DEAD"].includes(entity.state)) {
      group.rotation.z = Math.PI / 2;
      group.position.y = 0.4;
    }
  } else if (
    /vehicle|truck|armor|armour|tank/.test(String(entity.raw.raw?.type))
  ) {
    box(2.2, 0.7, 3.6, 0, 0.8, 0);
    box(1.8, 0.8, 1.3, 0, 1.5, -0.8);
    for (const x of [-1.15, 1.15])
      for (const z of [-1.1, 1.1]) {
        const wheel = new T.Mesh(
          new T.CylinderGeometry(0.45, 0.45, 0.25, 10),
          dark,
        );
        wheel.rotation.z = Math.PI / 2;
        wheel.position.set(x, 0.45, z);
        group.add(wheel);
      }
  } else {
    // One low, symmetric counter denotes one aggregate unit. No invented
    // soldiers or body bearing; the separate arrow is observed movement only.
    box(1.4, 0.18, 1.4, 0, 0.09, 0, dark);
    box(1.15, 0.22, 1.15, 0, 0.29, 0);
    box(0.65, 0.05, 0.12, 0, 0.43, 0, dark);
  }
  group.traverse((o) => {
    o.userData.entityId = entity.id;
  });
  return group;
}
