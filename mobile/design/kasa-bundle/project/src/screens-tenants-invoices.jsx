// Kasa screens — Tenants list, Add Tenant, Invoices list, Invoice Detail

function TenantsList({ nav }) {
  const [filter, setFilter] = React.useState('all');
  const filters = [
    { k: 'all', label: 'ALL' },
    { k: 'active', label: 'ACTIVE' },
    { k: 'ending', label: 'ENDING' },
    { k: 'overdue', label: 'OVERDUE' },
  ];
  const shown = MOCK.tenants.filter(t => filter === 'all' || t.status === filter);
  return (
    <Screen>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '16px 20px 12px' }}>
        <div className="kasa-display" style={{ fontSize: 32, fontWeight: 700, letterSpacing: '-0.03em' }}>TENANTS</div>
        <Button variant="primary" size="sm" onClick={() => nav('addTenant')}>
          <Icon name="plus" size={14} stroke={3} /> ADD
        </Button>
      </div>
      <div style={{ padding: '0 20px 14px', display: 'flex', gap: 8, overflowX: 'auto' }}>
        {filters.map(f => (
          <Chip key={f.k} variant={filter === f.k ? 'secondary' : 'neutral'} onClick={() => setFilter(f.k)}>
            {f.label}
          </Chip>
        ))}
      </div>
      <div style={{ padding: '0 20px', display: 'flex', flexDirection: 'column', gap: 10 }}>
        {shown.map(t => (
          <Card key={t.id} pad={14}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 14 }}>
              <Avatar name={t.name} size={48} accent={t.accent} />
              <div style={{ flex: 1, minWidth: 0 }}>
                <div className="kasa-display" style={{ fontSize: 14, fontWeight: 700, letterSpacing: '-0.01em', lineHeight: 1.2 }}>
                  {t.name.toUpperCase()}
                </div>
                <div style={{ fontFamily: 'var(--font-body)', fontSize: 11, color: 'var(--c-text-2)', fontWeight: 500, marginTop: 2 }}>
                  UNIT {t.unit} &middot; {t.property}
                </div>
                <div style={{ marginTop: 6, display: 'flex', gap: 12, fontFamily: 'var(--font-display)', fontSize: 10, fontWeight: 700 }}>
                  <span>LEASE: {t.leaseEnd}</span>
                  <span style={{ color: 'var(--c-text-2)' }}>|</span>
                  <span>{kes(t.rent)}</span>
                </div>
              </div>
              <Chip variant={t.status === 'overdue' ? 'primary' : t.status === 'ending' ? 'tertiary' : 'secondary'} size="sm">
                {t.status === 'ending' ? 'ENDING' : t.status}
              </Chip>
            </div>
          </Card>
        ))}
      </div>
    </Screen>
  );
}

function AddTenantForm({ nav }) {
  return (
    <Screen>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '14px 20px' }}>
        <IconBtn icon="close" onClick={() => nav('tenants')} />
        <div className="kasa-display" style={{ fontSize: 15, fontWeight: 700 }}>NEW TENANT</div>
        <div style={{ width: 42 }} />
      </div>
      <div style={{ padding: '12px 20px', display: 'flex', flexDirection: 'column', gap: 14 }}>
        <Input label="FULL NAME" placeholder="Otieno Wekesa" />
        <Input label="PHONE" prefix="+254" placeholder="7XX XXX XXX" />
        <Input label="EMAIL" placeholder="name@email.com" />
        <div>
          <Label style={{ marginBottom: 8 }}>ASSIGN UNIT</Label>
          <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8 }}>
            <Chip variant="secondary">B-204 \u00b7 WESTLANDS</Chip>
            <Chip>A-102</Chip>
            <Chip>C-301</Chip>
          </div>
        </div>
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12 }}>
          <Input label="LEASE START" placeholder="DD/MM/YYYY" />
          <Input label="LEASE END" placeholder="DD/MM/YYYY" />
        </div>
        <div>
          <Label style={{ marginBottom: 8 }}>ID PHOTO</Label>
          <div style={{
            border: '2px dashed var(--c-stroke)', borderRadius: 16, padding: 22, textAlign: 'center',
          }}>
            <Icon name="camera" size={28} stroke={2.2} color="var(--c-text-2)" />
            <div style={{ marginTop: 8, fontFamily: 'var(--font-display)', fontSize: 12, fontWeight: 700 }}>+ UPLOAD ID</div>
            <div style={{ marginTop: 3, fontSize: 10, color: 'var(--c-text-2)', fontFamily: 'var(--font-body)', fontWeight: 500 }}>FRONT AND BACK</div>
          </div>
        </div>
        <div style={{ marginTop: 6 }}>
          <Button variant="primary" fullWidth size="lg" onClick={() => nav('tenants')}>CREATE TENANT</Button>
        </div>
      </div>
    </Screen>
  );
}

const INV_STATUS = {
  paid: { chip: 'primary', label: 'PAID' },
  pending: { chip: 'secondary', label: 'PENDING' },
  overdue: { chip: 'tertiary', label: 'OVERDUE' },
};

