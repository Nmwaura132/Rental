// Kasa screens — Properties, Property Detail, Add Property

function PropertiesList({ nav }) {
  return (
    <Screen>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '16px 20px 12px' }}>
        <div className="kasa-display" style={{ fontSize: 32, fontWeight: 700, letterSpacing: '-0.03em' }}>PROPERTIES</div>
        <Button variant="primary" size="sm" onClick={() => nav('addProperty')}>
          <Icon name="plus" size={14} stroke={3} /> ADD
        </Button>
      </div>

      <div style={{ padding: '4px 20px 16px' }}>
        <div style={{
          display: 'flex', alignItems: 'center', gap: 10,
          background: 'var(--c-card)', border: '2px solid var(--c-stroke)',
          borderRadius: 14, padding: '12px 16px',
          boxShadow: '3px 3px 0 var(--c-shadow)',
        }}>
          <Icon name="search" size={18} stroke={2.4} color="var(--c-text-2)" />
          <span style={{ fontFamily: 'var(--font-body)', fontSize: 14, color: 'var(--c-text-2)', fontWeight: 500 }}>
            Search properties...
          </span>
        </div>
      </div>

      <div style={{ padding: '0 20px', display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12 }}>
        {MOCK.properties.map(p => (
          <Card key={p.id} pad={0} onClick={() => nav('propertyDetail')}>
            <div style={{
              height: 80, background: `var(--c-${p.accent})`,
              borderBottom: '2px solid var(--c-stroke)',
              position: 'relative', overflow: 'hidden',
              borderRadius: 'calc(var(--kasa-radius-md) - 2px) calc(var(--kasa-radius-md) - 2px) 0 0',
            }}>
              <svg width="100%" height="100%" style={{ opacity: 0.35 }}>
                <defs>
                  <pattern id={'pt'+p.id} width="20" height="20" patternUnits="userSpaceOnUse">
                    <path d="M0 10 L10 0 L20 10 L10 20 Z" fill="none" stroke="var(--c-stroke)" strokeWidth="1.2"/>
                  </pattern>
                </defs>
                <rect width="100%" height="100%" fill={`url(#pt${p.id})`} />
              </svg>
            </div>
            <div style={{ padding: 12 }}>
              <div className="kasa-display" style={{ fontSize: 13, fontWeight: 700, letterSpacing: '-0.02em', lineHeight: 1.15 }}>
                {p.name.toUpperCase()}
              </div>
              <div style={{ fontFamily: 'var(--font-body)', fontSize: 11, color: 'var(--c-text-2)', marginTop: 3, fontWeight: 500 }}>
                {p.address}
              </div>
              <div style={{ display: 'flex', gap: 6, marginTop: 10 }}>
                <Chip variant="secondary" size="sm">{p.units} UNITS</Chip>
                <Chip variant="tertiary" size="sm">{Math.round((p.occupied/p.units)*100)}%</Chip>
              </div>
              <div style={{
                marginTop: 10, paddingTop: 10,
                borderTop: '2px solid var(--c-stroke)',
                fontFamily: 'var(--font-display)', fontSize: 13, fontWeight: 700, letterSpacing: '-0.02em',
              }}>
                {kes(p.revenue)}
              </div>
            </div>
          </Card>
        ))}
      </div>
    </Screen>
  );
}

