// Kasa mock data — Kenyan names, Nairobi neighborhoods

const MOCK = {
  landlord: {
    name: 'Wanjiru Kamau',
    phone: '+254 712 345 678',
    email: 'wanjiru.k@kasa.co.ke',
    role: 'LANDLORD',
  },
  tenant: {
    name: 'Otieno Wekesa',
    phone: '+254 722 456 789',
    email: 'otieno.w@kasa.co.ke',
    role: 'TENANT',
    unit: 'B-204',
    property: 'Westlands Heights',
    rent: 45000,
    leaseEnd: '2026-07-20',
    daysLeft: 94,
  },
  revenue: {
    total: 847500,
    month: 'APR 2026',
    occupancy: 87,
    occupiedUnits: 13,
    totalUnits: 15,
    overdueCount: 4,
    overdueAmount: 112000,
  },
  properties: [
    { id: 'p1', name: 'Westlands Heights', address: 'Waiyaki Way, Westlands', units: 12, occupied: 11, revenue: 540000, accent: 'primary' },
    { id: 'p2', name: 'Kilimani Court', address: 'Argwings Kodhek Rd, Kilimani', units: 8, occupied: 7, revenue: 392000, accent: 'secondary' },
    { id: 'p3', name: 'Lavington Ridge', address: 'James Gichuru Rd, Lavington', units: 6, occupied: 6, revenue: 420000, accent: 'tertiary' },
    { id: 'p4', name: 'Karen Grove', address: 'Marula Lane, Karen', units: 4, occupied: 3, revenue: 360000, accent: 'primary' },
  ],
  tenants: [
    { id: 't1', name: 'Otieno Wekesa', unit: 'B-204', property: 'Westlands Heights', rent: 45000, leaseEnd: '15 JUL 2026', status: 'active', accent: 'primary' },
    { id: 't2', name: 'Akinyi Odhiambo', unit: 'A-102', property: 'Westlands Heights', rent: 38000, leaseEnd: '04 MAY 2026', status: 'ending', accent: 'secondary' },
    { id: 't3', name: 'Njoroge Maina', unit: 'C-301', property: 'Kilimani Court', rent: 52000, leaseEnd: '22 OCT 2026', status: 'overdue', accent: 'tertiary' },
    { id: 't4', name: 'Chebet Kiplagat', unit: 'A-201', property: 'Lavington Ridge', rent: 70000, leaseEnd: '18 SEP 2026', status: 'active', accent: 'primary' },
    { id: 't5', name: 'Mwangi Githinji', unit: 'D-404', property: 'Kilimani Court', rent: 56000, leaseEnd: '11 DEC 2026', status: 'active', accent: 'secondary' },
    { id: 't6', name: 'Achieng Omollo', unit: 'B-103', property: 'Karen Grove', rent: 90000, leaseEnd: '28 AUG 2026', status: 'active', accent: 'tertiary' },
  ],
  invoices: [
    { id: 'INV-2026-041', tenant: 'Otieno Wekesa', unit: 'B-204', amount: 45000, issued: '01 APR 2026', due: '05 APR 2026', status: 'paid', mpesa: 'SE4K8P9XQ2' },
    { id: 'INV-2026-042', tenant: 'Akinyi Odhiambo', unit: 'A-102', amount: 38000, issued: '01 APR 2026', due: '05 APR 2026', status: 'paid', mpesa: 'SE4H2N7RM1' },
    { id: 'INV-2026-055', tenant: 'Njoroge Maina', unit: 'C-301', amount: 52000, issued: '01 APR 2026', due: '05 APR 2026', status: 'overdue' },
    { id: 'INV-2026-056', tenant: 'Otieno Wekesa', unit: 'B-204', amount: 45000, issued: '01 MAY 2026', due: '05 MAY 2026', status: 'pending' },
    { id: 'INV-2026-060', tenant: 'Chebet Kiplagat', unit: 'A-201', amount: 70000, issued: '01 APR 2026', due: '05 APR 2026', status: 'overdue' },
    { id: 'INV-2026-061', tenant: 'Mwangi Githinji', unit: 'D-404', amount: 56000, issued: '01 APR 2026', due: '05 APR 2026', status: 'paid', mpesa: 'SE3P2K8LN4' },
  ],
  maintenance: [
    { id: 'm1', title: 'Kitchen tap leak', property: 'Westlands Heights', unit: 'B-204', submitted: '12 APR 2026', status: 'open', category: 'plumbing' },
    { id: 'm2', title: 'Power outage bedroom', property: 'Kilimani Court', unit: 'C-301', submitted: '10 APR 2026', status: 'progress', category: 'electrical' },
    { id: 'm3', title: 'Fridge not cooling', property: 'Westlands Heights', unit: 'A-102', submitted: '08 APR 2026', status: 'resolved', category: 'appliance' },
    { id: 'm4', title: 'Broken door handle', property: 'Lavington Ridge', unit: 'A-201', submitted: '14 APR 2026', status: 'open', category: 'general' },
    { id: 'm5', title: 'Hot water heater', property: 'Karen Grove', unit: 'B-103', submitted: '06 APR 2026', status: 'resolved', category: 'plumbing' },
  ],
  notifications: [
    { id: 'n1', type: 'coin', heading: 'Rent payment received', body: 'Otieno Wekesa paid KES 45,000 for Unit B-204. MPesa receipt SE4K8P9XQ2.', time: '2h ago', unread: true },
    { id: 'n2', type: 'wrench', heading: 'New maintenance request', body: 'Broken door handle reported at Lavington Ridge, Unit A-201.', time: '5h ago', unread: true },
    { id: 'n3', type: 'bell', heading: 'Lease ending soon', body: 'Akinyi Odhiambo\u2019s lease at Unit A-102 ends in 17 days.', time: '1d ago', unread: false },
    { id: 'n4', type: 'key', heading: 'New tenant onboarded', body: 'Mwangi Githinji moved into Kilimani Court, Unit D-404.', time: '3d ago', unread: false },
  ],
  activity: [
    { icon: 'coin', text: 'Otieno Wekesa paid KES 45,000', time: '2h ago', accent: 'primary' },
    { icon: 'key', text: 'New lease signed \u00b7 A-102', time: '1d ago', accent: 'secondary' },
    { icon: 'wrench', text: 'Ticket resolved \u00b7 Fridge cooling', time: '2d ago', accent: 'tertiary' },
    { icon: 'invoice', text: '6 invoices sent for MAY', time: '3d ago', accent: 'primary' },
  ],
  history: [
    { date: '05 APR 2026', amount: 45000, mpesa: 'SE4K8P9XQ2' },
    { date: '04 MAR 2026', amount: 45000, mpesa: 'SD2N9M6PL3' },
    { date: '03 FEB 2026', amount: 45000, mpesa: 'SC8L4K7PR1' },
  ],
};

window.MOCK = MOCK;