function InvoicesList({ nav, role }) {
  const [filter, setFilter] = React.useState('all');
  const filters = [
    { k: 'all', label: 'ALL' },
    { k: 'pending', label: 'PENDING' },
    { k: 'paid', label: 'PAID' },
    { k: 'overdue', label: 'OVERDUE' },
  ];
  let items = MOCK.invoices;
  if (role === 'tenant') items = items.filter(i => i.tenant === 'Otieno Wekesa');
  const shown = items.filter(i => filter === 'all' || i.status === filter);
  return (
    <Screen>
      <div style={{ padding: '16px 20px 8px' }}>
        <div className="kasa-display" style={{ fontSize: 32, fontWeight: 700, letterSpacing: '-0.03em' }}>INVOICES</div>
      </div>
      <div style={{ padding: '8px 20px 14px', display: 'flex', gap: 8, overflowX: 'auto' }}>
        {filters.map(f => (
          <Chip key={f.k} variant={filter === f.k ? 'secondary' : 'neutral'} onClick={() => setFilter(f.k)}>
            {f.label}
          </Chip>
        ))}
      </div>
      <div style={{ padding: '0 20px', display: 'flex', flexDirection: 'column', gap: 10 }}>
        {shown.map(inv => {
          const s = INV_STATUS[inv.status];
          return (
            <Card key={inv.id} pad={14} onClick={() => nav('invoiceDetail', { invoice: inv })}>
              <div style={{ display: 'flex', alignItems: 'flex-start', gap: 12 }}>
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{ fontFamily: 'var(--font-mono)', fontSize: 11, color: 'var(--c-text-2)', fontWeight: 700 }}>
                    {inv.id}
                  </div>
                  <div className="kasa-display" style={{ fontSize: 13, fontWeight: 700, letterSpacing: '-0.01em', marginTop: 4 }}>
                    {inv.tenant.toUpperCase()} \u00b7 {inv.unit}
                  </div>
                  <div style={{ marginTop: 6, display: 'flex', gap: 10, fontFamily: 'var(--font-body)', fontSize: 11, color: 'var(--c-text-2)', fontWeight: 500 }}>
                    <span>DUE {inv.due}</span>
                  </div>
                </div>
                <div style={{ textAlign: 'right' }}>
                  <div className="kasa-display" style={{ fontSize: 22, fontWeight: 700, letterSpacing: '-0.03em', lineHeight: 1 }}>
                    {kes(inv.amount)}
                  </div>
                  <div style={{ marginTop: 8 }}>
                    <Chip variant={s.chip} size="sm">{s.label}</Chip>
                  </div>
                </div>
              </div>
            </Card>
          );
        })}
      </div>
    </Screen>
  );
}

function InvoiceDetail({ nav, role, invoice }) {
  const inv = invoice || MOCK.invoices[2];
  const s = INV_STATUS[inv.status];
  return (
    <Screen>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '14px 20px' }}>
        <IconBtn icon="chevLeft" onClick={() => nav('invoices')} />
        <div className="kasa-display" style={{ fontSize: 14, fontWeight: 700 }}>{inv.id}</div>
        <IconBtn icon="settings" />
      </div>
      <div style={{ padding: '12px 20px 8px' }}>
        <Card accent={inv.status === 'overdue' ? 'tertiary' : inv.status === 'paid' ? 'primary' : 'secondary'} pad={22}>
          <Label>AMOUNT DUE</Label>
          <div className="kasa-display" style={{ fontSize: 56, fontWeight: 700, letterSpacing: '-0.03em', lineHeight: 1, marginTop: 10 }}>
            {kes(inv.amount)}
          </div>
          <div style={{ marginTop: 14, display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
            <Chip variant="neutral" size="sm" style={{ borderColor: 'currentColor' }}>{s.label}</Chip>
            <span style={{ fontFamily: 'var(--font-display)', fontSize: 11, fontWeight: 700, letterSpacing: '0.04em' }}>DUE {inv.due}</span>
          </div>
        </Card>
      </div>
      <div style={{ padding: '12px 20px' }}>
        <Card pad={0}>
          <DetailRow label="INVOICE" value={inv.id} />
          <DetailRow label="TENANT" value={inv.tenant} />
          <DetailRow label="UNIT" value={inv.unit} />
          <DetailRow label="ISSUED" value={inv.issued} />
          <DetailRow label="DUE" value={inv.due} />
          {inv.mpesa && <DetailRow label="MPESA" value={inv.mpesa} mono last />}
          {!inv.mpesa && <DetailRow label="METHOD" value="MPESA STK" last />}
        </Card>
      </div>
      <div style={{ padding: '12px 20px', display: 'flex', flexDirection: 'column', gap: 10 }}>
        {role === 'tenant' && inv.status !== 'paid' && (
          <Button variant="primary" fullWidth size="lg" onClick={() => nav('mpesa', { invoice: inv })}>
            <Icon name="phone" size={16} stroke={2.8} /> PAY WITH MPESA
          </Button>
        )}
        {role === 'landlord' && inv.status !== 'paid' && (
          <>
            <Button variant="primary" fullWidth size="lg">MARK AS PAID</Button>
            <Button variant="secondary" fullWidth size="md">SEND REMINDER</Button>
          </>
        )}
        {inv.status === 'paid' && (
          <Button variant="secondary" fullWidth size="md">DOWNLOAD RECEIPT</Button>
        )}
      </div>
    </Screen>
  );
}

function DetailRow({ label, value, mono, last }) {
  return (
    <div style={{
      display: 'flex', justifyContent: 'space-between', alignItems: 'center',
      padding: '14px 18px',
      borderBottom: last ? 'none' : '2px solid var(--c-stroke)',
    }}>
      <span style={{ fontFamily: 'var(--font-display)', fontSize: 11, fontWeight: 700, color: 'var(--c-text-2)', letterSpacing: '0.04em' }}>
        {label}
      </span>
      <span style={{ fontFamily: mono ? 'var(--font-mono)' : 'var(--font-body)', fontSize: 14, fontWeight: 600 }}>
        {value}
      </span>
    </div>
  );
}

Object.assign(window, { TenantsList, AddTenantForm, InvoicesList, InvoiceDetail, INV_STATUS });
