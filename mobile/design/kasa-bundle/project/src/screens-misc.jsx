// Kasa screens — MPesa modal, Maintenance list, Submit Maintenance, Reports, Notifications, Profile

function MpesaModal({ nav, invoice }) {
  const [state, setState] = React.useState('initiate');
  const inv = invoice || MOCK.invoices[3];

  React.useEffect(() => {
    if (state === 'waiting') {
      const t = setTimeout(() => setState('success'), 3200);
      return () => clearTimeout(t);
    }
  }, [state]);

  return (
    <Screen padBottom={24}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '14px 20px' }}>
        <IconBtn icon="close" onClick={() => nav('tenantHome')} />
        <div className="kasa-display" style={{ fontSize: 14, fontWeight: 700 }}>MPESA</div>
        <div style={{ width: 42 }} />
      </div>

      {state === 'initiate' && (
        <div style={{ padding: '0 20px', display: 'flex', flexDirection: 'column', gap: 16 }}>
          <div className="kasa-display" style={{ fontSize: 28, fontWeight: 700, letterSpacing: '-0.03em', lineHeight: 1.05 }}>
            PAY WITH<br/>MPESA
          </div>
          <Card accent="primary" pad={18}>
            <Label>AMOUNT</Label>
            <div className="kasa-display" style={{ fontSize: 42, fontWeight: 700, letterSpacing: '-0.03em', lineHeight: 1, marginTop: 8 }}>
              {kes(inv.amount)}
            </div>
            <div style={{ marginTop: 10, fontFamily: 'var(--font-display)', fontSize: 11, fontWeight: 700 }}>
              {inv.id} \u00b7 UNIT {inv.unit}
            </div>
          </Card>
          <Input label="MPESA NUMBER" prefix="+254" placeholder="722 456 789" />
          <Card pad={14}>
            <div style={{ display: 'flex', gap: 12, alignItems: 'flex-start' }}>
              <Icon name="bolt" size={20} stroke={2.6} color="var(--c-secondary)" />
              <div style={{ fontFamily: 'var(--font-body)', fontSize: 12, fontWeight: 500, lineHeight: 1.4, color: 'var(--c-text-2)' }}>
                We&rsquo;ll send an STK push to your phone. Enter your MPesa PIN to confirm.
              </div>
            </div>
          </Card>
          <Button variant="primary" fullWidth size="lg" onClick={() => setState('waiting')}>
            <Icon name="phone" size={16} stroke={2.8} /> SEND STK PUSH
          </Button>
        </div>
      )}

      {state === 'waiting' && (
        <div style={{ padding: '20px 20px', display: 'flex', flexDirection: 'column', alignItems: 'center', textAlign: 'center' }}>
          <div style={{ position: 'relative', width: 180, height: 180 }}>
            <div style={{
              position: 'absolute', inset: 0, borderRadius: '50%',
              border: '3px solid var(--c-secondary)',
              animation: 'kasaPulse 1.4s ease-out infinite',
            }} />
            <div style={{
              position: 'absolute', inset: 12, borderRadius: '50%',
              border: '3px solid var(--c-secondary)',
              animation: 'kasaPulse 1.4s ease-out 0.3s infinite',
              opacity: 0.6,
            }} />
            <div style={{
              position: 'absolute', inset: 34, borderRadius: 24,
              background: 'var(--c-secondary)', color: 'var(--c-secondary-ink)',
              border: '3px solid var(--c-stroke)',
              display: 'flex', alignItems: 'center', justifyContent: 'center',
              boxShadow: '5px 5px 0 var(--c-shadow)',
            }}>
              <Icon name="phone" size={52} stroke={2.4} />
            </div>
          </div>
          <style>{`@keyframes kasaPulse { 0% { transform: scale(0.9); opacity: 0.8; } 100% { transform: scale(1.25); opacity: 0; } }`}</style>
          <div className="kasa-display" style={{ fontSize: 28, fontWeight: 700, letterSpacing: '-0.02em', marginTop: 28 }}>
            CHECK YOUR PHONE
          </div>
          <div style={{ fontFamily: 'var(--font-body)', fontSize: 14, fontWeight: 500, color: 'var(--c-text-2)', marginTop: 8, maxWidth: 280 }}>
            Enter your MPesa PIN to confirm {kes(inv.amount)} to KASA.
          </div>
          <div style={{ marginTop: 28, fontFamily: 'var(--font-mono)', fontSize: 14, fontWeight: 700, color: 'var(--c-secondary)' }}>
            00:42 remaining
          </div>
          <div style={{ marginTop: 36 }}>
            <Button variant="ghost" size="sm" onClick={() => setState('initiate')}>CANCEL</Button>
          </div>
        </div>
      )}

      {state === 'success' && (
        <div style={{ padding: '20px 20px', display: 'flex', flexDirection: 'column', alignItems: 'center', textAlign: 'center' }}>
          <div style={{
            width: 140, height: 140, borderRadius: 28,
            background: 'var(--c-primary)', color: 'var(--c-primary-ink)',
            border: '3px solid var(--c-stroke)',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            boxShadow: '6px 6px 0 var(--c-shadow)',
          }}>
            <Icon name="check" size={72} stroke={3.2} />
          </div>
          <div className="kasa-display" style={{ fontSize: 30, fontWeight: 700, letterSpacing: '-0.02em', marginTop: 28 }}>
            PAYMENT<br/>CONFIRMED
          </div>
          <div style={{ fontFamily: 'var(--font-mono)', fontSize: 13, fontWeight: 700, color: 'var(--c-text-2)', marginTop: 10, letterSpacing: '0.04em' }}>
            RECEIPT SE7X4M2QL8
          </div>
          <div className="kasa-display" style={{ fontSize: 44, fontWeight: 700, letterSpacing: '-0.03em', marginTop: 16 }}>
            {kes(inv.amount)}
          </div>
          <div style={{ marginTop: 28, width: '100%' }}>
            <Button variant="primary" fullWidth size="lg" onClick={() => nav('tenantHome')}>DONE</Button>
          </div>
        </div>
      )}

      {state === 'failure' && (
        <div style={{ padding: '20px 20px', display: 'flex', flexDirection: 'column', alignItems: 'center', textAlign: 'center' }}>
          <div style={{
            width: 140, height: 140, borderRadius: 28,
            background: 'var(--c-tertiary)', color: 'var(--c-tertiary-ink)',
            border: '3px solid var(--c-stroke)',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            boxShadow: '6px 6px 0 var(--c-shadow)',
          }}>
            <Icon name="alert" size={64} stroke={3} />
          </div>
          <div className="kasa-display" style={{ fontSize: 28, fontWeight: 700, marginTop: 28 }}>STK PUSH FAILED</div>
          <div style={{ fontFamily: 'var(--font-body)', fontSize: 13, fontWeight: 500, color: 'var(--c-text-2)', marginTop: 10, maxWidth: 280 }}>
            Timed out waiting for PIN. Please try again.
          </div>
          <div style={{ marginTop: 28, width: '100%', display: 'flex', flexDirection: 'column', gap: 10 }}>
            <Button variant="primary" fullWidth size="lg" onClick={() => setState('initiate')}>TRY AGAIN</Button>
            <Button variant="ghost" fullWidth size="md" onClick={() => nav('tenantHome')}>CANCEL</Button>
          </div>
        </div>
      )}

      {state === 'waiting' && (
        <div style={{ position: 'absolute', bottom: 44, left: 0, right: 0, padding: '0 20px' }}>
          <Button variant="ghost" size="sm" fullWidth onClick={() => setState('failure')}>(demo) simulate timeout</Button>
        </div>
      )}
    </Screen>
  );
}

