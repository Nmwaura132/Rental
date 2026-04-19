// Kasa screens — Login, Landlord Dashboard, Tenant Dashboard

function LoginScreen({ onLogin, theme, onTheme }) {
  const [role, setRole] = React.useState(null);
  return (
    <Screen padBottom={0}>
      <div style={{ display: 'flex', justifyContent: 'flex-end', padding: '12px 20px' }}>
        <IconBtn onClick={onTheme} icon={theme === 'dark' ? 'sun' : 'moon'} />
      </div>
      <div style={{ padding: '30px 24px 40px', display: 'flex', flexDirection: 'column', alignItems: 'center' }}>
        <KasaLockupStacked markSize={96} wordSize={52} />
        <div style={{
          marginTop: 14,
          fontFamily: 'var(--font-display)', fontSize: 13, fontWeight: 700,
          color: 'var(--c-text-2)', letterSpacing: '0.08em', textTransform: 'uppercase',
        }}>RENTAL. MANAGED. LOCALLY.</div>
      </div>
      <div style={{ padding: '0 24px', display: 'flex', flexDirection: 'column', gap: 16 }}>
        <Input label="Phone number" prefix="+254" placeholder="7XX XXX XXX" />
        <Input label="Password" type="password" placeholder="\u2022\u2022\u2022\u2022\u2022\u2022\u2022\u2022" />
        <Button variant="primary" fullWidth size="lg" onClick={() => onLogin(role || 'landlord')}>LOG IN</Button>
        <div style={{ textAlign: 'center', padding: '4px 0' }}>
          <a style={{
            fontFamily: 'var(--font-display)', fontSize: 13, fontWeight: 700,
            color: 'var(--c-secondary)', letterSpacing: '-0.01em',
            textDecoration: 'underline', textUnderlineOffset: 3,
            cursor: 'pointer',
          }}>FORGOT PASSWORD?</a>
        </div>

        {/* Dev role picker */}
        <div style={{
          marginTop: 20, padding: 14,
          border: '2px dashed var(--c-stroke)',
          borderRadius: 16,
        }}>
          <Label style={{ marginBottom: 10 }}>DEV \u00b7 Pick role to continue</Label>
          <div style={{ display: 'flex', gap: 10 }}>
            <Button variant="primary" size="sm" onClick={() => onLogin('landlord')} style={{ flex: 1 }}>LANDLORD</Button>
            <Button variant="secondary" size="sm" onClick={() => onLogin('tenant')} style={{ flex: 1 }}>TENANT</Button>
          </div>
        </div>
      </div>
      <div style={{
        marginTop: 28, textAlign: 'center',
        fontFamily: 'var(--font-mono)', fontSize: 11, fontWeight: 700,
        color: 'var(--c-text-2)', letterSpacing: '0.1em',
      }}>
        POWERED BY MPESA \u00b7 NAIROBI
      </div>
      <div style={{ height: 40 }} />
    </Screen>
  );
}

