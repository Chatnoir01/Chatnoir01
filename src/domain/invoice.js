const ALLOWED_VAT_RATES = new Set([0, 6, 12, 21]);

function roundMoney(value) {
  return Math.round((Number(value) + Number.EPSILON) * 100) / 100;
}

function validText(value, min = 2, max = 200) {
  return typeof value === 'string' && value.trim().length >= min && value.trim().length <= max;
}

export function validateCompanyProfile(profile) {
  const errors = [];
  if (!profile || typeof profile !== 'object') return ['profile'];
  if (!validText(profile.name, 2, 120)) errors.push('name');
  if (!validText(profile.address, 5, 250)) errors.push('address');
  if (!validText(profile.vatNumber, 5, 40)) errors.push('vatNumber');
  if (!validText(profile.iban, 8, 40)) errors.push('iban');
  if (profile.email && !/^\S+@\S+\.\S+$/.test(profile.email)) errors.push('email');
  return errors;
}

export function validateInvoiceLine(line) {
  const errors = [];
  if (!line || typeof line !== 'object') return ['line'];
  if (!validText(line.description, 2, 300)) errors.push('description');
  const quantity = Number(line.quantity);
  if (!Number.isFinite(quantity) || quantity <= 0 || quantity > 1_000_000) errors.push('quantity');
  const unitPrice = Number(line.unitPrice);
  if (!Number.isFinite(unitPrice) || unitPrice < 0 || unitPrice > 10_000_000) errors.push('unitPrice');
  const vat = Number(line.vat);
  if (!ALLOWED_VAT_RATES.has(vat)) errors.push('vat');
  const discount = line.discount == null ? 0 : Number(line.discount);
  if (!Number.isFinite(discount) || discount < 0 || discount > 100) errors.push('discount');
  return errors;
}

export function validateInvoiceDraft(draft) {
  const errors = [];
  if (!draft || typeof draft !== 'object') return ['draft'];
  if (!validText(draft.client, 2, 160)) errors.push('client');
  if (Array.isArray(draft.lines)) {
    if (draft.lines.length === 0 || draft.lines.length > 200) errors.push('lines');
    draft.lines.forEach((line, index) => {
      for (const field of validateInvoiceLine(line)) errors.push(`lines.${index}.${field}`);
    });
  } else {
    if (!validText(draft.description, 2, 300)) errors.push('description');
    const amount = Number(draft.amount);
    if (!Number.isFinite(amount) || amount <= 0 || amount > 10_000_000) errors.push('amount');
    const vat = Number(draft.vat);
    if (!ALLOWED_VAT_RATES.has(vat)) errors.push('vat');
  }
  return errors;
}

export function calculateInvoiceLine(line) {
  const quantity = Number(line.quantity);
  const unitPrice = Number(line.unitPrice);
  const discount = line.discount == null ? 0 : Number(line.discount);
  const vatRate = Number(line.vat);
  const beforeDiscount = roundMoney(quantity * unitPrice);
  const discountAmount = roundMoney(beforeDiscount * discount / 100);
  const net = roundMoney(beforeDiscount - discountAmount);
  const vatAmount = roundMoney(net * vatRate / 100);
  const gross = roundMoney(net + vatAmount);
  return { beforeDiscount, discountAmount, net, vatRate, vatAmount, gross };
}

export function calculateInvoiceTotals(draft) {
  if (Array.isArray(draft.lines)) {
    const lines = draft.lines.map(calculateInvoiceLine);
    return {
      currency: 'EUR',
      net: roundMoney(lines.reduce((sum, line) => sum + line.net, 0)),
      vatAmount: roundMoney(lines.reduce((sum, line) => sum + line.vatAmount, 0)),
      gross: roundMoney(lines.reduce((sum, line) => sum + line.gross, 0)),
      lines
    };
  }
  const net = roundMoney(Number(draft.amount));
  const vatRate = Number(draft.vat);
  const vatAmount = roundMoney(net * vatRate / 100);
  const gross = roundMoney(net + vatAmount);
  return { currency: 'EUR', net, vatRate, vatAmount, gross };
}

export function nextInvoiceNumber(existingNumbers = [], year = new Date().getFullYear()) {
  const prefix = `FAC-${year}-`;
  const highest = existingNumbers
    .filter(value => typeof value === 'string' && value.startsWith(prefix))
    .map(value => Number(value.slice(prefix.length)))
    .filter(Number.isInteger)
    .reduce((max, value) => Math.max(max, value), 0);
  return `${prefix}${String(highest + 1).padStart(4, '0')}`;
}
