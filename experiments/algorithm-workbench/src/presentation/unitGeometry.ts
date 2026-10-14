import * as THREE from "three";
import { type Entity } from "../core/types";
/** Original geometric formation symbol. Geometry size is a display symbol, not troop footprint. */
export function createUnitGeometry(entity: Entity) {
  const group = new THREE.Group();
  group.userData.entityId = entity.id;
  const color = entity.team === "orange" ? 0xb46d2d : 0x067c78;
  const material = new THREE.MeshStandardMaterial({ color, roughness: 0.8 });
  const base = new THREE.Mesh(new THREE.BoxGeometry(6, 3, 6), material);
  base.position.y = 1.5;
  const top = new THREE.Mesh(new THREE.ConeGeometry(2.4, 3, 4), material);
  top.position.y = 4.5;
  group.add(base, top);
  for (const child of group.children) child.userData.entityId = entity.id;
  return group;
}
export function disposeObject(root: THREE.Object3D) {
  const materials = new Set<THREE.Material>();
  root.traverse((child) => {
    const mesh = child as THREE.Mesh;
    if (mesh.geometry) mesh.geometry.dispose();
    if (mesh.material)
      (Array.isArray(mesh.material) ? mesh.material : [mesh.material]).forEach(
        (m) => materials.add(m),
      );
  });
  materials.forEach((m) => m.dispose());
}
