// Library — three-pane: projects | entries list | preview
// Unified filter chips; preview has primary action; +N tag overflow.

function ProjectRow({ project, active, onClick }) {
  return (
    <div onClick={onClick} style={{
      display: 'flex', alignItems: 'center', gap: 8,
      height: 28, padding: '0 8px',
      borderRadius: T.rRow,
      background: active ? 'rgba(255,255,255,0.06)' : 'transparent',
      cursor: 'pointer', userSelect: 'none',
      color: active ? T.text : T.textSecondary,
      fontSize: 12.5, fontWeight: 500,
    }}>
      <Icon name="folder" size={13} style={{ color: active ? T.textSecondary : T.textTertiary }} />
      <span style={{ flex: 1, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
        {project.name}
      </span>
      {project.current && (
        <span style={{
          fontSize: 9, color: T.accent,
          padding: '1px 4px', borderRadius: 3,
          background: T.accentDim, fontWeight: 600, letterSpacing: 0.3,
        }}>当前</span>
      )}
      <span style={{
        fontFamily: T.fontMono, fontSize: 10.5, color: T.textQuaternary,
      }}>{project.count}</span>
    </div>
  );
}

function TagChips({ tags, max = 2 }) {
  const shown = tags.slice(0, max);
  const rest = tags.length - max;
  return (
    <div style={{ display: 'inline-flex', gap: 4, alignItems: 'center' }}>
      {shown.map(t => (
        <span key={t} style={{
          fontFamily: T.font, color: T.textTertiary,
          padding: '1px 5px', borderRadius: 3,
          background: 'rgba(255,255,255,0.04)',
          fontSize: 10, fontWeight: 500,
        }}>{t}</span>
      ))}
      {rest > 0 && (
        <span style={{
          fontFamily: T.fontMono, color: T.textQuaternary,
          fontSize: 10, fontWeight: 500,
        }}>+{rest}</span>
      )}
    </div>
  );
}

function EntryRow({ entry, selected, onClick }) {
  const meta = KIND_META[entry.kind] || KIND_META.note;
  return (
    <div onClick={onClick} style={{
      display: 'flex', alignItems: 'flex-start', gap: 10,
      padding: '10px 14px 10px 12px',
      cursor: 'pointer', userSelect: 'none',
      background: selected ? 'rgba(255,255,255,0.04)' : 'transparent',
      borderLeft: `2px solid ${selected ? T.accent : 'transparent'}`,
      position: 'relative',
    }}>
      <div style={{
        width: 18, height: 18, display: 'flex',
        alignItems: 'center', justifyContent: 'center',
        color: selected ? T.text : T.textSecondary,
        marginTop: 1, flexShrink: 0,
      }}>
        <Icon name={meta.icon} size={12.5} />
      </div>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{
          display: 'flex', alignItems: 'center', gap: 6, marginBottom: 2,
        }}>
          <span style={{
            fontSize: 13, fontWeight: 500, color: T.text,
            whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis',
            flex: 1, minWidth: 0,
          }}>{entry.title}</span>
          {entry.pinned && <Icon name="pin" size={10} style={{ color: T.pin, opacity: 0.9 }} />}
        </div>
        <div style={{
          fontSize: 11.5, color: T.textTertiary,
          whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis',
          marginBottom: 4,
        }}>{entry.content}</div>
        <div style={{
          display: 'flex', alignItems: 'center', gap: 8,
          fontSize: 10.5, color: T.textQuaternary,
        }}>
          <span style={{ fontFamily: T.fontMono }}>{entry.uses}次</span>
          <span style={{ opacity: 0.5 }}>·</span>
          <span>{entry.lastUsed}</span>
          <TagChips tags={entry.tags} max={2} />
        </div>
      </div>
    </div>
  );
}

function iconBtn() {
  return {
    width: 26, height: 24, display: 'inline-flex',
    alignItems: 'center', justifyContent: 'center',
    background: 'transparent', border: 'none',
    borderRadius: 5, cursor: 'pointer',
    color: T.textTertiary,
  };
}

function PrimaryBtn({ icon, children, onClick, kbd }) {
  return (
    <button onClick={onClick} style={{
      display: 'inline-flex', alignItems: 'center', gap: 6,
      height: 28, padding: '0 12px',
      background: T.accent, color: '#fff',
      border: 'none', borderRadius: 6, cursor: 'pointer',
      fontSize: 12, fontWeight: 600,
    }}>
      {icon && <Icon name={icon} size={12} />}
      {children}
      {kbd && <span style={{
        marginLeft: 2, fontFamily: T.fontMono, fontSize: 10,
        opacity: 0.7, fontWeight: 500,
      }}>{kbd}</span>}
    </button>
  );
}

function GhostBtn({ icon, children, onClick, kbd }) {
  return (
    <button onClick={onClick} style={{
      display: 'inline-flex', alignItems: 'center', gap: 6,
      height: 28, padding: '0 11px',
      background: 'rgba(255,255,255,0.05)',
      color: T.text,
      border: '0.5px solid ' + T.border,
      borderRadius: 6, cursor: 'pointer',
      fontSize: 12, fontWeight: 500,
    }}>
      {icon && <Icon name={icon} size={12} />}
      {children}
      {kbd && <span style={{
        marginLeft: 2, fontFamily: T.fontMono, fontSize: 10,
        color: T.textTertiary, fontWeight: 500,
      }}>{kbd}</span>}
    </button>
  );
}

function PreviewPane({ entry }) {
  if (!entry) {
    return (
      <div style={{
        flex: 1, display: 'flex', alignItems: 'center', justifyContent: 'center',
        color: T.textQuaternary, fontSize: 13,
      }}>选择一条词条查看</div>
    );
  }
  const meta = KIND_META[entry.kind] || KIND_META.note;
  return (
    <div style={{ flex: 1, display: 'flex', flexDirection: 'column', minWidth: 0 }}>
      {/* Header */}
      <div style={{
        padding: '14px 20px 14px',
        borderBottom: '0.5px solid ' + T.divider,
      }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 6, marginBottom: 8 }}>
          <span style={{
            display: 'inline-flex', alignItems: 'center', gap: 4,
            fontSize: 10.5, color: T.textTertiary, fontWeight: 500,
            padding: '2px 7px', borderRadius: 4,
            background: 'rgba(255,255,255,0.05)',
          }}>
            <Icon name={meta.icon} size={10} />{meta.label}
          </span>
          {entry.pinned && (
            <span style={{
              display: 'inline-flex', alignItems: 'center', gap: 3,
              fontSize: 10.5, color: T.pin, fontWeight: 500,
              padding: '2px 7px', borderRadius: 4,
              background: 'rgba(212,163,90,0.10)',
            }}>
              <Icon name="pin" size={10} />已置顶
            </span>
          )}
          <span style={{ color: T.textQuaternary, fontSize: 11, marginLeft: 2 }}>
            · {entry.uses}次使用 · {entry.lastUsed}
          </span>
          <div style={{ flex: 1 }} />
          <button style={iconBtn()} title="更多"><Icon name="dots" size={12} /></button>
        </div>
        <div style={{
          fontSize: 18, fontWeight: 600, color: T.text,
          letterSpacing: -0.1, marginBottom: 12,
        }}>{entry.title}</div>
        {/* Primary actions */}
        <div style={{ display: 'flex', gap: 6, alignItems: 'center' }}>
          <PrimaryBtn icon="copy" kbd="⌘C">复制</PrimaryBtn>
          <GhostBtn icon="return" kbd="⏎">插入到应用</GhostBtn>
          <GhostBtn icon="edit" kbd="⌘E">编辑</GhostBtn>
          <div style={{ flex: 1 }} />
          <button style={iconBtn()} title="置顶">
            <Icon name="pin" size={13} style={{ color: entry.pinned ? T.pin : T.textTertiary }} />
          </button>
          <button style={iconBtn()} title="删除">
            <Icon name="trash" size={13} />
          </button>
        </div>
      </div>

      {/* Body */}
      <div style={{ flex: 1, overflow: 'auto', padding: '16px 20px 20px' }}>
        <div style={{
          fontSize: 13, color: T.text, lineHeight: 1.7, whiteSpace: 'pre-wrap',
        }}>{entry.content}</div>
      </div>

      {/* Meta footer — single row */}
      <div style={{
        padding: '10px 20px',
        borderTop: '0.5px solid ' + T.divider,
        display: 'flex', alignItems: 'center', gap: 20,
        fontSize: 11.5,
      }}>
        <MetaInline label="标签" value={
          entry.tags.length === 0 ? <span style={{ color: T.textQuaternary }}>无</span> :
          <div style={{ display: 'flex', gap: 4, flexWrap: 'wrap' }}>
            {entry.tags.map(t => (
              <span key={t} style={{
                padding: '1px 6px', borderRadius: 3,
                background: 'rgba(255,255,255,0.05)',
                color: T.textSecondary, fontSize: 10.5, fontWeight: 500,
              }}>#{t}</span>
            ))}
          </div>
        } />
        <div style={{ width: 1, height: 16, background: T.divider }} />
        <MetaInline label="快捷键" value={
          entry.shortcut
            ? <span style={{ display: 'inline-flex', gap: 3 }}><Kbd>⌥</Kbd><Kbd>{entry.shortcut}</Kbd></span>
            : <button style={{
                background: 'transparent', border: 'none', color: T.textTertiary,
                cursor: 'pointer', fontSize: 11, fontFamily: T.font,
                textDecoration: 'underline', textDecorationStyle: 'dotted',
                textUnderlineOffset: 2,
              }}>设置</button>
        } />
      </div>
    </div>
  );
}

