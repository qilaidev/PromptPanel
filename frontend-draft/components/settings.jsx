// Settings — three sub-tabs. Status only when something's wrong.
// Exposes "show footer" toggle for Quick Panel. Neutral tab underline.

function SettingsRow({ label, hint, control, inline = true }) {
  return (
    <div style={{
      display: 'flex',
      flexDirection: inline ? 'row' : 'column',
      alignItems: inline ? 'center' : 'stretch',
      gap: inline ? 14 : 6,
      padding: '14px 0',
      borderBottom: '0.5px solid ' + T.divider,
    }}>
      <div style={{ flex: inline ? 1 : undefined, minWidth: 0 }}>
        <div style={{ fontSize: 13, color: T.text, fontWeight: 500 }}>{label}</div>
        {hint && <div style={{
          fontSize: 11.5, color: T.textTertiary, marginTop: 2, lineHeight: 1.5,
        }}>{hint}</div>}
      </div>
      <div style={{ flexShrink: 0, display: 'flex', alignItems: 'center', gap: 8 }}>
        {control}
      </div>
    </div>
  );
}

function SettingsSection({ title, children }) {
  return (
    <div style={{ marginBottom: 28 }}>
      <div style={{
        fontSize: 10.5, fontWeight: 600,
        color: T.textQuaternary, letterSpacing: 0.8,
        textTransform: 'uppercase',
        marginBottom: 4, padding: '0 2px',
      }}>{title}</div>
      <div>{children}</div>
    </div>
  );
}

function Toggle({ on, onChange }) {
  return (
    <button onClick={() => onChange(!on)} style={{
      width: 30, height: 17, padding: 2,
      borderRadius: 999, border: 'none',
      background: on ? T.accent : 'rgba(255,255,255,0.12)',
      cursor: 'pointer', position: 'relative',
      transition: 'background 0.15s',
    }}>
      <div style={{
        width: 13, height: 13, borderRadius: '50%',
        background: '#fff',
        transform: on ? 'translateX(13px)' : 'translateX(0)',
        transition: 'transform 0.15s',
      }} />
    </button>
  );
}

function Btn({ icon, children, variant = 'default', onClick }) {
  const isPrimary = variant === 'primary';
  const isDanger = variant === 'danger';
  return (
    <button onClick={onClick} style={{
      display: 'inline-flex', alignItems: 'center', gap: 5,
      height: 26, padding: '0 10px',
      background: isPrimary ? T.accent
        : isDanger ? 'transparent'
        : 'rgba(255,255,255,0.06)',
      border: '0.5px solid ' + (isPrimary ? 'transparent'
        : isDanger ? 'rgba(212,112,112,0.3)'
        : T.border),
      borderRadius: 6,
      color: isPrimary ? '#fff' : isDanger ? T.danger : T.text,
      fontFamily: T.font, fontSize: 11.5, fontWeight: 500, cursor: 'pointer',
    }}>
      {icon && <Icon name={icon} size={11} />}{children}
    </button>
  );
}

// Quiet status: only shows when there's something non-green.
// Normal state: a single small inline hint.
function StatusLine({ hasIssue }) {
  if (!hasIssue) {
    return (
      <div style={{
        display: 'flex', alignItems: 'center', gap: 8,
        padding: '6px 0 18px', fontSize: 11.5,
        color: T.textQuaternary,
      }}>
        <span style={{
          width: 5, height: 5, borderRadius: '50%', background: T.success,
          boxShadow: '0 0 0 2.5px ' + T.successDim,
        }} />
        运行正常 · 11 条词条 · 最近备份 今天 06:07
        <div style={{ flex: 1 }} />
        <span style={{ fontFamily: T.fontMono, fontSize: 11, color: T.textQuaternary }}>
          v1.0.0
        </span>
      </div>
    );
  }
  return (
    <div style={{
      display: 'flex', alignItems: 'center', gap: 10,
      padding: '10px 14px', marginBottom: 20,
      background: T.warnDim,
      border: '0.5px solid rgba(212,163,90,0.25)',
      borderRadius: 8, fontSize: 12,
    }}>
      <Icon name="info" size={13} style={{ color: T.warn }} />
      <span style={{ color: T.text, fontWeight: 500 }}>辅助功能权限未开启</span>
      <span style={{ color: T.textTertiary }}>
        快捷键无法监听，面板呼不出来。
      </span>
      <div style={{ flex: 1 }} />
      <Btn variant="primary">前往授权</Btn>
    </div>
  );
}