const MAINT_STATUS = {
  open: { chip: 'secondary', label: 'OPEN' },
  progress: { chip: 'tertiary', label: 'IN PROGRESS' },
  resolved: { chip: 'primary', label: 'RESOLVED' },
};
const MAINT_ICON = { plumbing: 'drop', electrical: 'bolt', appliance: 'settings', general: 'wrench' };

function MaintenanceList({ nav, role }) {
  const [filter, setFilter] = React.useState('all');
  const filters = [
    { k: 'all', label: 'ALL' },
    { k: 'open', label: 'OPEN' },
    { k: 'progress', label: 'IN PROGRESS' },
    { k: 'resolved', label: 'RESOLVED' },
  ];
  let items = MOCK.maintenance;
  if (role === 'tenant') items = items.filter(m => m.unit === 'B-204' || m.unit === 'A-102');
  const shown = items.filter(m => filter === 'all' || m.status === filter);
  return (
    <Screen>
      <div style={{ padding: '16px 20px 8px' }}>
        <div className="kasa-display" style={{ fontSize: 32, fontWeight: 700, letterSpacing: '-0.03em' }}>MAINTENANCE</div>
      </div>
      <div style={{ padding: '8px 20px 14px', display: 'flex', gap: 8, overflowX: 'auto' }}>
        {filters.map(f => (
          <Chip key={f.k} variant={filter === f.k ? 'secondary' : 'neutral'} onClick={() => setFilter(f.k)}>
            {f.label}
          </Chip>
        ))}
      </div>
      <div style={{ padding: '0 20px', display: 'flex', flexDirection: 'column', gap: 10 }}>
        {shown.map(m => {
          const s = MAINT_STATUS[m.status];
          const c = s.chip;
          return (
            <div key={m.id} style={{
              display: 'flex',
              background: 'var(--c-card)',
              border: '2px solid var(--c-stroke)',
              borderLeft: `8px solid var(--c-${c})`,
              borderRadius: 'var(--kasa-radius-md)',
              boxShadow: '4px 4px 0 var(--c-shadow)',
              overflow: 'hidden',
            }}>
              <div style={{
                width: 52, display: 'flex', alignItems: 'center', justifyContent: 'center',
                borderRight: '2px solid var(--c-stroke)',
                background: 'var(--c-elev)',
              }}>
                <Icon name={MAINT_ICON[m.category]} size={22} stroke={2.4} />
              </div>
              <div style={{ flex: 1, padding: 14, display: 'flex', alignItems: 'center', gap: 10 }}>
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div className="kasa-display" style={{ fontSize: 14, fontWeight: 700, letterSpacing: '-0.01em' }}>
                    {m.title.toUpperCase()}
                  </div>
                  <div style={{ fontFamily: 'var(--font-body)', fontSize: 11, color: 'var(--c-text-2)', fontWeight: 500, marginTop: 3 }}>
                    {m.property} \u00b7 {m.unit}
                  </div>
                  <div style={{ fontFamily: 'var(--font-display)', fontSize: 10, fontWeight: 700, color: 'var(--c-text-2)', marginTop: 6, letterSpacing: '0.04em' }}>
                    SUBMITTED {m.submitted}
                  </div>
                </div>
                <Chip variant={c} size="sm">{s.label}</Chip>
              </div>
            </div>
          );
        })}
      </div>
      {/* FAB */}
      <button onClick={() => nav('newMaintenance')} style={{
        position: 'absolute', bottom: 108, right: 24, zIndex: 30,
        background: 'var(--c-primary)', color: 'var(--c-primary-ink)',
        border: '3px solid var(--c-stroke)',
        borderRadius: 999,
        padding: '14px 20px',
        boxShadow: '4px 4px 0 var(--c-shadow)',
        cursor: 'pointer',
        fontFamily: 'var(--font-display)', fontSize: 13, fontWeight: 700, letterSpacing: '-0.01em',
        display: 'flex', alignItems: 'center', gap: 8,
      }}>
        <Icon name="plus" size={18} stroke={3.2} /> NEW
      </button>
    </Screen>
  );
}

