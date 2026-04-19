// Kasa primitives — Card, Chip, Button, IconBadge, PhoneShell, BottomNav, StatusBar, Icon

// ─────────────────── PhoneShell ───────────────────
// Custom phone frame that respects theme. iOS-style by default (notch variant selectable).
function PhoneShell({ children, width = 390, height = 844, variant = 'ios', time = '9:41', onTap, style = {} }) {
  const isIOS = variant === 'ios';
  return (
    <div
      style={{
        width, height,
        borderRadius: isIOS ? 48 : 40,
        background: 'var(--c-bg)',
        border: '6px solid var(--c-stroke-hard)',
        boxShadow: '8px 8px 0 var(--c-shadow), 0 30px 60px rgba(0,0,0,0.25)',
        position: 'relative',
        overflow: 'hidden',
        display: 'flex',
        flexDirection: 'column',
        ...style,
      }}
      onClick={onTap}
    >
      {/* Notch / island */}
      {isIOS ? (
        <div style={{
          position: 'absolute', top: 10, left: '50%', transform: 'translateX(-50%)',
          width: 118, height: 34, borderRadius: 20, background: '#000', zIndex: 100,
        }} />
      ) : (
        <div style={{
          position: 'absolute', top: 14, left: '50%', transform: 'translateX(-50%)',
          width: 18, height: 18, borderRadius: '50%', background: '#000', zIndex: 100,
        }} />
      )}
      {/* Status bar */}
      <KasaStatusBar time={time} variant={variant} />
      {/* Content scroll */}
      <div className="kasa-scroll" style={{ flex: 1, overflow: 'auto', position: 'relative' }}>
        {children}
      </div>
      {/* Home indicator / gesture pill */}
      {isIOS ? (
        <div style={{
          position: 'absolute', bottom: 8, left: '50%', transform: 'translateX(-50%)',
          width: 134, height: 5, borderRadius: 4, background: 'var(--c-text)', opacity: 0.55, zIndex: 200,
        }} />
      ) : (
        <div style={{
          position: 'absolute', bottom: 10, left: '50%', transform: 'translateX(-50%)',
          width: 110, height: 4, borderRadius: 2, background: 'var(--c-text)', opacity: 0.5, zIndex: 200,
        }} />
      )}
    </div>
  );
}

function KasaStatusBar({ time = '9:41', variant = 'ios' }) {
  return (
    <div style={{
      height: variant === 'ios' ? 50 : 40,
      display: 'flex', alignItems: 'center', justifyContent: 'space-between',
      padding: variant === 'ios' ? '14px 32px 0' : '12px 20px 0',
      fontFamily: 'var(--font-display)',
      fontSize: 15, fontWeight: 700,
      color: 'var(--c-text)',
      position: 'relative', zIndex: 10,
    }}>
      <span style={{ letterSpacing: '-0.02em' }}>{time}</span>
      <div style={{ display: 'flex', gap: 6, alignItems: 'center' }}>
        {/* signal */}
        <svg width="18" height="10" viewBox="0 0 18 10" fill="none">
          <rect x="0" y="7" width="3" height="3" fill="currentColor"/>
          <rect x="5" y="5" width="3" height="5" fill="currentColor"/>
          <rect x="10" y="2" width="3" height="8" fill="currentColor"/>
          <rect x="15" y="0" width="3" height="10" fill="currentColor"/>
        </svg>
        {/* wifi */}
        <svg width="14" height="10" viewBox="0 0 14 10" fill="none">
          <path d="M7 8a1.5 1.5 0 100 3 1.5 1.5 0 000-3z" fill="currentColor"/>
          <path d="M2 5.5a7 7 0 0110 0l-1.4 1.4a5 5 0 00-7.2 0L2 5.5z" fill="currentColor"/>
          <path d="M0 3.2a10 10 0 0114 0l-1.4 1.4a8 8 0 00-11.2 0L0 3.2z" fill="currentColor"/>
        </svg>
        {/* battery */}
        <div style={{ display: 'flex', alignItems: 'center' }}>
          <div style={{ width: 22, height: 10, border: '1.5px solid currentColor', borderRadius: 3, padding: 1 }}>
            <div style={{ width: '75%', height: '100%', background: 'currentColor', borderRadius: 1 }}/>
          </div>
          <div style={{ width: 2, height: 4, background: 'currentColor', borderRadius: 1, marginLeft: 1 }}/>
        </div>
      </div>
    </div>
  );
}

