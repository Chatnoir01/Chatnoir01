import test from 'node:test';
import assert from 'node:assert/strict';
import {
  calculateInvoiceLine,
  calculateInvoiceTotals,
  nextInvoiceNumber,
  validateCompanyProfile,
  validateInvoiceDraft
} from '../src/domain/invoice.js';

test('calculates 21% VAT with cent rounding', () => {
  assert.deepEqual(calculateInvoiceTotals({ amount: 99.99, vat: 21 }), {
    currency: 'EUR', net: 99.99, vatRate: 21, vatAmount: 21, gross: 120.99
  });
});

test('accepts zero VAT', () => {
  assert.deepEqual(calculateInvoiceTotals({ amount: 125, vat: 0 }).gross, 125);
});

test('rejects malformed invoice draft', () => {
  assert.deepEqual(
    validateInvoiceDraft({ client: '', description: 'x', amount: -1, vat: 19 }),
    ['client', 'description', 'amount', 'vat']
  );
});

test('accepts a valid invoice draft', () => {
  assert.deepEqual(validateInvoiceDraft({ client: 'Client SA', description: 'Conseil', amount: 500, vat: 21 }), []);
});

test('calculates line quantity discount VAT and gross total', () => {
  assert.deepEqual(
    calculateInvoiceLine({ description: 'Audit', quantity: 2, unitPrice: 100, discount: 10, vat: 21 }),
    { beforeDiscount: 200, discountAmount: 20, net: 180, vatRate: 21, vatAmount: 37.8, gross: 217.8 }
  );
});

test('calculates multi-line invoice totals across VAT rates', () => {
  const result = calculateInvoiceTotals({
    lines: [
      { description: 'Service', quantity: 1, unitPrice: 100, discount: 0, vat: 21 },
      { description: 'Livre', quantity: 2, unitPrice: 25, discount: 0, vat: 6 }
    ]
  });
  assert.equal(result.net, 150);
  assert.equal(result.vatAmount, 24);
  assert.equal(result.gross, 174);
});

test('rejects invalid multi-line invoice fields', () => {
  assert.deepEqual(
    validateInvoiceDraft({ client: 'Client SA', lines: [{ description: '', quantity: 0, unitPrice: -1, discount: 120, vat: 19 }] }),
    ['lines.0.description', 'lines.0.quantity', 'lines.0.unitPrice', 'lines.0.vat', 'lines.0.discount']
  );
});

test('validates a complete company profile', () => {
  assert.deepEqual(validateCompanyProfile({
    name: 'Pilot Demo SRL',
    address: 'Rue Exemple 1, 1000 Bruxelles',
    vatNumber: 'BE0123456789',
    iban: 'BE68539007547034',
    email: 'hello@pilot.example'
  }), []);
});

test('rejects malformed company profile fields', () => {
  assert.deepEqual(validateCompanyProfile({ name: '', address: 'x', vatNumber: '', iban: 'BE1', email: 'oops' }), ['name','address','vatNumber','iban','email']);
});

test('generates next invoice number without reusing an existing number', () => {
  assert.equal(nextInvoiceNumber(['FAC-2026-0001', 'FAC-2026-0007', 'FAC-2025-0099'], 2026), 'FAC-2026-0008');
});
