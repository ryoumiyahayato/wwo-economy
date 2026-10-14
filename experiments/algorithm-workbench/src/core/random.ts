/** Portable 32-bit LCG. Draw order is part of demo v1's reproducibility contract. */
export class SeededRandom {
  constructor(public state: number) {
    this.state = state >>> 0;
  }
  next() {
    this.state = (Math.imul(1664525, this.state) + 1013904223) >>> 0;
    return this.state / 4294967296;
  }
}