function MetaInline({ label, value }) {
  return (
    <div style={{ display: 'inline-flex', alignItems: 'center', gap: 8 }}>
      <span style={{ color: T.textQuaternary, fontSize: 11 }}>{label}</span>
      <span style={{ color: T.textSecondary }}>{value}</span>
    </div>
  );
}

function Library() {
  const [activeProject, setActiveProject] = React.useState('promptpanel');
  const [selectedId, setSelectedId] = React.useState('e1');
  const [query, setQuery] = React.useState('');
  const [sortBy, setSortBy] = React.useState('uses');
  const [activeFilter, setActiveFilter] = React.useState(null);

  const filtered = React.useMemo(() => {
    let list = ENTRIES;
    if (activeProject !== 'all') list = list.filter(e => e.project === activeProject);
    if (activeFilter) {
      if (activeFilter.kind === 'tag') list = list.filter(e => e.tags.includes(activeFilter.value));
      if (activeFilter.kind === 'format') list = list.filter(e => e.kind === activeFilter.value);
    }
    if (query) {
      const q = query.toLowerCase();
      list = list.filter(e =>
        e.title.toLowerCase().includes(q) ||
        e.content.toLowerCase().includes(q) ||
        e.tags.some(t => t.toLowerCase().includes(q))
      );
    }
    return [...list].sort((a, b) => {
      if (a.pinned !== b.pinned) return a.pinned ? -1 : 1;
      if (sortBy === 'uses') return b.uses - a.uses;
      if (sortBy === 'alpha') return a.title.localeCompare(b.title);
      return 0;
    });
  }, [activeProject, query, sortBy, activeFilter]);

  const selected = filtered.find(e => e.id === selectedId) || filtered[0];

  // Unified filter chips for library's middle column
  const filterChips = React.useMemo(() => {
    const scope = activeProject === 'all' ? ENTRIES : ENTRIES.filter(e => e.project === activeProject);
    const fc = new Map(), tc = new Map();
    scope.forEach(e => {
      fc.set(e.kind, (fc.get(e.kind) || 0) + 1);
      e.tags.forEach(t => tc.set(t, (tc.get(t) || 0) + 1));
    });
    return [
      ...[...fc.entries()].sort((a, b) => b[1] - a[1])
        .map(([k, n]) => ({ kind: 'format', value: k, label: KIND_META[k].label, icon: KIND_META[k].icon, count: n })),
      ...[...tc.entries()].sort((a, b) => b[1] - a[1]).slice(0, 8)
        .map(([t, n]) => ({ kind: 'tag', value: t, label: '#' + t, count: n })),
    ];
  }, [activeProject]);

  return (
    <div style={{ display: 'flex', height: '100%', background: T.surface }}>
      {/* Left: projects */}
      <div style={{
        width: 200, flexShrink: 0,
        background: T.sidebar,
        borderRight: '0.5px solid ' + T.divider,
        display: 'flex', flexDirection: 'column',
      }}>
        <div style={{
          padding: '14px 12px 8px',
          display: 'flex', alignItems: 'center', gap: 6,
        }}>
          <span style={{
            flex: 1, fontSize: 10.5, fontWeight: 600,
            color: T.textQuaternary, letterSpacing: 0.8,
            textTransform: 'uppercase',
          }}>项目</span>
          <button style={{ ...iconBtn(), width: 22, height: 22 }} title="新建项目">
            <Icon name="plus" size={12} />
          </button>
        </div>
        <div style={{ padding: '0 6px', flex: 1, overflow: 'auto' }}>
          {PROJECTS.map(p => (
            <ProjectRow key={p.id} project={p}
              active={activeProject === p.id}
              onClick={() => setActiveProject(p.id)} />
          ))}
        </div>
        <div style={{
          padding: '10px 12px',
          borderTop: '0.5px solid ' + T.divider,
          fontSize: 10.5, color: T.textQuaternary, lineHeight: 1.5,
        }}>
          <div style={{ color: T.textTertiary }}>
            面板默认在 <span style={{ color: T.textSecondary, fontWeight: 500 }}>PromptPanel</span> 中搜索
          </div>
        </div>
      </div>

      {/* Middle: list */}
      <div style={{
        width: 360, flexShrink: 0,
        background: T.surface,
        borderRight: '0.5px solid ' + T.divider,
        display: 'flex', flexDirection: 'column',
      }}>
        {/* Search */}
        <div style={{ padding: '12px 14px 10px', borderBottom: '0.5px solid ' + T.divider }}>
          <div style={{
            display: 'flex', alignItems: 'center', gap: 8,
            height: 30, padding: '0 10px',
            background: T.surfaceRaised,
            borderRadius: 7, border: '0.5px solid ' + T.border,
          }}>
            <Icon name="search" size={12} style={{ color: T.textTertiary }} />
            <input
              value={query} onChange={e => setQuery(e.target.value)}
              placeholder="搜索标题或内容"
              style={{
                flex: 1, background: 'transparent', border: 'none', outline: 'none',
                color: T.text, fontSize: 12, fontFamily: T.font,
              }}
            />
            <Kbd>⌘F</Kbd>
          </div>
        </div>

        {/* Unified filter chips */}
        <div style={{
          display: 'flex', alignItems: 'center', gap: 2,
          padding: '6px 10px', borderBottom: '0.5px solid ' + T.divider,
          overflowX: 'auto', whiteSpace: 'nowrap', scrollbarWidth: 'none',
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

        {/* Count + sort + new */}
        <div style={{
          padding: '6px 14px',
          display: 'flex', alignItems: 'center',
          fontSize: 10.5, color: T.textQuaternary,
          borderBottom: '0.5px solid ' + T.divider,
        }}>
          <span style={{ textTransform: 'uppercase', letterSpacing: 0.8, fontWeight: 500 }}>
            {filtered.length} 条
          </span>
          <div style={{ flex: 1 }} />
          <select value={sortBy} onChange={e => setSortBy(e.target.value)} style={{
            background: 'transparent', border: 'none', color: T.textTertiary,
            fontSize: 11, fontFamily: T.font, cursor: 'pointer',
            padding: '2px 4px', outline: 'none',
          }}>
            <option value="uses">按使用</option>
            <option value="recent">按最近</option>
            <option value="alpha">按字母</option>
          </select>
          <button style={{
            display: 'inline-flex', alignItems: 'center', gap: 4,
            background: 'transparent', border: 'none', cursor: 'pointer',
            color: T.textSecondary, fontSize: 11, fontWeight: 500,
            padding: '2px 7px', borderRadius: 4,
          }}>
            <Icon name="plus" size={11} />新建
          </button>
        </div>

        {/* List */}
        <div style={{ flex: 1, overflow: 'auto' }}>
          {filtered.map(entry => (
            <EntryRow key={entry.id}
              entry={entry}
              selected={selected && selected.id === entry.id}
              onClick={() => setSelectedId(entry.id)} />
          ))}
        </div>
      </div>

      {/* Right: preview */}
      <PreviewPane entry={selected} />
    </div>
  );
}

Object.assign(window, { Library });