function NewMaintenance({ nav }) {
  const [cat, setCat] = React.useState('plumbing');
  const [pri, setPri] = React.useState('medium');
  return (
    <Screen>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '14px 20px' }}>
        <IconBtn icon="close" onClick={() => nav('maintenance')} />
        <div className="kasa-display" style={{ fontSize: 15, fontWeight: 700 }}>NEW REQUEST</div>
        <div style={{ width: 42 }} />
      </div>
      <div style={{ padding: '12px 20px', display: 'flex', flexDirection: 'column', gap: 14 }}>
        <div>
          <Label style={{ marginBottom: 8 }}>CATEGORY</Label>
          <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8 }}>
            {['plumbing', 'electrical', 'appliance', 'general'].map(c => (
              <Chip key={c} variant={cat === c ? 'secondary' : 'neutral'} onClick={() => setCat(c)}>
                {c}
              </Chip>
            ))}
          </div>
        </div>
        <div>
          <Label style={{ marginBottom: 8 }}>PRIORITY</Label>
          <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8 }}>
            {[
              { k: 'low', v: 'neutral' },
              { k: 'medium', v: 'secondary' },
              { k: 'high', v: 'tertiary' },
              { k: 'urgent', v: 'primary' },
            ].map(p => (
              <Chip key={p.k} variant={pri === p.k ? p.v : 'neutral'} onClick={() => setPri(p.k)}>
                {p.k}
              </Chip>
            ))}
          </div>
        </div>
        <Input label="ISSUE TITLE" placeholder="Kitchen tap leak" />
        <div>
          <Label style={{ marginBottom: 8 }}>DESCRIPTION</Label>
          <div style={{
            background: 'var(--c-card)', border: '2px solid var(--c-stroke)',
            borderRadius: 14, padding: '14px 16px', minHeight: 100,
            boxShadow: '3px 3px 0 var(--c-shadow)',
            fontFamily: 'var(--font-body)', fontSize: 14, fontWeight: 500, color: 'var(--c-text-2)',
          }}>
            The kitchen tap has been dripping for a few days...
          </div>
        </div>
        <div>
          <Label style={{ marginBottom: 8 }}>PHOTOS (MAX 4)</Label>
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: 8 }}>
            <div style={{ aspectRatio: 1, background: 'var(--c-tertiary)', border: '2px solid var(--c-stroke)', borderRadius: 10 }}>
              <svg width="100%" height="100%" style={{ opacity: 0.35 }}>
                <defs><pattern id="pup" width="16" height="16" patternUnits="userSpaceOnUse"><path d="M0 8 L8 0 L16 8 L8 16 Z" fill="none" stroke="var(--c-stroke)" strokeWidth="1"/></pattern></defs>
                <rect width="100%" height="100%" fill="url(#pup)"/>
              </svg>
            </div>
            {[1, 2, 3].map(i => (
              <div key={i} style={{
                aspectRatio: 1, border: '2px dashed var(--c-stroke)', borderRadius: 10,
                display: 'flex', alignItems: 'center', justifyContent: 'center',
                color: 'var(--c-text-2)',
              }}>
                <Icon name="plus" size={20} stroke={2.4} />
              </div>
            ))}
          </div>
        </div>
        <div style={{ marginTop: 6 }}>
          <Button variant="secondary" fullWidth size="lg" onClick={() => nav('maintenance')}>SUBMIT REQUEST</Button>
        </div>
      </div>
    </Screen>
  );
}

