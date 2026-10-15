/** Display-only hierarchy in the original abstract km plane. No terrain or troops are generated. */
export const PARENT_KM = 50;
export const THEATRE_KM = 25;
export const CELL_KM = 5;
export const GRID_ORIGIN = -2.5; // Keeps A3's (0,0) inside, not on a picking boundary.
export function gridCells(size: 25 | 5) {
  const side = PARENT_KM / size;
  return Array.from({ length: side * side }, (_, i) => ({
    id: `${size}:${i % side}:${Math.floor(i / side)}`,
    x: GRID_ORIGIN + (i % side) * size,
    y: GRID_ORIGIN + Math.floor(i / side) * size,
    size,
  }));
}
export function cellAt(x: number, y: number, size: 25 | 5) {
  return gridCells(size).find(
    (c) => x >= c.x && x < c.x + size && y >= c.y && y < c.y + size,
  );
}