function GeneralTab({ prefs, setPrefs }) {
  const [recording, setRecording] = React.useState(false);

  return (
    <div>
      <SettingsSection title="快捷键">
        <SettingsRow
          label="呼出面板"
          hint="这是呼出快捷面板唯一的入口。"
          control={
            <button onClick={() => setRecording(!recording)} style={{
              display: 'inline-flex', alignItems: 'center', gap: 6,
              minWidth: 100, height: 28, padding: '0 12px',
              background: recording ? T.accentDim : T.surfaceRaised,
              border: '0.5px solid ' + (recording ? T.accentBorder : T.border),
              borderRadius: 6, cursor: 'pointer',
              fontFamily: T.fontMono, fontSize: 12.5,
              color: recording ? T.accent : T.text, fontWeight: 500,
              justifyContent: 'center',
            }}>
              {recording ? '按下组合键…' : '⌥ 2'}
            </button>
          }
        />
      </SettingsSection>

      <SettingsSection title="面板行为">
        <SettingsRow
          label="固定面板"
          hint="关闭时面板失焦自动收起，更利落。"
          control={<Toggle on={prefs.pinPanel} onChange={v => setPrefs({ ...prefs, pinPanel: v })} />}
        />
        <SettingsRow
          label="执行后关闭"
          hint="粘贴后自动收起面板，不留痕。"
          control={<Toggle on={prefs.closeAfterRun} onChange={v => setPrefs({ ...prefs, closeAfterRun: v })} />}
        />
        <SettingsRow
          label="默认作用域"
          hint="面板打开时预置的项目筛选。"
          control={
            <select
              value={prefs.scope}
              onChange={e => setPrefs({ ...prefs, scope: e.target.value })}
              style={{
                height: 26, padding: '0 26px 0 10px',
                background: T.surfaceRaised,
                border: '0.5px solid ' + T.border,
                borderRadius: 6, color: T.text,
                fontFamily: T.font, fontSize: 11.5,
                appearance: 'none', cursor: 'pointer',
              }}>
              <option value="current">当前执行项目</option>
              <option value="all">全部</option>
              <option value="common">通用项目</option>
            </select>
          }
        />
        <SettingsRow
          label="显示键盘提示栏"
          hint="面板底部显示 ⏎/⌘C/⌘1-9 等提示。熟练后可关闭。"
          control={<Toggle on={prefs.showFooter} onChange={v => setPrefs({ ...prefs, showFooter: v })} />}
        />
        <SettingsRow
          label="紧凑行高"
          hint="每行更紧凑，一屏可见更多词条（约 12 条）。"
          control={<Toggle on={prefs.compact} onChange={v => setPrefs({ ...prefs, compact: v })} />}
        />
      </SettingsSection>

      <SettingsSection title="权限与启动">
        <SettingsRow
          label="辅助功能权限"
          hint="用于监听快捷键和自动粘贴。"
          control={
            <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
              <span style={{
                display: 'inline-flex', alignItems: 'center', gap: 4,
                color: T.success, fontSize: 11.5, fontWeight: 500,
                padding: '2px 7px', borderRadius: 4, background: T.successDim,
              }}>
                <Icon name="check" size={10} />已授权
              </span>
              <Btn icon="refresh">重新检测</Btn>
            </div>
          }
        />
        <SettingsRow
          label="登录时启动"
          hint="系统启动时自动在后台运行。"
          control={<Toggle on={prefs.launchAtLogin} onChange={v => setPrefs({ ...prefs, launchAtLogin: v })} />}
        />
      </SettingsSection>
    </div>
  );
}

