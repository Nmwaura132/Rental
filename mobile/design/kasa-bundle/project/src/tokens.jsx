// Kasa design tokens — CSS variables scoped by [data-theme]

const KASA_CSS = `
@import url('https://fonts.googleapis.com/css2?family=Outfit:wght@500;700;900&family=Space+Grotesk:wght@500;600;700&family=Inter:wght@500;600;700;800&family=JetBrains+Mono:wght@500;700&display=swap');

:root {
  --kasa-radius-sm: 12px;
  --kasa-radius-md: 16px;
  --kasa-radius-lg: 20px;
  --kasa-radius-xl: 24px;

  --kasa-border: 2px;
  --kasa-shadow-offset: 4px;

  --font-display: 'Space Grotesk', system-ui, sans-serif;
  --font-body: 'Inter', system-ui, sans-serif;
  --font-brand: 'Outfit', system-ui, sans-serif;
  --font-mono: 'JetBrains Mono', ui-monospace, monospace;

  /* Accents (palette-independent slots; role-specific below) */
  --c-primary: #FF7A66;
  --c-primary-ink: #2C0000;
  --c-secondary: #5868E0;
  --c-secondary-ink: #052496;
  --c-tertiary: #F5C842;
  --c-tertiary-ink: #4A3D00;
}

[data-theme="dark"] {
  --c-bg: #0E0E13;
  --c-card: #19191F;
  --c-elev: #25252C;
  --c-text: #F0EDF4;
  --c-text-2: #ACAAB1;
  --c-stroke: #48474D;
  --c-stroke-hard: #0A0A0F;

  --c-primary: #FF8E7F;
  --c-primary-ink: #2C0000;
  --c-secondary: #8496FF;
  --c-secondary-ink: #052496;
  --c-tertiary: #FFEDB3;
  --c-tertiary-ink: #4A3D00;

  --c-shadow: #000000;

  --kasa-house-fill: #8496FF;
  --kasa-neg: #0E0E13;
  --kasa-shadow: #000000;
  --kasa-k: #FF8E7F;
  --kasa-asa: #F0EDF4;
}

[data-theme="light"] {
  --c-bg: #F5F2ED;
  --c-card: #FFFFFF;
  --c-elev: #EBE7DF;
  --c-text: #1A1A1F;
  --c-text-2: #5A5962;
  --c-stroke: #1A1A1F;
  --c-stroke-hard: #1A1A1F;

  --c-primary: #FF7A66;
  --c-primary-ink: #2C0000;
  --c-secondary: #5868E0;
  --c-secondary-ink: #F5F2ED;
  --c-tertiary: #F5C842;
  --c-tertiary-ink: #4A3D00;

  --c-shadow: #1A1A1F;

  --kasa-house-fill: #2F3FB8;
  --kasa-neg: #F5F2ED;
  --kasa-shadow: #1A1A1F;
  --kasa-k: #FF7A66;
  --kasa-asa: #1A1A1F;
}

/* Accent palette variants */
[data-accent="citrus"] {
  --c-primary: #FF9F1C;  --c-primary-ink: #3A1A00;
  --c-secondary: #2EC4B6; --c-secondary-ink: #002A26;
  --c-tertiary: #E71D36;  --c-tertiary-ink: #FFECEC;
}
[data-accent="forest"] {
  --c-primary: #E07A5F;  --c-primary-ink: #2A0A00;
  --c-secondary: #81B29A; --c-secondary-ink: #0A2A1C;
  --c-tertiary: #F2CC8F;  --c-tertiary-ink: #3A2A00;
}

* { box-sizing: border-box; }
body { margin: 0; background: var(--c-bg); color: var(--c-text); font-family: var(--font-body); -webkit-font-smoothing: antialiased; }

.kasa-display { font-family: var(--font-display); font-weight: 700; letter-spacing: -0.02em; text-transform: uppercase; }
.kasa-body { font-family: var(--font-body); font-weight: 500; }
.kasa-mono { font-family: var(--font-mono); }

.kasa-scroll::-webkit-scrollbar { width: 0; height: 0; }
`;

function KasaStyles() {
  return <style dangerouslySetInnerHTML={{ __html: KASA_CSS }} />;
}

window.KasaStyles = KasaStyles;