// ─────────────────── Card ───────────────────
function Card({ children, accent, pad = 16, radius = 'md', onClick, style = {}, shadow = true }) {
  const fill =
    accent === 'primary' ? 'var(--c-primary)' :
    accent === 'secondary' ? 'var(--c-secondary)' :
    accent === 'tertiary' ? 'var(--c-tertiary)' :
    accent === 'elev' ? 'var(--c-elev)' :
    'var(--c-card)';
  const ink =
    accent === 'primary' ? 'var(--c-primary-ink)' :
    accent === 'secondary' ? 'var(--c-secondary-ink)' :
    accent === 'tertiary' ? 'var(--c-tertiary-ink)' :
    'var(--c-text)';
  const r = typeof radius === 'number' ? radius : `var(--kasa-radius-${radius})`;
  return (
    <div
      onClick={onClick}
      style={{
        background: fill,
        color: ink,
        border: `var(--kasa-border) solid var(--c-stroke)`,
        borderRadius: r,
        padding: pad,
        boxShadow: shadow ? `var(--kasa-shadow-offset) var(--kasa-shadow-offset) 0 var(--c-shadow)` : 'none',
        cursor: onClick ? 'pointer' : 'default',
        transition: 'transform 0.06s ease',
        ...style,
      }}
    >
      {children}
    </div>
  );
}

// ─────────────────── Chip ───────────────────
function Chip({ children, variant = 'neutral', size = 'md', style = {}, onClick }) {
  const bg =
    variant === 'primary' ? 'var(--c-primary)' :
    variant === 'secondary' ? 'var(--c-secondary)' :
    variant === 'tertiary' ? 'var(--c-tertiary)' :
    variant === 'active' ? 'var(--c-secondary)' :
    'transparent';
  const ink =
    variant === 'primary' ? 'var(--c-primary-ink)' :
    variant === 'secondary' ? 'var(--c-secondary-ink)' :
    variant === 'tertiary' ? 'var(--c-tertiary-ink)' :
    variant === 'active' ? 'var(--c-secondary-ink)' :
    'var(--c-text)';
  const p = size === 'sm' ? '4px 10px' : '6px 12px';
  const fs = size === 'sm' ? 11 : 12;
  return (
    <span
      onClick={onClick}
      style={{
        display: 'inline-flex', alignItems: 'center', gap: 6,
        background: bg, color: ink,
        padding: p,
        border: `2px solid var(--c-stroke)`,
        borderRadius: 999,
        fontFamily: 'var(--font-display)',
        fontSize: fs,
        fontWeight: 700,
        letterSpacing: '-0.01em',
        textTransform: 'uppercase',
        cursor: onClick ? 'pointer' : 'default',
        whiteSpace: 'nowrap',
        ...style,
      }}
    >
      {children}
    </span>
  );
}

// ─────────────────── Button ───────────────────
function Button({ children, variant = 'primary', size = 'md', onClick, style = {}, fullWidth, disabled }) {
  const map = {
    primary: { bg: 'var(--c-primary)', ink: 'var(--c-primary-ink)' },
    secondary: { bg: 'var(--c-secondary)', ink: 'var(--c-secondary-ink)' },
    tertiary: { bg: 'var(--c-tertiary)', ink: 'var(--c-tertiary-ink)' },
    ghost: { bg: 'transparent', ink: 'var(--c-text)' },
    dark: { bg: 'var(--c-text)', ink: 'var(--c-bg)' },
  };
  const { bg, ink } = map[variant] || map.primary;
  const sizes = {
    sm: { p: '8px 14px', fs: 13, h: 36 },
    md: { p: '12px 18px', fs: 14, h: 48 },
    lg: { p: '16px 22px', fs: 16, h: 56 },
  };
  const s = sizes[size];
  return (
    <button
      onClick={onClick}
      disabled={disabled}
      style={{
        background: bg, color: ink,
        border: `3px solid var(--c-stroke)`,
        borderRadius: 14,
        padding: s.p,
        minHeight: s.h,
        fontFamily: 'var(--font-display)',
        fontSize: s.fs,
        fontWeight: 700,
        letterSpacing: '-0.01em',
        textTransform: 'uppercase',
        cursor: disabled ? 'not-allowed' : 'pointer',
        boxShadow: variant === 'ghost' ? 'none' : 'var(--kasa-shadow-offset) var(--kasa-shadow-offset) 0 var(--c-shadow)',
        width: fullWidth ? '100%' : undefined,
        opacity: disabled ? 0.5 : 1,
        display: 'inline-flex', alignItems: 'center', justifyContent: 'center', gap: 8,
        ...style,
      }}
    >
      {children}
    </button>
  );
}