// Occupancy ring
function Ring({ pct, size = 120, color = 'var(--c-secondary-ink)', bg = 'rgba(0,0,0,0.15)' }) {
  const r = (size - 14) / 2;
  const c = 2 * Math.PI * r;
  return (
    <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`} style={{ transform: 'rotate(-90deg)' }}>
      <circle cx={size/2} cy={size/2} r={r} fill="none" stroke={bg} strokeWidth="10" />
      <circle cx={size/2} cy={size/2} r={r} fill="none" stroke={color} strokeWidth="10" strokeLinecap="butt"
        strokeDasharray={`${(c * pct) / 100} ${c}`} />
    </svg>
  );
}

function LandlordDashboard({ nav, theme, onTheme }) {
  const d = MOCK.revenue;
  const kpiSize = 'var(--kpi-size, 60px)';
  return (
    <Screen>
      <ScreenHeader unread={3} onBell={() => nav('notifications')} onTheme={onTheme} theme={theme} />
      <div style={{ padding: '4px 20px 24px' }}>
        <div className="kasa-display" style={{ fontSize: 28, fontWeight: 700, marginBottom: 4 }}>HABARI, WANJIRU</div>
        <div style={{ fontFamily: 'var(--font-body)', fontSize: 14, color: 'var(--c-text-2)', fontWeight: 500 }}>
          Here&rsquo;s how your portfolio is running.
        </div>
      </div>

      <div style={{ padding: '0 20px', display: 'flex', flexDirection: 'column', gap: 14 }}>
        {/* Hero — Total Revenue */}
        <Card accent="primary" pad={22}>
          <Label>TOTAL REVENUE \u00b7 {d.month}</Label>
          <div className="kasa-display" style={{ fontSize: kpiSize, fontWeight: 700, lineHeight: 1, marginTop: 10, letterSpacing: '-0.03em' }}>
            KES 847,500
          </div>
          <div style={{ marginTop: 14, display: 'flex', alignItems: 'center', gap: 10 }}>
            <div style={{
              background: 'var(--c-primary-ink)', color: 'var(--c-primary)',
              padding: '4px 10px', borderRadius: 999,
              fontFamily: 'var(--font-display)', fontSize: 11, fontWeight: 700, letterSpacing: '0.04em',
              display: 'inline-flex', alignItems: 'center', gap: 4,
            }}>
              <Icon name="arrowUp" size={11} stroke={3} /> +12.4%
            </div>
            <span style={{ fontFamily: 'var(--font-body)', fontSize: 12, fontWeight: 600 }}>vs MARCH 2026</span>
          </div>
        </Card>

        {/* 2-col: occupancy + overdue */}
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 14 }}>
          <Card accent="secondary" pad={18} style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
            <Label>OCCUPANCY</Label>
            <div style={{ position: 'relative', alignSelf: 'center', marginTop: 4 }}>
              <Ring pct={d.occupancy} size={108} color="var(--c-secondary-ink)" bg="rgba(5,36,150,0.18)" />
              <div style={{
                position: 'absolute', inset: 0, display: 'flex', flexDirection: 'column',
                alignItems: 'center', justifyContent: 'center',
              }}>
                <div className="kasa-display" style={{ fontSize: 26, fontWeight: 700, letterSpacing: '-0.04em', lineHeight: 1 }}>
                  {d.occupancy}%
                </div>
              </div>
            </div>
            <div style={{ textAlign: 'center', fontFamily: 'var(--font-display)', fontSize: 11, fontWeight: 700 }}>
              {d.occupiedUnits} / {d.totalUnits} UNITS
            </div>
          </Card>
          <Card accent="tertiary" pad={18} onClick={() => nav('invoices')}>
            <Label>OVERDUE</Label>
            <div className="kasa-display" style={{ fontSize: 54, fontWeight: 700, lineHeight: 1, marginTop: 8, letterSpacing: '-0.03em' }}>
              {d.overdueCount}
            </div>
            <div style={{ marginTop: 8, fontFamily: 'var(--font-display)', fontSize: 11, fontWeight: 700 }}>
              KES 112,000
            </div>
            <div style={{ marginTop: 14, display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
              <span style={{ fontFamily: 'var(--font-body)', fontSize: 11, fontWeight: 600 }}>VIEW</span>
              <Icon name="arrowRight" size={16} stroke={2.8} />
            </div>
          </Card>
        </div>

        {/* Quick actions */}
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: 10 }}>
          <QuickAction icon="building" label="ADD PROPERTY" accent="primary" />
          <QuickAction icon="users" label="ADD TENANT" accent="secondary" />
          <QuickAction icon="invoice" label="NEW INVOICE" accent="tertiary" />
        </div>

        {/* Activity */}
        <Card pad={0}>
          <div style={{ padding: '16px 18px 8px', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
            <Label>RECENT ACTIVITY</Label>
            <span style={{ fontFamily: 'var(--font-display)', fontSize: 11, fontWeight: 700, color: 'var(--c-text-2)' }}>VIEW ALL</span>
          </div>
          <div>
            {MOCK.activity.map((a, i) => (
              <div key={i} style={{
                display: 'flex', alignItems: 'center', gap: 14,
                padding: '14px 18px',
                borderTop: i > 0 ? '2px solid var(--c-stroke)' : 'none',
              }}>
                <div style={{
                  width: 40, height: 40, borderRadius: 10,
                  background: `var(--c-${a.accent})`,
                  color: `var(--c-${a.accent}-ink)`,
                  border: '2px solid var(--c-stroke)',
                  display: 'flex', alignItems: 'center', justifyContent: 'center',
                  flexShrink: 0,
                }}>
                  <Icon name={a.icon} size={20} stroke={2.4} />
                </div>
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{ fontFamily: 'var(--font-body)', fontSize: 14, fontWeight: 600, color: 'var(--c-text)' }}>
                    {a.text}
                  </div>
                  <div style={{ fontFamily: 'var(--font-display)', fontSize: 10, fontWeight: 700, color: 'var(--c-text-2)', marginTop: 2, letterSpacing: '0.04em' }}>
                    {a.time.toUpperCase()}
                  </div>
                </div>
              </div>
            ))}
          </div>
        </Card>
      </div>
    </Screen>
  );
}

function QuickAction({ icon, label, accent }) {
  return (
    <Card accent={accent} pad={14} style={{ display: 'flex', flexDirection: 'column', gap: 10, alignItems: 'flex-start' }}>
      <Icon name={icon} size={24} stroke={2.6} />
      <div className="kasa-display" style={{ fontSize: 11, fontWeight: 700, lineHeight: 1.2, letterSpacing: '-0.01em' }}>
        {label}
      </div>
    </Card>
  );
}

function TenantDashboard({ nav, theme, onTheme }) {
  const t = MOCK.tenant;
  const kpiSize = 'var(--kpi-size, 60px)';
  return (
    <Screen>
      <ScreenHeader unread={2} onBell={() => nav('notifications')} onTheme={onTheme} theme={theme} />
      <div style={{ padding: '4px 20px 24px' }}>
        <div className="kasa-display" style={{ fontSize: 28, fontWeight: 700, marginBottom: 4 }}>HABARI, OTIENO</div>
        <div style={{ fontFamily: 'var(--font-body)', fontSize: 14, color: 'var(--c-text-2)', fontWeight: 500 }}>
          {t.property} &middot; Unit {t.unit}
        </div>
      </div>

      <div style={{ padding: '0 20px', display: 'flex', flexDirection: 'column', gap: 14 }}>
        {/* Hero — Rent Due */}
        <Card accent="primary" pad={22}>
          <Label>RENT DUE \u00b7 1 MAY 2026</Label>
          <div className="kasa-display" style={{ fontSize: kpiSize, fontWeight: 700, lineHeight: 1, marginTop: 10, letterSpacing: '-0.03em' }}>
            KES 45,000
          </div>
          <div style={{ marginTop: 14, display: 'flex', alignItems: 'center', gap: 8 }}>
            <div style={{
              background: 'var(--c-primary-ink)', color: 'var(--c-primary)',
              padding: '4px 10px', borderRadius: 999,
              fontFamily: 'var(--font-display)', fontSize: 11, fontWeight: 700, letterSpacing: '0.04em',
            }}>14 DAYS LEFT</div>
          </div>
          <div style={{ marginTop: 16 }}>
            <Button variant="dark" fullWidth size="md" onClick={() => nav('mpesa')}>
              <Icon name="phone" size={16} stroke={2.6} /> PAY WITH MPESA
            </Button>
          </div>
        </Card>

        {/* 2-col: lease + tickets */}
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 14 }}>
          <Card accent="secondary" pad={18}>
            <Label>LEASE ENDS</Label>
            <div className="kasa-display" style={{ fontSize: 52, fontWeight: 700, lineHeight: 1, marginTop: 8, letterSpacing: '-0.04em' }}>
              94
            </div>
            <div style={{ fontFamily: 'var(--font-display)', fontSize: 11, fontWeight: 700, marginTop: 4 }}>
              DAYS \u00b7 20 JUL 2026
            </div>
            <div style={{ marginTop: 14, height: 8, background: 'rgba(5,36,150,0.18)', borderRadius: 4, overflow: 'hidden', border: '1.5px solid var(--c-stroke)' }}>
              <div style={{ width: '68%', height: '100%', background: 'var(--c-secondary-ink)' }} />
            </div>
          </Card>
          <Card accent="tertiary" pad={18}>
            <Label>TICKETS</Label>
            <div className="kasa-display" style={{ fontSize: 52, fontWeight: 700, lineHeight: 1, marginTop: 8, letterSpacing: '-0.04em' }}>
              1
            </div>
            <div style={{ fontFamily: 'var(--font-display)', fontSize: 11, fontWeight: 700, marginTop: 4 }}>
              OPEN \u00b7 1 IN PROGRESS
            </div>
            <div style={{ marginTop: 14, display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
              <span style={{ fontFamily: 'var(--font-body)', fontSize: 11, fontWeight: 600 }}>TRACK</span>
              <Icon name="arrowRight" size={16} stroke={2.8} />
            </div>
          </Card>
        </div>

        {/* Quick actions */}
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: 10 }}>
          <QuickAction icon="coin" label="PAY RENT" accent="primary" />
          <QuickAction icon="wrench" label="REPORT ISSUE" accent="tertiary" />
          <QuickAction icon="doc" label="VIEW LEASE" accent="secondary" />
        </div>

        {/* Payment history */}
        <Card pad={0}>
          <div style={{ padding: '16px 18px 8px', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
            <Label>PAYMENT HISTORY</Label>
            <span style={{ fontFamily: 'var(--font-display)', fontSize: 11, fontWeight: 700, color: 'var(--c-text-2)' }}>ALL</span>
          </div>
          {MOCK.history.map((h, i) => (
            <div key={i} style={{
              display: 'flex', alignItems: 'center', gap: 14,
              padding: '14px 18px',
              borderTop: i > 0 ? '2px solid var(--c-stroke)' : 'none',
            }}>
              <div style={{
                width: 44, height: 44, borderRadius: 10,
                background: 'var(--c-primary)', color: 'var(--c-primary-ink)',
                border: '2px solid var(--c-stroke)',
                display: 'flex', alignItems: 'center', justifyContent: 'center',
              }}>
                <Icon name="check" size={22} stroke={3} />
              </div>
              <div style={{ flex: 1 }}>
                <div style={{ fontFamily: 'var(--font-display)', fontSize: 15, fontWeight: 700, letterSpacing: '-0.01em' }}>
                  KES {h.amount.toLocaleString()}
                </div>
                <div style={{ fontFamily: 'var(--font-mono)', fontSize: 10, color: 'var(--c-text-2)', marginTop: 2 }}>
                  {h.mpesa} &middot; {h.date}
                </div>
              </div>
              <Chip variant="primary" size="sm">PAID</Chip>
            </div>
          ))}
        </Card>
      </div>
    </Screen>
  );
}

Object.assign(window, { LoginScreen, LandlordDashboard, TenantDashboard, QuickAction, Ring });
