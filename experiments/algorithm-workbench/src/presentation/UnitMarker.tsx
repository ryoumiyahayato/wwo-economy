/** Reusable formation glyph. One marker = one adapter entity, never invented individuals. */
export function UnitMarker({
  entityId,
  label,
  personnel,
  ammo,
  team,
  heading = 0,
  x,
  y,
  interpolate = false,
  onSelect,
}: {
  entityId: string;
  label: string;
  personnel?: number;
  ammo?: number;
  team?: string;
  heading?: number;
  x: number;
  y: number;
  interpolate?: boolean;
  onSelect?: () => void;
}) {
  const color = team === "orange" ? "#b46d2d" : "#067c78";
  return (
    <g
      data-entity-id={entityId}
      onClick={onSelect}
      role={onSelect ? "button" : undefined}
      tabIndex={onSelect ? 0 : undefined}
      aria-label={`追踪单位 ${entityId}`}
      onKeyDown={(event) => {
        if (onSelect && event.key === "Enter") onSelect();
      }}
      transform={`translate(${x},${y})`}
      style={interpolate ? { transition: "transform 180ms linear" } : undefined}
    >
      <text y={-28} textAnchor="middle">
        {label} · ID {entityId}
      </text>
      <g transform={`rotate(${heading})`}>
        <rect
          x={-15}
          y={-11}
          width={30}
          height={22}
          rx={3}
          fill={color}
          stroke="white"
          strokeWidth={2}
        />
        <path
          d="M-8 -5 L8 5 M8 -5 L-8 5"
          fill="none"
          stroke="white"
          strokeWidth={1.5}
        />
        <path d="M17 -5 L24 0 L17 5" fill={color} />
      </g>
      <text y={35} textAnchor="middle">
        单位人数 {personnel ?? "未知"} / 弹药 {ammo ?? "未知"}
      </text>
    </g>
  );
}