// ─────────────────── Input ───────────────────
function Input({ label, prefix, placeholder, type = 'text', value, onChange, style = {} }) {
  return (
    <label style={{ display: 'block', ...style }}>
      {label && (
        <div style={{
          fontFamily: 'var(--font-display)',
          fontSize: 11, fontWeight: 700, letterSpacing: '0.04em',
          textTransform: 'uppercase', color: 'var(--c-text-2)', marginBottom: 8,
        }}>{label}</div>
      )}
      <div style={{
        display: 'flex', alignItems: 'center',
        background: 'var(--c-card)',
        border: `2px solid var(--c-stroke)`,
        borderRadius: 14,
        padding: '14px 16px',
        gap: 10,
        boxShadow: `3px 3px 0 var(--c-shadow)`,
      }}>
        {prefix && <span style={{ fontFamily: 'var(--font-mono)', fontSize: 15, fontWeight: 600, color: 'var(--c-text)' }}>{prefix}</span>}
        <input
          type={type}
          placeholder={placeholder}
          value={value}
          onChange={onChange}
          style={{
            flex: 1, border: 'none', background: 'transparent', outline: 'none',
            fontFamily: 'var(--font-body)', fontSize: 16, fontWeight: 600,
            color: 'var(--c-text)',
          }}
        />
      </div>
    </label>
  );
}

// ─────────────────── Icon (stroke-based SVG glyphs) ───────────────────
function Icon({ name, size = 24, color = 'currentColor', stroke = 2.4 }) {
  const paths = {
    bell: <><path d="M6 16V11a6 6 0 1112 0v5l1.5 2h-15L6 16z"/><path d="M10 21a2 2 0 004 0"/></>,
    home: <><path d="M3 11l9-7 9 7v9a1 1 0 01-1 1h-5v-7h-6v7H4a1 1 0 01-1-1v-9z"/></>,
    building: <><rect x="4" y="3" width="16" height="18" rx="1"/><path d="M9 7h2M13 7h2M9 11h2M13 11h2M9 15h2M13 15h2"/></>,
    users: <><circle cx="9" cy="8" r="3"/><path d="M3 20c0-3 3-5 6-5s6 2 6 5"/><circle cx="17" cy="10" r="2.5"/><path d="M14 18c0-2 1.5-3.5 3-3.5s4 1.5 4 3.5"/></>,
    invoice: <><path d="M5 3h11l3 3v15l-3-2-2 2-2-2-2 2-2-2-3 2V3z"/><path d="M8 9h8M8 13h8M8 17h5"/></>,
    wrench: <><path d="M14 6a4 4 0 10-3.5 6L4 18.5 5.5 20 12 13.5a4 4 0 006-3.5l-3 1-1.5-1.5L14 6z"/></>,
    plus: <><path d="M12 5v14M5 12h14"/></>,
    close: <><path d="M6 6l12 12M18 6L6 18"/></>,
    chevRight: <><path d="M9 6l6 6-6 6"/></>,
    chevLeft: <><path d="M15 6l-6 6 6 6"/></>,
    chevDown: <><path d="M6 9l6 6 6-6"/></>,
    search: <><circle cx="10.5" cy="10.5" r="6"/><path d="M15 15l5 5"/></>,
    phone: <><path d="M5 4h4l2 5-3 2a12 12 0 006 6l2-3 5 2v4a2 2 0 01-2 2A16 16 0 013 6a2 2 0 012-2z"/></>,
    check: <><path d="M5 12l5 5L20 7"/></>,
    alert: <><path d="M12 4L2 20h20L12 4z"/><path d="M12 10v5M12 18v.5"/></>,
    sun: <><circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/></>,
    moon: <><path d="M20 14.5A8 8 0 119.5 4a6 6 0 0010.5 10.5z"/></>,
    coin: <><circle cx="12" cy="12" r="8"/><path d="M12 7v10M9 10h4a2 2 0 010 4H9"/></>,
    key: <><circle cx="8" cy="14" r="4"/><path d="M11.5 12L21 3M17 7l2 2M19 5l2 2"/></>,
    camera: <><path d="M4 8h3l2-3h6l2 3h3v12H4V8z"/><circle cx="12" cy="13" r="3.5"/></>,
    bolt: <><path d="M13 2L4 14h6l-1 8 9-12h-6l1-8z"/></>,
    drop: <><path d="M12 3c-4 5-6 8-6 11a6 6 0 0012 0c0-3-2-6-6-11z"/></>,
    grid: <><rect x="4" y="4" width="7" height="7"/><rect x="13" y="4" width="7" height="7"/><rect x="4" y="13" width="7" height="7"/><rect x="13" y="13" width="7" height="7"/></>,
    doc: <><path d="M6 3h8l4 4v14H6V3z"/><path d="M14 3v4h4"/></>,
    arrowUp: <><path d="M12 19V5M5 12l7-7 7 7"/></>,
    arrowRight: <><path d="M5 12h14M13 5l7 7-7 7"/></>,
    logout: <><path d="M10 4H5v16h5"/><path d="M16 8l4 4-4 4M20 12H9"/></>,
    settings: <><circle cx="12" cy="12" r="3"/><path d="M19 12a7 7 0 00-.2-1.6l2-1.5-2-3.4-2.3 1a7 7 0 00-2.7-1.6L13 2h-4l-.8 2.9a7 7 0 00-2.7 1.6l-2.3-1-2 3.4 2 1.5a7 7 0 000 3.2l-2 1.5 2 3.4 2.3-1a7 7 0 002.7 1.6L9 22h4l.8-2.9a7 7 0 002.7-1.6l2.3 1 2-3.4-2-1.5A7 7 0 0019 12z"/></>,
    filter: <><path d="M3 4h18l-7 9v7l-4-2v-5L3 4z"/></>,
    eye: <><path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7S2 12 2 12z"/><circle cx="12" cy="12" r="3"/></>,
  };
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth={stroke} strokeLinecap="round" strokeLinejoin="round">
      {paths[name] || paths.home}
    </svg>
  );
}

