// Quick Panel — Spotlight-style launcher
// Compact rows, keyboard-first, adaptive project scope, unified filter chips.

function PanelRow({ entry, index, selected, onClick, showNumber, dense, hideUses }) {
  const meta = KIND_META[entry.kind] || KIND_META.note;
  const h = dense ? 26 : 30;
  return (
    <div
      onClick={onClick}
      style={{
        display: 'flex', alignItems: 'center', gap: 10,
        height: h, padding: '0 12px 0 8px',
        borderRadius: T.rRow,
        background: selected ? 'rgba(124,140,248,0.12)' : 'transparent',
        cursor: 'pointer', userSelect: 'none',
        position: 'relative',
      }}
    >
      <div style={{
        width: 16, flexShrink: 0, textAlign: 'center',
        fontFamily: T.fontMono, fontSize: 10,
        color: selected ? T.accent : T.textQuaternary,
        fontWeight: 500,
      }}>
        {showNumber && index < 9 ? index + 1 : ''}
      </div>

      <div style={{
        width: 16, height: 16, display: 'flex', alignItems: 'center', justifyContent: 'center',
        color: selected ? T.text : T.textSecondary, flexShrink: 0,
      }}>
        <Icon name={meta.icon} size={12.5} />
      </div>

      <div style={{ flex: 1, minWidth: 0, display: 'flex', alignItems: 'baseline', gap: 10 }}>
        <div style={{
          fontSize: 12.5, fontWeight: 500, color: T.text,
          whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis',
          flex: '0 0 min(max(28%, 150px), 260px)',
        }}>
          {entry.title}
          {entry.pinned && (
            <Icon name="pin" size={9.5} style={{
              color: T.pin, marginLeft: 5, verticalAlign: 'middle', opacity: 0.85,
            }} />
          )}
        </div>
        <div style={{
          fontSize: 11.5, color: T.textSecondary,
          whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis',
          flex: 1, minWidth: 0,
        }}>
          {entry.content}
        </div>
      </div>

      <div style={{
        display: 'flex', alignItems: 'center', gap: 8, flexShrink: 0,
        color: T.textQuaternary, fontSize: 10.5,
      }}>
        {!hideUses && selected && <span style={{ fontFamily: T.fontMono }}>{entry.uses} 次</span>}
        <span style={{
          fontSize: 10, color: selected ? T.textSecondary : T.textTertiary,
          fontWeight: 500,
        }}>{meta.label}</span>
      </div>
    </div>
  );
}

