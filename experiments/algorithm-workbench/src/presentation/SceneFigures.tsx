// Original display symbols. Geometry and equipment shapes are not simulation inputs.
export function SoldierFigure({
  selected,
  wounded,
  dead,
}: {
  selected: boolean;
  wounded: boolean;
  dead: boolean;
}) {
  const uniform = dead ? "#69706a" : wounded ? "#aa7444" : "#60734e";
  return (
    <g className="soldier-figure" data-testid="soldier-figure">
      <ellipse cy={7} rx={35} ry={12} fill="#697b63" opacity={0.16} />
      {selected && (
        <ellipse
          cy={7}
          rx={40}
          ry={16}
          fill="none"
          stroke="#067c78"
          strokeWidth={3}
        />
      )}
      <path d="M-12-22L-14 2L-3 3L1-22M5-22L7 3L19 3L15-22" fill="#44513e" />
      <path d="M-16 0L-17 8L-2 8L-2 1M7 1L7 8L23 8L21 0" fill="#333c36" />
      <path
        d="M-13-62Q0-69 15-61L21-25Q3-17-19-25Z"
        fill={uniform}
        stroke="#394d3e"
        strokeWidth={2}
      />
      <path
        d="M-15-60L-25-52L-29-31L-21-27L-16-46M16-59L25-48L28-27L20-25L16-45"
        fill={uniform}
        stroke="#394d3e"
        strokeWidth={2}
      />
      <path d="M-17-25L18-25M-4-61L-4-28" stroke="#d3c39c" strokeWidth={3} />
      <rect x={-10} y={-45} width={8} height={9} rx={1} fill="#82926d" />
      <rect x={5} y={-45} width={8} height={9} rx={1} fill="#82926d" />
      <circle cy={-78} r={14} fill="#d8b590" stroke="#5c6351" strokeWidth={2} />
      <path
        d="M-17-79Q-17-101 0-101Q18-101 18-79Z"
        fill="#526749"
        stroke="#394d3e"
        strokeWidth={2}
      />
      <path
        d="M-19-79L20-79"
        stroke="#354537"
        strokeWidth={4}
        strokeLinecap="round"
      />
    </g>
  );
}

export const goodLabels: Record<string, string> = {
  grain: "谷物",
  bread: "面包",
  beans: "豆类",
  soap: "肥皂",
  goods: "商品",
};
export function GoodFigure({ good }: { good: string }) {
  if (good === "grain")
    return (
      <g>
        <path
          d="M0 16L0-13M0 3L-9-6M0-4L9-13"
          stroke="#a37631"
          strokeWidth={2}
        />
        {[-9, -2, 5].map((v) => (
          <g key={v}>
            <ellipse
              cx={-5}
              cy={v}
              rx={4}
              ry={6}
              transform={`rotate(-35 -5 ${v})`}
              fill="#d6aa48"
            />
            <ellipse
              cx={5}
              cy={v - 5}
              rx={4}
              ry={6}
              transform={`rotate(35 5 ${v - 5})`}
              fill="#edc567"
            />
          </g>
        ))}
      </g>
    );
  if (good === "bread")
    return (
      <g>
        <path
          d="M-19 9Q-23-10-8-15Q10-21 22-5L20 9Z"
          fill="#dc9c4b"
          stroke="#9f6d34"
          strokeWidth={2}
        />
        <path
          d="M-10-7L-5 1M0-11L5-3M10-8L14-1"
          stroke="#fae0a2"
          strokeWidth={3}
        />
      </g>
    );
  if (good === "beans")
    return (
      <g>
        <path
          d="M-21 12Q-12-20 22-13Q7 15-21 12Z"
          fill="#75985d"
          stroke="#4e7047"
          strokeWidth={2}
        />
        {[-10, 0, 10].map((v, i) => (
          <ellipse key={v} cx={v} cy={5 - i * 6} rx={5} ry={6} fill="#bcd489" />
        ))}
      </g>
    );
  if (good === "soap")
    return (
      <g>
        <rect
          x={-20}
          y={-12}
          width={40}
          height={26}
          rx={6}
          fill="#c0dce3"
          stroke="#789fab"
          strokeWidth={2}
        />
        <path d="M-13-5L9-5" stroke="#ecf7f9" strokeWidth={3} />
        <circle cx={15} cy={-21} r={4} fill="#deedf0" />
        <circle cx={23} cy={-27} r={3} fill="#deedf0" />
      </g>
    );
  return (
    <g>
      <path
        d="M-18-10L0-20L18-10L18 12L0 22L-18 12Z"
        fill="#c89c66"
        stroke="#8c704e"
        strokeWidth={2}
      />
      <path
        d="M-18-10L0 0L18-10M0 0L0 22"
        fill="none"
        stroke="#8c704e"
        strokeWidth={2}
      />
    </g>
  );
}