// ─────────────────── BottomNav (neo-brutalist pill) ───────────────────
function BottomNav({ tabs, active, onChange }) {
  return (
    <div style={{
      position: 'absolute', bottom: 18, left: 16, right: 16, zIndex: 40,
      background: 'var(--c-elev)',
      border: '2px solid var(--c-stroke)',
      borderRadius: 999,
      boxShadow: '4px 4px 0 var(--c-shadow)',
      display: 'flex', padding: 6,
    }}>
      {tabs.map(t => {
        const isActive = t.key === active;
        return (
          <button
            key={t.key}
            onClick={() => onChange(t.key)}
            style={{
              flex: 1, border: 'none', cursor: 'pointer',
              background: isActive ? 'var(--c-secondary)' : 'transparent',
              color: isActive ? 'var(--c-secondary-ink)' : 'var(--c-text)',
              borderRadius: 999,
              padding: '10px 4px',
              fontFamily: 'var(--font-display)',
              fontSize: 10, fontWeight: 700, textTransform: 'uppercase',
              letterSpacing: '0.02em',
              display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 3,
              minHeight: 44,
              transition: 'background 0.15s',
            }}
          >
            <Icon name={t.icon} size={20} stroke={isActive ? 2.6 : 2.2} />
            <span style={{ fontSize: 9 }}>{t.label}</span>
          </button>
        );
      })}
    </div>
  );
}

// ─────────────────── Header (logo + bell + theme) ───────────────────
function ScreenHeader({ unread = 0, onBell, onTheme, theme, onBack, title }) {
  return (
    <div style={{
      display: 'flex', alignItems: 'center', justifyContent: 'space-between',
      padding: '12px 20px 14px',
    }}>
      {onBack ? (
        <IconBtn onClick={onBack} icon="chevLeft" />
      ) : (
        <KasaLockupHorizontal size={22} />
      )}
      {title && (
        <span className="kasa-display" style={{ fontSize: 16, fontWeight: 700 }}>{title}</span>
      )}
      <div style={{ display: 'flex', gap: 8 }}>
        <IconBtn onClick={onBell} icon="bell" badge={unread} />
        <IconBtn onClick={onTheme} icon={theme === 'dark' ? 'sun' : 'moon'} />
      </div>
    </div>
  );
}

