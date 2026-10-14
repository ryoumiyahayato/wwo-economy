import {
  clone,
  type AlgorithmAdapter,
  type Event,
  type Snapshot,
  type Stage,
} from "../core/types";
import { militaryMetadata, validateScenario } from "../core/scenario";
import { SeededRandom } from "../core/random";
import { provideSupply } from "../core/dependencies";

export const militaryAdapter: AlgorithmAdapter = {
  metadata: militaryMetadata,
  async create(input) {
    const s = validateScenario(input, militaryMetadata),
      p = s.params,
      random = new SeededRandom(s.seed);
    let tick = 0,
      x = 0,
      blue = p.personnel,
      orange = p.targetPersonnel,
      ammo = p.ammo,
      enemyAmmo = p.ammo,
      shots = 0,
      enemyShots = 0,
      casualties = 0,
      enemyCasualties = 0,
      injectedAmmo = 0,
      lastAmmo = 0,
      stallTicks = 0;
    let events: Event[] = [],
      stages: Stage[] = [],
      reason = "";
    const movementOnly = s.boundary === "movement";
    const outcome = () =>
      movementOnly
        ? x >= p.distance
          ? "pass"
          : "pending"
        : orange === 0
          ? "pass"
          : blue === 0
            ? "fail"
            : "pending";
    const snapshot = (): Snapshot => {
      const status = outcome(),
        ended = status !== "pending" || tick >= s.maxTicks;
      return clone({
        tick,
        metrics: {
          position: x,
          distanceRemaining: p.distance - x,
          personnel: blue,
          targetPersonnel: orange,
          ammo,
          shots,
          casualties,
          enemyCasualties,
          enemyShots,
          enemyAmmo,
          stallTicks,
          ammoResidual: p.ammo + injectedAmmo - ammo - shots,
          personnelResidual:
            p.personnel +
            p.targetPersonnel -
            blue -
            orange -
            casualties -
            enemyCasualties,
        },
        stages: tick
          ? stages
          : [
              {
                id: "input",
                label: "输入",
                status: "pending",
                detail: "点击单步开始",
              },
            ],
        events,
        entities: [
          {
            id: "blue",
            label: "蓝方",
            team: "blue",
            granularity: "formation",
            state:
              x >= p.distance
                ? movementOnly
                  ? "arrived"
                  : "engaging"
                : "moving",
            x,
            y: 3,
            personnel: blue,
            ammo,
          },
          {
            id: "orange",
            label: movementOnly ? "目标位置" : "橙方",
            team: "orange",
            granularity: "formation",
            x: p.distance,
            y: 3,
            personnel: orange,
            ammo: enemyAmmo,
          },
        ],
        orders: [],
        invariants: {
          ammo: p.ammo + injectedAmmo - ammo - shots,
          enemyAmmo: p.ammo - enemyAmmo - enemyShots,
          personnel:
            p.personnel +
            p.targetPersonnel -
            blue -
            orange -
            casualties -
            enemyCasualties,
        },
        injections: { ammo: lastAmmo, totalAmmo: injectedAmmo },
        completion: {
          status: status === "pending" && ended ? "fail" : status,
          condition: movementOnly
            ? "蓝方按移动函数到达目标位置"
            : "完成抽象交火，目标人数降为 0；失败与无进展保留",
          reason:
            status === "pass"
              ? "合成 demo 任务完成"
              : status === "fail"
                ? "蓝方失去行动能力"
                : reason || "任务进行中",
        },
        done: ended,
        blockedReason: reason,
      });
    };
    return {
      snapshot: snapshot(),
      session: {
        async step() {
          if (snapshot().done) return snapshot();
          tick++;
          events = [];
          stages = [];
          lastAmmo = 0;
          reason = "";
          const before = x + shots + enemyShots;
          const event = (
            stage: string,
            status: Event["status"],
            message: string,
            entityId?: string,
          ) =>
            events.push({
              tick,
              stage,
              status,
              message,
              ...(entityId ? { entityId } : {}),
            });
          stages.push({
            id: "input",
            label: "输入",
            status: "success",
            detail: "有效单位、目标与固定种子",
          });
          if (x < p.distance) {
            if (s.dependencies.path === "blocked") {
              reason = "外部路径不可达";
              event("movement", "blocked", reason, "blue");
            } else {
              const delta = Math.min(p.speed, p.distance - x);
              x += delta;
              event(
                "movement",
                delta > 0 ? "success" : "blocked",
                `移动 +${delta}；位置 ${x}`,
                "blue",
              );
              if (delta === 0) reason = "被测移动速度为 0";
            }
          }
          stages.push({
            id: "movement",
            label: "移动",
            status: reason
              ? "blocked"
              : x >= p.distance
                ? "success"
                : "pending",
            detail: `位置 ${x} / ${p.distance}`,
          });
          if (!movementOnly && x >= p.distance && blue > 0 && orange > 0) {
            const supply = provideSupply(
              p.fireRate,
              ammo,
              s.dependencies.resupply,
            );
            ammo = supply.available;
            injectedAmmo += supply.injected;
            lastAmmo = supply.injected;
            if (supply.injected)
              event("external", "success", `外部弹药注入 +${supply.injected}`);
            const fired = Math.min(ammo, p.fireRate);
            ammo -= fired;
            shots += fired;
            let hits = 0;
            for (let i = 0; i < fired; i++)
              if (random.next() < p.hitChance) hits++;
            const loss = Math.min(orange, hits);
            orange -= loss;
            enemyCasualties += loss;
            event(
              "engagement",
              fired ? "success" : "blocked",
              `蓝方射击 ${fired}；命中 ${hits}；橙方伤亡 ${loss}`,
              "blue",
            );
            if (orange > 0) {
              const firedBack = Math.min(enemyAmmo, 1);
              enemyAmmo -= firedBack;
              enemyShots += firedBack;
              const hit = firedBack && random.next() < 0.4 ? 1 : 0;
              const lossBack = Math.min(blue, hit);
              blue -= lossBack;
              casualties += lossBack;
              event(
                "engagement",
                firedBack ? "success" : "pending",
                `橙方射击 ${firedBack}；蓝方伤亡 ${lossBack}`,
                "orange",
              );
            }
            if (!fired)
              reason = ammo === 0 ? "蓝方弹药耗尽" : "被测射击速率为 0";
            stages.push({
              id: "engagement",
              label: "交火",
              status: fired ? "success" : "blocked",
              detail: "每发抽样计算；不保证命中或获胜",
            });
          } else
            stages.push({
              id: "engagement",
              label: "交火",
              status: movementOnly ? "not-implemented" : "pending",
              detail: movementOnly ? "移动任务不执行交火" : "等待移动至目标",
            });
          stages.push({
            id: "result",
            label: "结果",
            status:
              outcome() === "pass"
                ? "success"
                : outcome() === "fail"
                  ? "blocked"
                  : "pending",
            detail: `蓝方 ${blue}；橙方 ${orange}；弹药 ${ammo}`,
          });
          stages.push({
            id: "next-tick",
            label: "时间",
            status: "success",
            detail: `推进到 ${tick}`,
          });
          event("next-tick", "success", `完成 tick ${tick}`);
          stallTicks = before === x + shots + enemyShots ? stallTicks + 1 : 0;
          return snapshot();
        },
        async close() {},
      },
    };
  },
};
