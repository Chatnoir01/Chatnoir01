import test from 'node:test';
import assert from 'node:assert/strict';
import { buildInvoiceHtml } from '../src/domain/invoice-document.js';

test('renders company client totals and invoice number',()=>{
  const html=buildInvoiceHtml({company:{name:'Pilot SRL',address:'Bruxelles',vatNumber:'BE0123',iban:'BE001'},client:{name:'Client SA'},invoice:{number:'FAC-2026-0001',issueDate:'2026-08-11',lines:[{description:'Conseil',quantity:2,unitPrice:100,vat:21}],totals:{net:200,vatAmount:42,gross:242}}});
  assert.match(html,/FAC-2026-0001/);assert.match(html,/Pilot SRL/);assert.match(html,/242/);
});

test('escapes untrusted content in printable invoice',()=>{
  const html=buildInvoiceHtml({company:{name:'<script>alert(1)<\/script>'},client:{name:'<img src=x onerror=alert(1)>'},invoice:{number:'FAC-X',lines:[{description:'<b>x</b>',quantity:1,unitPrice:1,vat:21}],totals:{net:1,vatAmount:.21,gross:1.21}}});
  assert.equal(html.includes('<img src=x onerror=alert(1)>'),false);
  assert.equal(html.includes('<b>x</b>'),false);
  assert.match(html,/&lt;img/);
});
