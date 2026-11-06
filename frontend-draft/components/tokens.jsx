// Design tokens — Linear/Things inspired dark minimal
// Cool neutral grays, single restrained accent, no saturated colors.

const T = {
  // Surfaces (cool neutrals, very low chroma)
  bg: '#0e0f11',              // desktop wallpaper bg
  surface: '#17181b',         // window body
  surfaceRaised: '#1e1f23',   // cards, inputs
  surfaceHover: '#24262b',    // hover states
  surfaceActive: '#2b2e34',   // selected row
  sidebar: '#141518',         // sidebar darker
  border: 'rgba(255,255,255,0.06)',
  borderStrong: 'rgba(255,255,255,0.10)',
  divider: 'rgba(255,255,255,0.04)',

  // Text
  text: '#e8e9ec',
  textSecondary: '#aeb3bc',
  textTertiary: '#858b96',
  textQuaternary: '#666d78',

  // Accent — single indigo/violet, low sat, used sparingly
  accent: '#7c8cf8',          // primary accent (links, selection tint)
  accentDim: 'rgba(124,140,248,0.14)',
  accentBorder: 'rgba(124,140,248,0.35)',

  // Semantic (desaturated)
  success: '#5fb37a',
  successDim: 'rgba(95,179,122,0.12)',
  warn: '#d4a35a',
  warnDim: 'rgba(212,163,90,0.12)',
  danger: '#d47070',
  dangerDim: 'rgba(212,112,112,0.12)',
  pin: '#d4a35a',

  // Typography
  font: '-apple-system, BlinkMacSystemFont, "SF Pro Text", "PingFang SC", "Helvetica Neue", sans-serif',
  fontMono: '"SF Mono", ui-monospace, "JetBrains Mono", Menlo, monospace',

  // Radii
  rWindow: 12,
  rCard: 10,
  rRow: 6,
  rPill: 999,

  // Shadows
  shadowWindow: '0 0 0 0.5px rgba(0,0,0,0.6), 0 24px 60px rgba(0,0,0,0.55), 0 4px 12px rgba(0,0,0,0.3)',
  shadowPopover: '0 0 0 0.5px rgba(0,0,0,0.4), 0 20px 48px rgba(0,0,0,0.5)',
};

// Traffic lights (non-interactive)
function TrafficLights() {
  const dot = (bg) => (
    <div style={{
      width: 12, height: 12, borderRadius: '50%', background: bg,
      boxShadow: 'inset 0 0 0 0.5px rgba(0,0,0,0.25)',
    }} />
  );
  return (
    <div style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
      {dot('#ff5f57')}{dot('#febc2e')}{dot('#28c840')}
    </div>
  );
}