// Line chart for revenue over time
function LineChart() {
  const pts = [72, 68, 75, 84, 79, 88, 92, 85, 90, 95, 100, 108];
  const W = 300, H = 140, pad = 10;
  const max = 120;
  const step = (W - pad * 2) / (pts.length - 1);
  const path = pts.map((p, i) => `${i === 0 ? 'M' : 'L'} ${pad + i * step} ${H - pad - (p / max) * (H - pad * 2)}`).join(' ');
  const fill = path + ` L ${pad + (pts.length - 1) * step} ${H - pad} L ${pad} ${H - pad} Z`;
  return (
    <svg viewBox={`0 0 ${W} ${H}`} width="100%" height={H} preserveAspectRatio="none">
      <path d={fill} fill="var(--c-primary)" opacity="0.22" />
      <path d={path} fill="none" stroke="var(--c-primary)" strokeWidth="3" strokeLinejoin="round" strokeLinecap="round"/>
      {pts.map((p, i) => (
        <circle key={i} cx={pad + i * step} cy={H - pad - (p / max) * (H - pad * 2)} r="3.5" fill="var(--c-stroke)" />
      ))}
    </svg>
  );
}

function StackedBar() {
  const bars = [
    { label: '0-30', a: 60, b: 25, c: 15 },
    { label: '31-60', a: 35, b: 40, c: 25 },
    { label: '61+', a: 18, b: 22, c: 60 },
  ];
  return (
    <div style={{ display: 'flex', gap: 14, alignItems: 'flex-end', height: 160, padding: '10px 6px 0' }}>
      {bars.map(b => (
        <div key={b.label} style={{ flex: 1, display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 8 }}>
          <div style={{
            width: '100%', height: 120, display: 'flex', flexDirection: 'column',
            border: '2px solid var(--c-stroke)', borderRadius: 8, overflow: 'hidden',
          }}>
            <div style={{ flex: b.c, background: 'var(--c-secondary)' }}/>
            <div style={{ flex: b.b, background: 'var(--c-tertiary)', borderTop: '2px solid var(--c-stroke)' }}/>
            <div style={{ flex: b.a, background: 'var(--c-primary)', borderTop: '2px solid var(--c-stroke)' }}/>
          </div>
          <div style={{ fontFamily: 'var(--font-display)', fontSize: 11, fontWeight: 700 }}>{b.label}D</div>
        </div>
      ))}
    </div>
  );
}