function PropertyDetail({ nav }) {
  const [tab, setTab] = React.useState('units');
  const p = MOCK.properties[0];
  const units = [
    { n: 'A-101', tenant: 'Akinyi Odhiambo', rent: 38000, status: 'active' },
    { n: 'A-102', tenant: 'Mwangi Githinji', rent: 40000, status: 'active' },
    { n: 'B-204', tenant: 'Otieno Wekesa', rent: 45000, status: 'active' },
    { n: 'B-205', tenant: null, rent: 45000, status: 'vacant' },
    { n: 'C-301', tenant: 'Njoroge Maina', rent: 52000, status: 'overdue' },
  ];
  return (
    <Screen>
      <div style={{ padding: '12px 20px' }}>
        <IconBtn icon="chevLeft" onClick={() => nav('properties')} />
      </div>
      <div style={{ padding: '0 20px 16px' }}>
        <TilePattern height={160} accent={p.accent} label="PROPERTY HERO" />
        <div className="kasa-display" style={{ fontSize: 28, fontWeight: 700, letterSpacing: '-0.03em', marginTop: 16 }}>
          {p.name.toUpperCase()}
        </div>
        <div style={{ fontFamily: 'var(--font-body)', fontSize: 13, color: 'var(--c-text-2)', fontWeight: 500, marginTop: 2 }}>
          {p.address}
        </div>

        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 10, marginTop: 16 }}>
          <StatChip label="UNITS" value={p.units} />
          <StatChip label="OCCUPIED" value={`${p.occupied}/${p.units}`} accent="secondary" />
          <StatChip label="MTD" value={`${Math.round(p.revenue/1000)}K`} accent="primary" />
        </div>

        <div style={{ display: 'flex', gap: 6, marginTop: 18, padding: 4,
          background: 'var(--c-elev)', border: '2px solid var(--c-stroke)', borderRadius: 999,
        }}>
          {['units', 'tenants', 'activity'].map(k => (
            <button key={k} onClick={() => setTab(k)}
              style={{
                flex: 1, border: 'none', cursor: 'pointer',
                background: tab === k ? 'var(--c-secondary)' : 'transparent',
                color: tab === k ? 'var(--c-secondary-ink)' : 'var(--c-text)',
                borderRadius: 999, padding: '10px 4px',
                fontFamily: 'var(--font-display)', fontSize: 11, fontWeight: 700,
                textTransform: 'uppercase', letterSpacing: '0.04em',
              }}>{k}</button>
          ))}
        </div>

        <div style={{ marginTop: 16, display: 'flex', flexDirection: 'column', gap: 10 }}>
          {tab === 'units' && units.map(u => (
            <Card key={u.n} pad={14}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
                <div style={{
                  width: 52, height: 52, borderRadius: 12,
                  background: u.status === 'vacant' ? 'var(--c-elev)' : 'var(--c-secondary)',
                  color: u.status === 'vacant' ? 'var(--c-text)' : 'var(--c-secondary-ink)',
                  border: '2px solid var(--c-stroke)',
                  display: 'flex', alignItems: 'center', justifyContent: 'center',
                  fontFamily: 'var(--font-display)', fontSize: 13, fontWeight: 700,
                }}>{u.n}</div>
                <div style={{ flex: 1 }}>
                  <div style={{ fontFamily: 'var(--font-body)', fontSize: 14, fontWeight: 600 }}>
                    {u.tenant || 'Vacant'}
                  </div>
                  <div style={{ fontFamily: 'var(--font-display)', fontSize: 12, color: 'var(--c-text-2)', fontWeight: 700, marginTop: 2 }}>
                    {kes(u.rent)} / MO
                  </div>
                </div>
                <Chip variant={u.status === 'vacant' ? 'neutral' : u.status === 'overdue' ? 'primary' : 'secondary'} size="sm">
                  {u.status}
                </Chip>
              </div>
            </Card>
          ))}
          {tab === 'tenants' && (
            <div style={{ padding: 40, textAlign: 'center', color: 'var(--c-text-2)', fontFamily: 'var(--font-display)', fontWeight: 700 }}>
              TENANT LIST HERE
            </div>
          )}
          {tab === 'activity' && (
            <div style={{ padding: 40, textAlign: 'center', color: 'var(--c-text-2)', fontFamily: 'var(--font-display)', fontWeight: 700 }}>
              ACTIVITY FEED HERE
            </div>
          )}
        </div>
      </div>
    </Screen>
  );
}

function StatChip({ label, value, accent }) {
  const bg = accent ? `var(--c-${accent})` : 'var(--c-card)';
  const ink = accent ? `var(--c-${accent}-ink)` : 'var(--c-text)';
  return (
    <div style={{
      background: bg, color: ink,
      border: '2px solid var(--c-stroke)',
      borderRadius: 14,
      padding: '10px 12px',
      boxShadow: '3px 3px 0 var(--c-shadow)',
    }}>
      <div style={{ fontFamily: 'var(--font-display)', fontSize: 10, fontWeight: 700, letterSpacing: '0.04em', opacity: 0.8 }}>{label}</div>
      <div className="kasa-display" style={{ fontSize: 22, fontWeight: 700, letterSpacing: '-0.03em', marginTop: 2 }}>{value}</div>
    </div>
  );
}

function AddPropertyForm({ nav }) {
  return (
    <Screen>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '14px 20px' }}>
        <IconBtn icon="close" onClick={() => nav('properties')} />
        <div className="kasa-display" style={{ fontSize: 15, fontWeight: 700 }}>NEW PROPERTY</div>
        <div style={{ width: 42 }} />
      </div>
      <div style={{ padding: '12px 20px', display: 'flex', flexDirection: 'column', gap: 14 }}>
        <Input label="PROPERTY NAME" placeholder="Westlands Heights" />
        <Input label="ADDRESS" placeholder="Waiyaki Way, Westlands" />
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12 }}>
          <Input label="UNITS" placeholder="12" />
          <Input label="MONTHLY RENT" prefix="KES" placeholder="45,000" />
        </div>
        <div>
          <Label style={{ marginBottom: 8 }}>PROPERTY TYPE</Label>
          <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8 }}>
            <Chip variant="secondary">APARTMENT</Chip>
            <Chip>TOWNHOUSE</Chip>
            <Chip>BEDSITTER</Chip>
            <Chip>STUDIO</Chip>
          </div>
        </div>
        <div>
          <Label style={{ marginBottom: 8 }}>PHOTOS</Label>
          <div style={{
            border: '2px dashed var(--c-stroke)', borderRadius: 16, padding: 28, textAlign: 'center',
          }}>
            <Icon name="camera" size={32} stroke={2.2} color="var(--c-text-2)" />
            <div style={{ marginTop: 10, fontFamily: 'var(--font-display)', fontSize: 13, fontWeight: 700 }}>+ ADD PHOTOS</div>
            <div style={{ marginTop: 4, fontSize: 11, color: 'var(--c-text-2)', fontFamily: 'var(--font-body)', fontWeight: 500 }}>MAX 6 \u00b7 JPG OR PNG</div>
          </div>
        </div>
        <div style={{ marginTop: 6 }}>
          <Button variant="primary" fullWidth size="lg" onClick={() => nav('properties')}>SAVE PROPERTY</Button>
        </div>
      </div>
    </Screen>
  );
}

Object.assign(window, { PropertiesList, PropertyDetail, AddPropertyForm, StatChip });