// Minimal line icons (stroke-based, 16px baseline, currentColor)
function Icon({ name, size = 14, style = {} }) {
  const s = size;
  const common = { width: s, height: s, viewBox: '0 0 16 16', fill: 'none', stroke: 'currentColor', strokeWidth: 1.4, strokeLinecap: 'round', strokeLinejoin: 'round', style };
  switch (name) {
    case 'search': return <svg {...common}><circle cx="7" cy="7" r="4.5"/><path d="M10.5 10.5L13.5 13.5"/></svg>;
    case 'settings': return <svg {...common}><circle cx="8" cy="8" r="2"/><path d="M8 1.5v2M8 12.5v2M14.5 8h-2M3.5 8h-2M12.6 3.4l-1.4 1.4M4.8 11.2l-1.4 1.4M12.6 12.6l-1.4-1.4M4.8 4.8L3.4 3.4"/></svg>;
    case 'folder': return <svg {...common}><path d="M1.5 4.5a1 1 0 0 1 1-1h3l1.5 1.5h6a1 1 0 0 1 1 1v6a1 1 0 0 1-1 1h-10.5a1 1 0 0 1-1-1v-7.5z"/></svg>;
    case 'plus': return <svg {...common}><path d="M8 3v10M3 8h10"/></svg>;
    case 'pin': return <svg {...common}><path d="M9.5 1.5l5 5-2 1-3 3-1 4-4-4-3.5 3.5M6 6l4 4"/></svg>;
    case 'chev-right': return <svg {...common}><path d="M6 3l5 5-5 5"/></svg>;
    case 'chev-down': return <svg {...common}><path d="M3 6l5 5 5-5"/></svg>;
    case 'sidebar': return <svg {...common}><rect x="1.5" y="2.5" width="13" height="11" rx="1.5"/><path d="M6 2.5v11"/></svg>;
    case 'sort': return <svg {...common}><path d="M4 3v10M2 11l2 2 2-2M12 13V3M14 5l-2-2-2 2"/></svg>;
    case 'filter': return <svg {...common}><path d="M2 3h12l-4.5 5.5V13l-3-1.5V8.5L2 3z"/></svg>;
    case 'tag': return <svg {...common}><path d="M2 2h5l7 7-5 5-7-7V2z"/><circle cx="5" cy="5" r="0.8" fill="currentColor" stroke="none"/></svg>;
    case 'clock': return <svg {...common}><circle cx="8" cy="8" r="6"/><path d="M8 4.5V8l2.5 1.5"/></svg>;
    case 'dot': return <svg {...common}><circle cx="8" cy="8" r="1.5" fill="currentColor" stroke="none"/></svg>;
    case 'check': return <svg {...common}><path d="M3 8.5L6.5 12l6.5-7"/></svg>;
    case 'edit': return <svg {...common}><path d="M10.5 2.5l3 3-8 8H2.5v-3l8-8z"/></svg>;
    case 'trash': return <svg {...common}><path d="M3 4.5h10M5.5 4.5V3a1 1 0 0 1 1-1h3a1 1 0 0 1 1 1v1.5M4.5 4.5v8a1 1 0 0 0 1 1h5a1 1 0 0 0 1-1v-8M6.5 7v4M9.5 7v4"/></svg>;
    case 'copy': return <svg {...common}><rect x="5" y="5" width="8" height="8" rx="1"/><path d="M3 10V3.5a1 1 0 0 1 1-1H10"/></svg>;
    case 'arrow-down': return <svg {...common}><path d="M8 3v10M4 9l4 4 4-4"/></svg>;
    case 'arrow-updown': return <svg {...common}><path d="M4 3v10M2 11l2 2 2-2M12 13V3M14 5l-2-2-2 2"/></svg>;
    case 'return': return <svg {...common}><path d="M13 4v3a2 2 0 0 1-2 2H3M5 7L3 9l2 2"/></svg>;
    case 'command': return <svg {...common}><path d="M5.5 5.5h5v5h-5v-5zM3 5.5a2.5 2.5 0 1 1 2.5-2.5v2.5H3zM10.5 5.5V3a2.5 2.5 0 1 1 2.5 2.5h-2.5zM10.5 10.5h2.5a2.5 2.5 0 1 1-2.5 2.5v-2.5zM5.5 10.5V13a2.5 2.5 0 1 1-2.5-2.5h2.5z"/></svg>;
    case 'option': return <svg {...common}><path d="M2 3h4l4 10h4M10 3h4"/></svg>;
    case 'close': return <svg {...common}><path d="M3.5 3.5l9 9M12.5 3.5l-9 9"/></svg>;
    case 'dots': return <svg {...common}><circle cx="4" cy="8" r="1" fill="currentColor" stroke="none"/><circle cx="8" cy="8" r="1" fill="currentColor" stroke="none"/><circle cx="12" cy="8" r="1" fill="currentColor" stroke="none"/></svg>;
    case 'reply': return <svg {...common}><path d="M6 4L2 8l4 4M2 8h8a4 4 0 0 1 4 4v1"/></svg>;
    case 'chat': return <svg {...common}><path d="M2.5 4.5a1 1 0 0 1 1-1h9a1 1 0 0 1 1 1v6a1 1 0 0 1-1 1H8l-3 2.5v-2.5H3.5a1 1 0 0 1-1-1v-6z"/></svg>;
    case 'doc': return <svg {...common}><path d="M3.5 2.5h6l3 3v8a1 1 0 0 1-1 1h-8a1 1 0 0 1-1-1v-10a1 1 0 0 1 1-1zM9.5 2.5v3h3"/></svg>;
    case 'sparkles': return <svg {...common}><path d="M8 2v3M8 11v3M2 8h3M11 8h3M4 4l2 2M12 12l-2-2M4 12l2-2M12 4l-2 2"/></svg>;
    case 'lock': return <svg {...common}><rect x="3" y="7" width="10" height="7" rx="1"/><path d="M5 7V5a3 3 0 0 1 6 0v2"/></svg>;
    case 'kbd': return <svg {...common}><rect x="1.5" y="4.5" width="13" height="8" rx="1.5"/><path d="M4 7h.01M7 7h.01M10 7h.01M4 10h6"/></svg>;
    case 'keyboard': return <svg {...common}><rect x="1.5" y="4" width="13" height="8" rx="1.5"/><path d="M4 7h0M7 7h0M10 7h0M4 10h6"/></svg>;
    case 'database': return <svg {...common}><ellipse cx="8" cy="3.5" rx="5.5" ry="1.8"/><path d="M2.5 3.5v9c0 1 2.5 1.8 5.5 1.8s5.5-.8 5.5-1.8v-9M2.5 8c0 1 2.5 1.8 5.5 1.8s5.5-.8 5.5-1.8"/></svg>;
    case 'info': return <svg {...common}><circle cx="8" cy="8" r="6"/><path d="M8 7.5v3.5M8 5v.01"/></svg>;
    case 'refresh': return <svg {...common}><path d="M2 8a6 6 0 0 1 10-4.5M14 3v3h-3M14 8a6 6 0 0 1-10 4.5M2 13v-3h3"/></svg>;
    default: return <svg {...common}><circle cx="8" cy="8" r="5"/></svg>;
  }
}

// Keyboard key
function Kbd({ children, style = {} }) {
  return (
    <span style={{
      display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
      minWidth: 18, height: 18, padding: '0 5px',
      borderRadius: 4,
      background: 'rgba(255,255,255,0.06)',
      border: '0.5px solid rgba(255,255,255,0.08)',
      color: T.textSecondary,
      fontFamily: T.fontMono, fontSize: 10.5, fontWeight: 500,
      lineHeight: 1,
      ...style,
    }}>{children}</span>
  );
}

Object.assign(window, { T, TrafficLights, Icon, Kbd });