function ReportsScreen({ theme, onTheme }) {
  const [range, setRange] = React.useState('month');
  return (
    <Screen>
      <ScreenHeader onTheme={onTheme} theme={theme} unread={3} />
      <div style={{ padding: '0 20px 12px' }}>
        <div className="kasa-display" style={{ fontSize: 32, fontWeight: 700, letterSpacing: '-0.03em' }}>REPORTS</div>
      </div>
      <div style={{ padding: '0 20px 14px', display: 'flex', gap: 8, overflowX: 'auto' }}>
        {[{ k: 'month', l: 'THIS MONTH' }, { k: 'last', l: 'LAST MONTH' }, { k: 'ytd', l: 'YTD' }].map(r => (
          <Chip key={r.k} variant={range === r.k ? 'secondary' : 'neutral'} onClick={() => setRange(r.k)}>{r.l}</Chip>
        ))}
      </div>
      <div style={{ padding: '0 20px', display: 'flex', flexDirection: 'column', gap: 12 }}>
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: 10 }}>
          <Card accent="primary" pad={12}>
            <Label>GROSS</Label>
            <div className="kasa-display" style={{ fontSize: 20, fontWeight: 700, letterSpacing: '-0.03em', lineHeight: 1, marginTop: 8 }}>
              847K
            </div>
            <div style={{ fontFamily: 'var(--font-display)', fontSize: 9, fontWeight: 700, marginTop: 4 }}>KES</div>
          </Card>
          <Card accent="secondary" pad={12}>
            <Label>COLLECT</Label>
            <div className="kasa-display" style={{ fontSize: 20, fontWeight: 700, letterSpacing: '-0.03em', lineHeight: 1, marginTop: 8 }}>
              94%
            </div>
            <div style={{ fontFamily: 'var(--font-display)', fontSize: 9, fontWeight: 700, marginTop: 4 }}>RATE</div>
          </Card>
          <Card accent="tertiary" pad={12}>
            <Label>ARREARS</Label>
            <div className="kasa-display" style={{ fontSize: 20, fontWeight: 700, letterSpacing: '-0.03em', lineHeight: 1, marginTop: 8 }}>
              112K
            </div>
            <div style={{ fontFamily: 'var(--font-display)', fontSize: 9, fontWeight: 700, marginTop: 4 }}>KES</div>
          </Card>
        </div>
        <Card pad={18}>
          <Label>REVENUE OVER TIME</Label>
          <div style={{ marginTop: 12 }}>
            <LineChart />
          </div>
          <div style={{ display: 'flex', justifyContent: 'space-between', marginTop: 4, fontFamily: 'var(--font-mono)', fontSize: 9, color: 'var(--c-text-2)', fontWeight: 700 }}>
            <span>MAY</span><span>JUL</span><span>SEP</span><span>NOV</span><span>JAN</span><span>MAR</span><span>APR</span>
          </div>
        </Card>
        <Card pad={18}>
          <Label>ARREARS AGING</Label>
          <StackedBar />
          <div style={{ display: 'flex', gap: 14, marginTop: 14, fontFamily: 'var(--font-display)', fontSize: 10, fontWeight: 700 }}>
            <LegDot c="primary" label="0-30" />
            <LegDot c="tertiary" label="31-60" />
            <LegDot c="secondary" label="61+" />
          </div>
        </Card>
        <Button variant="dark" fullWidth size="md">
          <Icon name="doc" size={16} stroke={2.6} /> EXPORT PDF
        </Button>
      </div>
    </Screen>
  );
}