// Project scope — adaptive: pills if ≤ MAX, else current + dropdown
function ProjectScope({ projects, active, onChange, max = 4 }) {
  const [open, setOpen] = React.useState(false);
  const current = projects.find(p => p.id === active) || projects[0];
  const shouldCollapse = projects.length > max;

  if (!shouldCollapse) {
    return (
      <div style={{ display: 'flex', alignItems: 'center', gap: 2 }}>
        {projects.map(p => (
          <button key={p.id} onClick={() => onChange(p.id)} style={{
            display: 'inline-flex', alignItems: 'center', gap: 5,
            height: 22, padding: '0 9px', borderRadius: T.rPill,
            background: active === p.id ? 'rgba(255,255,255,0.08)' : 'transparent',
            color: active === p.id ? T.text : T.textSecondary,
            border: 'none', cursor: 'pointer',
            fontFamily: T.font, fontSize: 11.5, fontWeight: 500,
            whiteSpace: 'nowrap',
          }}>
            {p.name}
            {p.current && (
              <span style={{
                fontSize: 9, color: T.accent,
                padding: '1px 4px', borderRadius: 3,
                background: T.accentDim, fontWeight: 600, letterSpacing: 0.3,
              }}>当前</span>
            )}
            <span style={{
              fontFamily: T.fontMono, fontSize: 10,
              color: active === p.id ? T.textTertiary : T.textQuaternary,
            }}>{p.count}</span>
          </button>
        ))}
      </div>
    );
  }

  // Collapsed: only current + chevron, click to open dropdown
  return (
    <div style={{ position: 'relative' }}>
      <button onClick={() => setOpen(!open)} style={{
        display: 'inline-flex', alignItems: 'center', gap: 5,
        height: 22, padding: '0 8px 0 10px', borderRadius: T.rPill,
        background: 'rgba(255,255,255,0.06)', color: T.text,
        border: 'none', cursor: 'pointer',
        fontSize: 11.5, fontWeight: 500, fontFamily: T.font,
      }}>
        <Icon name="folder" size={11} style={{ color: T.textTertiary }} />
        {current.name}
        {current.current && (
          <span style={{
            fontSize: 9, color: T.accent,
            padding: '1px 4px', borderRadius: 3,
            background: T.accentDim, fontWeight: 600, letterSpacing: 0.3,
          }}>当前</span>
        )}
        <span style={{ fontFamily: T.fontMono, fontSize: 10, color: T.textQuaternary }}>
          {current.count}
        </span>
        <Icon name="chev-down" size={10} style={{ color: T.textTertiary, marginLeft: 2 }} />
      </button>
      {open && (
        <>
          <div onClick={() => setOpen(false)} style={{
            position: 'fixed', inset: 0, zIndex: 20,
          }} />
          <div style={{
            position: 'absolute', top: 26, left: 0, zIndex: 21,
            minWidth: 200, padding: 4,
            background: T.surfaceRaised,
            border: '0.5px solid ' + T.borderStrong,
            borderRadius: 8, boxShadow: T.shadowPopover,
          }}>
            {projects.map(p => (
              <button key={p.id} onClick={() => { onChange(p.id); setOpen(false); }} style={{
                display: 'flex', alignItems: 'center', gap: 6, width: '100%',
                height: 26, padding: '0 8px', borderRadius: 5,
                background: active === p.id ? 'rgba(255,255,255,0.06)' : 'transparent',
                color: T.text, border: 'none', cursor: 'pointer',
                fontSize: 11.5, fontWeight: 500, fontFamily: T.font,
                textAlign: 'left',
              }}>
                <Icon name="folder" size={11} style={{ color: T.textTertiary }} />
                <span style={{ flex: 1 }}>{p.name}</span>
                {p.current && <span style={{
                  fontSize: 9, color: T.accent,
                  padding: '1px 4px', borderRadius: 3,
                  background: T.accentDim, fontWeight: 600,
                }}>当前</span>}
                <span style={{ fontFamily: T.fontMono, fontSize: 10, color: T.textQuaternary }}>
                  {p.count}
                </span>
              </button>
            ))}
          </div>
        </>
      )}
    </div>
  );
}

// Unified filter chip (works for tags and formats alike)
function FilterChip({ label, icon, count, active, onClick }) {
  return (
    <button onClick={onClick} style={{
      display: 'inline-flex', alignItems: 'center', gap: 4,
      height: 22, padding: '0 8px',
      background: active ? T.accentDim : 'transparent',
      color: active ? T.accent : T.textTertiary,
      border: 'none', borderRadius: 4,
      fontSize: 11, fontFamily: T.font, fontWeight: 500,
      cursor: 'pointer', whiteSpace: 'nowrap',
    }}>
      {icon && <Icon name={icon} size={10.5} />}
      {label}
      {count != null && <span style={{
        fontFamily: T.fontMono, fontSize: 9.5,
        color: active ? T.accent : T.textQuaternary, opacity: 0.8,
      }}>{count}</span>}
    </button>
  );
}

