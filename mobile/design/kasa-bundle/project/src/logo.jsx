// Kasa logo — Single house silhouette with key-shaped negative space.
// Matches the uploaded reference: one house, key cut through as white/bg space.
// CSS vars: --kasa-house-fill, --kasa-neg, --kasa-shadow, --kasa-k, --kasa-asa

// Geometry (viewBox 96x80):
//  - House body: x [8, 88], y [30, 74]  (width 80, height 44)
//  - Roof: peak at (48, 6), eaves at (4, 30) and (92, 30) — slight overhang
//  - Key bow (circle): cx=48, cy=42, r=6.5 — carved from upper-mid of body
//  - Shaft: x [45.5, 50.5], from y=46 down to y=66 (below the bow)
//  - Teeth: two small rectangles on the right side of the shaft near the base
//      tooth1: (50.5, 58) 5w x 2.5h
//      tooth2: (50.5, 62.5) 5w x 2.5h
//  - Baseline gap: bottom of house sits at y=74 with subtle rounded corners

function KasaMark({ size = 96, shadow = true, style = {} }) {
  const h = (size * 80) / 96;
  return (
    <div style={{ display: 'inline-block', position: 'relative', width: size, height: h, ...style }}>
      {shadow && (
        <svg width={size} height={h} viewBox="0 0 96 80" style={{ position: 'absolute', inset: 0, transform: 'translate(4px, 4px)' }}>
          <MarkPaths fill="var(--kasa-shadow)" />
        </svg>
      )}
      <svg width={size} height={h} viewBox="0 0 96 80" style={{ position: 'absolute', inset: 0 }}>
        <MarkPaths fill="var(--kasa-house-fill)" />
      </svg>
    </div>
  );
}

function MarkPaths({ fill }) {
  // Outer house silhouette: rounded-bottom body + pitched roof with slight overhang.
  // Path starts bottom-left and goes clockwise.
  const house = [
    "M12 74",                 // bottom-left corner (rounded via arc)
    "Q8 74 8 70",
    "L8 32",
    "Q8 30 9.5 28.5",         // roof eave tuck
    "L46 4",                  // up the left roof slope to peak
    "Q48 2.5 50 4",           // rounded peak
    "L86.5 28.5",
    "Q88 30 88 32",
    "L88 70",
    "Q88 74 84 74",
    "Z",
  ].join(' ');

  // Key negative space (drawn in bg color, fillRule not needed since solid overlay)
  // Bow (circle)
  const bow = "M48,36 a6.5,6.5 0 1,0 0.0001,0 Z";
  // Shaft
  const shaft = "M45.5,42 L50.5,42 L50.5,68 L45.5,68 Z";
  // Teeth (notches on the right side of shaft)
  const tooth1 = "M50.5,58 L55.5,58 L55.5,60.5 L50.5,60.5 Z";
  const tooth2 = "M50.5,62.5 L55.5,62.5 L55.5,65 L50.5,65 Z";

  return (
    <g>
      {/* Single compound path: house solid + key carved out via evenodd */}
      <path
        d={`${house} ${bow} ${shaft} ${tooth1} ${tooth2}`}
        fill={fill}
        fillRule="evenodd"
      />
    </g>
  );
}

function KasaWordmark({ size = 48, style = {} }) {
  return (
    <span
      style={{
        fontFamily: "'Outfit', system-ui, sans-serif",
        fontWeight: 900,
        fontSize: size,
        letterSpacing: '-0.01em',
        lineHeight: 0.9,
        display: 'inline-flex',
        alignItems: 'baseline',
        ...style,
      }}
    >
      <span style={{ color: 'var(--kasa-k)' }}>K</span>
      <span style={{ color: 'var(--kasa-asa)' }}>ASA</span>
    </span>
  );
}

function KasaLockupHorizontal({ size = 40, style = {} }) {
  return (
    <div style={{ display: 'inline-flex', alignItems: 'center', gap: size * 0.35, ...style }}>
      <KasaMark size={size * 1.2} />
      <KasaWordmark size={size} />
    </div>
  );
}

function KasaLockupStacked({ markSize = 120, wordSize = 48, style = {} }) {
  return (
    <div style={{ display: 'inline-flex', flexDirection: 'column', alignItems: 'center', gap: 20, ...style }}>
      <KasaMark size={markSize} />
      <KasaWordmark size={wordSize} />
    </div>
  );
}

Object.assign(window, { KasaMark, KasaWordmark, KasaLockupHorizontal, KasaLockupStacked });