function IconBtn({ icon, onClick, badge, accent }) {
  return (
    <button
      onClick={onClick}
      style={{
        width: 42, height: 42, borderRadius: 12,
        background: accent === 'primary' ? 'var(--c-primary)' : 'var(--c-card)',
        border: '2px solid var(--c-stroke)',
        boxShadow: '3px 3px 0 var(--c-shadow)',
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        cursor: 'pointer', position: 'relative',
        color: 'var(--c-text)',
      }}
    >
      <Icon name={icon} size={20} />
      {badge > 0 && (
        <span style={{
          position: 'absolute', top: -6, right: -6,
          background: 'var(--c-primary)', color: 'var(--c-primary-ink)',
          border: '2px solid var(--c-stroke)', borderRadius: 999,
          minWidth: 22, height: 22, padding: '0 6px',
          fontFamily: 'var(--font-display)', fontSize: 11, fontWeight: 700,
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          lineHeight: 1,
        }}>{badge}</span>
      )}
    </button>
  );
}

// ─────────────────── Screen scaffold ───────────────────
function Screen({ children, padBottom = 108, bg }) {
  return (
    <div style={{ minHeight: '100%', background: bg || 'var(--c-bg)', color: 'var(--c-text)', paddingBottom: padBottom }}>
      {children}
    </div>
  );
}

// ─────────────────── Helpers ───────────────────
function kes(n) {
  return 'KES ' + n.toLocaleString('en-KE');
}

// Tile-pattern SVG placeholder for image slots
function TilePattern({ height = 200, accent = 'tertiary', label }) {
  const bg = accent === 'tertiary' ? 'var(--c-tertiary)' :
             accent === 'secondary' ? 'var(--c-secondary)' :
             accent === 'primary' ? 'var(--c-primary)' : 'var(--c-elev)';
  return (
    <div style={{
      height, background: bg,
      border: '2px solid var(--c-stroke)',
      borderRadius: 'var(--kasa-radius-lg)',
      position: 'relative', overflow: 'hidden',
      boxShadow: '4px 4px 0 var(--c-shadow)',
    }}>
      <svg width="100%" height="100%" style={{ position: 'absolute', inset: 0, opacity: 0.3 }}>
        <defs>
          <pattern id={'p'+accent} width="28" height="28" patternUnits="userSpaceOnUse">
            <path d="M0 14 L14 0 L28 14 L14 28 Z" fill="none" stroke="var(--c-stroke)" strokeWidth="1.5"/>
          </pattern>
        </defs>
        <rect width="100%" height="100%" fill={'url(#p'+accent+')'} />
      </svg>
      {label && (
        <div style={{
          position: 'absolute', bottom: 12, left: 14,
          fontFamily: 'var(--font-mono)', fontSize: 11, fontWeight: 700,
          color: 'var(--c-stroke)', textTransform: 'uppercase', letterSpacing: '0.08em',
          background: 'var(--c-bg)', padding: '4px 8px', borderRadius: 4,
          border: '1.5px solid var(--c-stroke)',
        }}>{label}</div>
      )}
    </div>
  );
}

// Avatar with initials
function Avatar({ name, size = 40, accent = 'primary' }) {
  const initials = name.split(' ').map(s => s[0]).slice(0, 2).join('');
  const bg = accent === 'primary' ? 'var(--c-primary)' :
             accent === 'secondary' ? 'var(--c-secondary)' :
             'var(--c-tertiary)';
  const ink = accent === 'primary' ? 'var(--c-primary-ink)' :
              accent === 'secondary' ? 'var(--c-secondary-ink)' :
              'var(--c-tertiary-ink)';
  return (
    <div style={{
      width: size, height: size, borderRadius: '50%',
      background: bg, color: ink,
      border: '2px solid var(--c-stroke)',
      display: 'flex', alignItems: 'center', justifyContent: 'center',
      fontFamily: 'var(--font-display)', fontSize: size * 0.4, fontWeight: 700,
      flexShrink: 0,
      letterSpacing: '-0.02em',
    }}>
      {initials}
    </div>
  );
}

// KPI label (tiny caps)
function Label({ children, style = {} }) {
  return (
    <div style={{
      fontFamily: 'var(--font-display)',
      fontSize: 11, fontWeight: 700,
      letterSpacing: '0.04em',
      textTransform: 'uppercase',
      color: 'currentColor',
      opacity: 0.75,
      ...style,
    }}>{children}</div>
  );
}

Object.assign(window, {
  PhoneShell, KasaStatusBar, Card, Chip, Button, Input, Icon, BottomNav,
  ScreenHeader, IconBtn, Screen, kes, TilePattern, Avatar, Label,
});