function LegDot({ c, label }) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
      <div style={{ width: 14, height: 14, background: `var(--c-${c})`, border: '1.5px solid var(--c-stroke)', borderRadius: 3 }} />
      <span>{label}</span>
    </div>
  );
}

function NotificationsScreen({ nav }) {
  const [tab, setTab] = React.useState('all');
  const shown = MOCK.notifications.filter(n => tab === 'all' || n.unread);
  return (
    <Screen>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '14px 20px' }}>
        <IconBtn icon="chevLeft" onClick={() => nav('back')} />
        <div className="kasa-display" style={{ fontSize: 15, fontWeight: 700 }}>NOTIFICATIONS</div>
        <span style={{ fontFamily: 'var(--font-display)', fontSize: 11, fontWeight: 700, color: 'var(--c-secondary)', textTransform: 'uppercase' }}>MARK READ</span>
      </div>
      <div style={{ padding: '8px 20px 14px', display: 'flex', gap: 8 }}>
        <Chip variant={tab === 'all' ? 'secondary' : 'neutral'} onClick={() => setTab('all')}>ALL</Chip>
        <Chip variant={tab === 'unread' ? 'secondary' : 'neutral'} onClick={() => setTab('unread')}>UNREAD</Chip>
      </div>
      <div style={{ padding: '0 20px', display: 'flex', flexDirection: 'column', gap: 10 }}>
        {shown.map(n => (
          <div key={n.id} style={{
            background: 'var(--c-card)', border: '2px solid var(--c-stroke)',
            borderLeft: n.unread ? '6px solid var(--c-primary)' : '2px solid var(--c-stroke)',
            borderRadius: 'var(--kasa-radius-md)',
            boxShadow: '4px 4px 0 var(--c-shadow)',
            padding: 14,
            display: 'flex', gap: 12,
          }}>
            <div style={{
              width: 40, height: 40, borderRadius: 10,
              background: 'var(--c-elev)', border: '2px solid var(--c-stroke)',
              display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0,
            }}>
              <Icon name={n.type} size={18} stroke={2.4} />
            </div>
            <div style={{ flex: 1, minWidth: 0 }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', gap: 8 }}>
                <div className="kasa-display" style={{ fontSize: 13, fontWeight: n.unread ? 700 : 600, letterSpacing: '-0.01em' }}>
                  {n.heading.toUpperCase()}
                </div>
                <span style={{ fontFamily: 'var(--font-mono)', fontSize: 10, color: 'var(--c-text-2)', fontWeight: 700, flexShrink: 0 }}>{n.time}</span>
              </div>
              <div style={{ fontFamily: 'var(--font-body)', fontSize: 12, color: 'var(--c-text-2)', fontWeight: 500, marginTop: 4, lineHeight: 1.4 }}>
                {n.body}
              </div>
            </div>
          </div>
        ))}
      </div>
    </Screen>
  );
}