function QuickPanel({ width = 560, showFooter = true, compact = false }) {
  const [query, setQuery] = React.useState('');
  const [selectedIdx, setSelectedIdx] = React.useState(0);
  const [activeProject, setActiveProject] = React.useState('all');
  const [activeFilter, setActiveFilter] = React.useState(null); // {kind:'tag'|'format', value:string}

  const { cleanQuery, tagFilter } = React.useMemo(() => {
    const m = query.match(/#(\S+)/);
    return {
      cleanQuery: query.replace(/#\S+/g, '').trim().toLowerCase(),
      tagFilter: m ? m[1] : null,
    };
  }, [query]);

  const filtered = React.useMemo(() => {
    let list = ENTRIES;
    if (activeProject !== 'all') list = list.filter(e => e.project === activeProject);
    if (tagFilter) list = list.filter(e => e.tags.includes(tagFilter));
    else if (activeFilter) {
      if (activeFilter.kind === 'tag') list = list.filter(e => e.tags.includes(activeFilter.value));
      if (activeFilter.kind === 'format') list = list.filter(e => e.kind === activeFilter.value);
    }
    if (cleanQuery) {
      list = list.filter(e =>
        e.title.toLowerCase().includes(cleanQuery) ||
        e.content.toLowerCase().includes(cleanQuery) ||
        e.tags.some(t => t.toLowerCase().includes(cleanQuery))
      );
    }
    return [...list].sort((a, b) => {
      if (a.pinned !== b.pinned) return a.pinned ? -1 : 1;
      return b.uses - a.uses;
    });
  }, [cleanQuery, activeProject, activeFilter, tagFilter]);

  React.useEffect(() => { setSelectedIdx(0); }, [query, activeProject, activeFilter]);

  // Build unified filter list: formats present + most-used tags, in scope
  const filterChips = React.useMemo(() => {
    const scope = activeProject === 'all' ? ENTRIES : ENTRIES.filter(e => e.project === activeProject);
    const formatCounts = new Map();
    const tagCounts = new Map();
    scope.forEach(e => {
      formatCounts.set(e.kind, (formatCounts.get(e.kind) || 0) + 1);
      e.tags.forEach(t => tagCounts.set(t, (tagCounts.get(t) || 0) + 1));
    });
    const formats = [...formatCounts.entries()]
      .sort((a, b) => b[1] - a[1])
      .map(([k, n]) => ({ kind: 'format', value: k, label: KIND_META[k].label, icon: KIND_META[k].icon, count: n }));
    const tags = [...tagCounts.entries()]
      .sort((a, b) => b[1] - a[1])
      .slice(0, 6)
      .map(([t, n]) => ({ kind: 'tag', value: t, label: '#' + t, count: n }));
    return [...formats, ...tags];
  }, [activeProject]);

  const currentProjectName = PROJECTS.find(p => p.id === activeProject)?.name || '全部';

  return (
    <div style={{
      width,
      background: T.surface,
      borderRadius: 14,
      border: '0.5px solid ' + T.borderStrong,
      boxShadow: T.shadowPopover,
      overflow: 'hidden',
      fontFamily: T.font, color: T.text,
      display: 'flex', flexDirection: 'column',
    }}>
      {/* Header row: scope + search */}
      <div style={{
        display: 'flex', alignItems: 'center', gap: 10,
        padding: '10px 12px 10px',
        borderBottom: '0.5px solid ' + T.divider,
      }}>
        <ProjectScope projects={PROJECTS} active={activeProject} onChange={setActiveProject} />
        <div style={{
          width: 1, height: 16, background: T.divider, margin: '0 2px',
        }} />
        <div style={{ color: T.textTertiary, display: 'flex' }}>
          <Icon name="search" size={13} />
        </div>
        <div style={{ flex: 1, position: 'relative', minWidth: 0 }}>
          {!query && (
            <div style={{
              position: 'absolute', inset: '0 auto 0 4px',
              display: 'flex', alignItems: 'center',
              color: T.textTertiary, fontSize: 12.5, fontWeight: 500,
              pointerEvents: 'none', whiteSpace: 'nowrap',
            }}>
              搜索 {currentProjectName} 或 #标签
            </div>
          )}
          <input
            value={query}
            onChange={e => setQuery(e.target.value)}
            autoFocus
            style={{
              width: '100%', background: 'transparent', border: 'none', outline: 'none',
              color: T.text, fontSize: 13, fontFamily: T.font,
            }}
          />
        </div>
        {query && (
          <button onClick={() => setQuery('')} style={{
            background: 'transparent', border: 'none', color: T.textTertiary,
            cursor: 'pointer', padding: 2, display: 'flex',
          }}><Icon name="close" size={12} /></button>
        )}
        <button title="固定面板" style={{
          background: 'transparent', border: 'none', color: T.textTertiary,
          cursor: 'pointer', padding: 2, display: 'flex',
        }}><Icon name="pin" size={12} /></button>
      </div>

      {/* Unified filter chips — horizontally scrollable */}
      {filterChips.length > 0 && (
        <div style={{
          display: 'flex', alignItems: 'center', gap: 2,
          padding: '6px 10px', borderBottom: '0.5px solid ' + T.divider,
          overflowX: 'auto', whiteSpace: 'nowrap',
          scrollbarWidth: 'none',
        }}>
          <FilterChip label="全部" count={filtered.length}
            active={!activeFilter}
            onClick={() => setActiveFilter(null)} />
          <div style={{ width: 1, height: 14, background: T.divider, margin: '0 4px', flexShrink: 0 }} />
          {filterChips.map(c => (
            <FilterChip key={c.kind + ':' + c.value}
              label={c.label} icon={c.icon} count={c.count}
              active={activeFilter && activeFilter.kind === c.kind && activeFilter.value === c.value}
              onClick={() => setActiveFilter(
                activeFilter && activeFilter.value === c.value ? null : { kind: c.kind, value: c.value }
              )} />
          ))}
        </div>
      )}

      {/* List */}
      <div style={{ maxHeight: 420, overflow: 'auto', padding: '6px 6px' }}>
        {filtered.length === 0 ? (
          <div style={{
            padding: '40px 20px', textAlign: 'center',
            color: T.textTertiary, fontSize: 13,
          }}>
            无匹配词条
          </div>
        ) : filtered.map((entry, i) => (
          <PanelRow key={entry.id}
            entry={entry} index={i}
            selected={i === selectedIdx}
            showNumber={!query}
            dense={compact}
            onClick={() => setSelectedIdx(i)}
          />
        ))}
      </div>

      {/* Footer — optional */}
      {showFooter && (
        <div style={{
          display: 'flex', alignItems: 'center', gap: 14,
          height: 28, padding: '0 12px',
          borderTop: '0.5px solid ' + T.divider,
          color: T.textTertiary, fontSize: 10.5,
          background: 'rgba(0,0,0,0.15)',
        }}>
          <span style={{ display: 'inline-flex', alignItems: 'center', gap: 4 }}>
            <Kbd>↑↓</Kbd>选择
          </span>
          <span style={{ display: 'inline-flex', alignItems: 'center', gap: 4 }}>
            <Kbd>⏎</Kbd>执行
          </span>
          <span style={{ display: 'inline-flex', alignItems: 'center', gap: 4 }}>
            <Kbd>Esc</Kbd>关闭
          </span>
          <span style={{ display: 'inline-flex', alignItems: 'center', gap: 4 }}>
            <Kbd>⌘C</Kbd>复制
          </span>
          <span style={{ display: 'inline-flex', alignItems: 'center', gap: 4 }}>
            <Kbd>⌘1-9</Kbd>直达
          </span>
          <span style={{ display: 'inline-flex', alignItems: 'center', gap: 4 }}>
            <Kbd>⌘P</Kbd>固定
          </span>
          <div style={{ flex: 1 }} />
          <span style={{ color: T.textTertiary, fontFamily: T.fontMono }}>
            {filtered.length}/{ENTRIES.length}
          </span>
        </div>
      )}
    </div>
  );
}

Object.assign(window, { QuickPanel });