export function BuildingFigure({
  kind,
}: {
  kind: "farm" | "bakery" | "home" | "store";
}) {
  if (kind === "farm")
    return (
      <g data-building-kind={kind}>
        <path
          d="M-72-23L-12-23L-12 33L-72 33Z"
          fill="#aa5c42"
          stroke="#754532"
          strokeWidth={2}
        />
        <path
          d="M-79-23L-43-59L-6-23Z"
          fill="#754a3e"
          stroke="#654439"
          strokeWidth={2}
        />
        <path
          d="M-57 33L-57-5L-29-5L-29 33"
          fill="#684b3c"
          stroke="#eed9b4"
          strokeWidth={3}
        />
        <path d="M-55-3L-31 30M-31-3L-55 30" stroke="#eed9b4" strokeWidth={2} />
        <ellipse cx={44} cy={31} rx={24} ry={9} fill="#b9b9a1" />
        <path
          d="M20 30L20-27Q20-46 44-46Q68-46 68-27L68 30"
          fill="#c6c9b3"
          stroke="#858f7a"
          strokeWidth={2}
        />
        <path d="M18-28Q44-59 70-28Z" fill="#889581" />
        <path
          d="M28-21L28 23M34-23L34 25M40-24L40 26"
          stroke="#dde0cb"
          strokeWidth={2}
        />
      </g>
    );
  if (kind === "home")
    return (
      <g data-building-kind={kind}>
        <path
          d="M-60-28L-60 33L60 33L60-28Z"
          fill="#dfceab"
          stroke="#a88f6c"
          strokeWidth={2}
        />
        <path
          d="M-71-26L0-74L71-26Z"
          fill="#9c5b46"
          stroke="#744536"
          strokeWidth={2}
        />
        <rect x={34} y={-68} width={12} height={24} fill="#a07857" />
        <rect x={-15} y={-4} width={28} height={37} fill="#7b6750" />
        <rect
          x={-46}
          y={-11}
          width={22}
          height={22}
          fill="#b4d4d5"
          stroke="#fbf1d6"
          strokeWidth={3}
        />
        <rect
          x={27}
          y={-11}
          width={22}
          height={22}
          fill="#b4d4d5"
          stroke="#fbf1d6"
          strokeWidth={3}
        />
      </g>
    );
  return (
    <g data-building-kind={kind}>
      <path
        d="M-70-36L-70 33L70 33L70-36Z"
        fill={kind === "bakery" ? "#e5cca7" : "#bbcab8"}
        stroke="#87967f"
        strokeWidth={2}
      />
      <path
        d="M-80-35L-51-64L80-64L71-35Z"
        fill={kind === "bakery" ? "#ae7653" : "#687d6d"}
        stroke="#616f5b"
        strokeWidth={2}
      />
      <rect
        x={-48}
        y={-18}
        width={48}
        height={31}
        fill="#bad7d4"
        stroke="#ede5cd"
        strokeWidth={3}
      />
      <rect x={22} y={-15} width={25} height={48} fill="#766951" />
      {kind === "bakery" ? (
        <g>
          <rect x={39} y={-86} width={17} height={30} fill="#97765a" />
          <path d="M-59-19L6-19L1-7L-54-7Z" fill="#e5b676" />
          <path
            d="M-46-19L-44-7M-25-19L-24-7M-5-19L-6-7"
            stroke="#fff0d1"
            strokeWidth={8}
          />
        </g>
      ) : (
        <g>
          <rect x={-34} y={-6} width={14} height={14} fill="#c19b64" />
          <rect x={-17} y={-6} width={14} height={14} fill="#c19b64" />
        </g>
      )}
    </g>
  );
}