function ProfileScreen({ role, nav, theme, onTheme }) {
  const user = role === 'landlord' ? MOCK.landlord : MOCK.tenant;
  return (
    <Screen>
      <div style={{ padding: '14px 20px 8px' }}>
        <div className="kasa-display" style={{ fontSize: 32, fontWeight: 700, letterSpacing: '-0.03em' }}>PROFILE</div>
      </div>
      <div style={{ padding: '12px 20px', display: 'flex', flexDirection: 'column', gap: 14 }}>
        <Card pad={20}>
          <div style={{ display: 'flex', justifyContent: 'flex-end' }}>
            <Chip variant={role === 'landlord' ? 'primary' : 'secondary'} size="sm">
              {user.role}
            </Chip>
          </div>
          <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 12, marginTop: -18 }}>
            <Avatar name={user.name} size={88} accent={role === 'landlord' ? 'primary' : 'secondary'} />
            <div className="kasa-display" style={{ fontSize: 24, fontWeight: 700, letterSpacing: '-0.02em' }}>
              {user.name.toUpperCase()}
            </div>
            <div style={{ fontFamily: 'var(--font-mono)', fontSize: 12, fontWeight: 700, color: 'var(--c-text-2)', letterSpacing: '0.04em' }}>
              {user.phone}
            </div>
          </div>
        </Card>

        <Card pad={0}>
          <div style={{ padding: '14px 18px 8px' }}><Label>ACCOUNT</Label></div>
          <DetailRow label="NAME" value={user.name} />
          <DetailRow label="PHONE" value={user.phone} mono />
          <DetailRow label="EMAIL" value={user.email} last />
        </Card>

        <Card pad={16}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
            <div style={{
              width: 44, height: 44, borderRadius: 10, background: 'var(--c-primary)', color: 'var(--c-primary-ink)',
              border: '2px solid var(--c-stroke)', display: 'flex', alignItems: 'center', justifyContent: 'center',
            }}>
              <Icon name="check" size={22} stroke={3} />
            </div>
            <div style={{ flex: 1 }}>
              <div className="kasa-display" style={{ fontSize: 13, fontWeight: 700 }}>ID VERIFIED</div>
              <div style={{ fontFamily: 'var(--font-body)', fontSize: 11, color: 'var(--c-text-2)', fontWeight: 500, marginTop: 2 }}>
                National ID uploaded 03 MAR 2026
              </div>
            </div>
            <Chip variant="primary" size="sm">VERIFIED</Chip>
          </div>
        </Card>

        <Card pad={0}>
          <div style={{ padding: '14px 18px 8px' }}><Label>PREFERENCES</Label></div>
          <div style={{ padding: '14px 18px', display: 'flex', justifyContent: 'space-between', alignItems: 'center', borderBottom: '2px solid var(--c-stroke)' }}>
            <span style={{ fontFamily: 'var(--font-body)', fontSize: 14, fontWeight: 600 }}>Theme</span>
            <div style={{ display: 'flex', gap: 6 }}>
              <Chip variant={theme === 'light' ? 'secondary' : 'neutral'} size="sm" onClick={() => document.documentElement.setAttribute('data-theme', 'light')}>LIGHT</Chip>
              <Chip variant={theme === 'dark' ? 'secondary' : 'neutral'} size="sm" onClick={() => document.documentElement.setAttribute('data-theme', 'dark')}>DARK</Chip>
            </div>
          </div>
          <DetailRow label="LANGUAGE" value="English (KE)" />
          <DetailRow label="NOTIFICATIONS" value="On" last />
        </Card>

        <div style={{ display: 'flex', flexDirection: 'column', gap: 10, marginTop: 6 }}>
          <Button variant="ghost" fullWidth size="md" onClick={() => nav('login')}
            style={{ color: 'var(--c-primary)', border: '2px solid var(--c-primary)' }}>
            <Icon name="logout" size={16} stroke={2.8} /> LOG OUT
          </Button>
        </div>
        <div style={{ textAlign: 'center', fontFamily: 'var(--font-mono)', fontSize: 10, fontWeight: 700, color: 'var(--c-text-2)', marginTop: 6, letterSpacing: '0.1em' }}>
          KASA v1.0.0 \u00b7 BUILD 246
        </div>
      </div>
    </Screen>
  );
}

Object.assign(window, { MpesaModal, MaintenanceList, NewMaintenance, ReportsScreen, NotificationsScreen, ProfileScreen, LineChart, StackedBar });