function BackupTab() {
  const [open, setOpen] = React.useState(false);
  return (
    <div>
      <SettingsSection title="备份">
        <SettingsRow
          label="自动备份"
          hint="每次启动时备份一次，最多保留 7 份。"
          control={<Toggle on={true} onChange={() => {}} />}
        />
        <SettingsRow
          label="备份状态"
          hint="当前已保存 1 / 7 份，最近一次：今天 06:07。"
          control={
            <div style={{ display: 'flex', gap: 6 }}>
              <Btn icon="database">备份目录</Btn>
              <Btn icon="plus" variant="primary">立即备份</Btn>
            </div>
          }
        />
      </SettingsSection>

      <SettingsSection title="维护">
        <SettingsRow label="刷新状态" hint="重新读取数据库和权限状态。"
          control={<Btn icon="refresh">刷新</Btn>} />
        <SettingsRow label="清理旧日志" hint="当前日志目录约占 4.2 MB。"
          control={<Btn icon="trash" variant="danger">清理</Btn>} />
      </SettingsSection>

      <SettingsSection title="数据位置">
        <div style={{
          border: '0.5px solid ' + T.border,
          borderRadius: 8, background: 'rgba(0,0,0,0.15)',
        }}>
          <button onClick={() => setOpen(!open)} style={{
            display: 'flex', alignItems: 'center', gap: 8,
            width: '100%', padding: '12px 14px',
            background: 'transparent', border: 'none',
            color: T.textSecondary, cursor: 'pointer',
            fontFamily: T.font, fontSize: 12,
          }}>
            <Icon name={open ? 'chev-down' : 'chev-right'} size={11} style={{ color: T.textTertiary }} />
            <span style={{ color: T.text, fontWeight: 500 }}>文件路径</span>
            <span style={{ color: T.textQuaternary, fontSize: 11 }}>
              落盘、备份、恢复隔离目录
            </span>
            <div style={{ flex: 1 }} />
            <span style={{ color: T.textQuaternary, fontSize: 11 }}>
              {open ? '收起' : '展开'}
            </span>
          </button>
          {open && (
            <div style={{ padding: '2px 14px 14px 32px', display: 'flex', flexDirection: 'column', gap: 10 }}>
              {[
                ['数据库', '/var/folders/…/app-support/promptpanel.db'],
                ['备份', '/var/folders/…/app-support/Backups'],
                ['恢复隔离', '/var/folders/…/app-support/Recovery'],
                ['日志', '/var/folders/…/logs'],
              ].map(([k, v]) => (
                <div key={k}>
                  <div style={{ fontSize: 10.5, color: T.textQuaternary, letterSpacing: 0.5, marginBottom: 2 }}>{k}</div>
                  <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
                    <code style={{
                      flex: 1, fontFamily: T.fontMono, fontSize: 11, color: T.textSecondary,
                      padding: '4px 8px', borderRadius: 4, background: 'rgba(255,255,255,0.03)',
                      overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap',
                    }}>{v}</code>
                    <button style={{
                      width: 24, height: 24, display: 'inline-flex',
                      alignItems: 'center', justifyContent: 'center',
                      background: 'transparent', border: 'none',
                      borderRadius: 5, cursor: 'pointer', color: T.textTertiary,
                    }} title="复制">
                      <Icon name="copy" size={11} />
                    </button>
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>
      </SettingsSection>
    </div>
  );
}

function AboutTab() {
  return (
    <div>
      <SettingsSection title="版本">
        <SettingsRow
          label="当前版本"
          hint="PromptPanel 1.0.0 (构建 1)"
          control={<span style={{ fontFamily: T.fontMono, fontSize: 11.5, color: T.textSecondary }}>1.0.0 (1)</span>}
        />
        <SettingsRow
          label="自动更新"
          hint="当前为开发版本，未配置更新源。发布版本会自动提示新版。"
          control={<Btn icon="refresh">检查更新</Btn>}
        />
      </SettingsSection>

      <SettingsSection title="运行日志">
        <SettingsRow label="最近执行"
          control={<span style={{ color: T.textSecondary, fontSize: 12 }}>暂无</span>} />
        <SettingsRow label="最近异常"
          control={<span style={{ color: T.textSecondary, fontSize: 12 }}>暂无</span>} />
        <SettingsRow label="近 7 天" hint="执行 0 次 · 成功 0 · 失败 0"
          control={<Btn icon="doc">查看日志</Btn>} />
      </SettingsSection>
    </div>
  );
}

function Settings({ prefs, setPrefs }) {
  const [tab, setTab] = React.useState('general');
  return (
    <div style={{
      height: '100%', background: T.surface,
      display: 'flex', flexDirection: 'column', overflow: 'hidden',
    }}>
      <div style={{
        display: 'flex', alignItems: 'center', gap: 2,
        padding: '10px 20px 0',
        borderBottom: '0.5px solid ' + T.divider,
      }}>
        {[
          ['general', '通用'],
          ['backup', '备份与数据'],
          ['about', '关于'],
        ].map(([id, label]) => (
          <button key={id} onClick={() => setTab(id)} style={{
            padding: '8px 12px 10px',
            background: 'transparent', border: 'none',
            color: tab === id ? T.text : T.textTertiary,
            fontFamily: T.font, fontSize: 12.5, fontWeight: 500,
            cursor: 'pointer',
            borderBottom: '2px solid ' + (tab === id ? T.text : 'transparent'),
            marginBottom: -1,
          }}>{label}</button>
        ))}
      </div>

      <div style={{ flex: 1, overflow: 'auto' }}>
        <div style={{ maxWidth: 680, margin: '0 auto', padding: '14px 20px 40px' }}>
          <StatusLine hasIssue={false} />
          {tab === 'general' && <GeneralTab prefs={prefs} setPrefs={setPrefs} />}
          {tab === 'backup' && <BackupTab />}
          {tab === 'about' && <AboutTab />}
        </div>
      </div>
    </div>
  );
}

Object.assign(window, { Settings });
