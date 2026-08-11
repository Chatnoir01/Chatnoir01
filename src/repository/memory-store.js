import { randomUUID } from 'node:crypto';

function clone(value) { return structuredClone(value); }

export class MemoryStore {
  constructor(seed = {}) {
    this.clients = clone(seed.clients || []);
    this.invoices = clone(seed.invoices || []);
    this.quotes = clone(seed.quotes || []);
    this.organizations = clone(seed.organizations || []);
    this.users = clone(seed.users || []);
    this.memberships = clone(seed.memberships || []);
    this.sessions = clone(seed.sessions || []);
  }

  getOrganization(id){const row=this.organizations.find(x=>x.id===id);return row?clone(row):null;}
  updateOrganization(id,patch){const i=this.organizations.findIndex(x=>x.id===id);if(i<0)return null;this.organizations[i]={...this.organizations[i],...patch,id,updatedAt:new Date().toISOString()};return clone(this.organizations[i]);}
  findUserByEmail(email){const row=this.users.find(x=>x.email===String(email).toLowerCase());return row?clone(row):null;}
  getUser(id){const row=this.users.find(x=>x.id===id);return row?clone(row):null;}
  createUser(input){const now=new Date().toISOString();const row={id:randomUUID(),email:String(input.email).toLowerCase(),passwordHash:input.passwordHash,createdAt:now,updatedAt:now};this.users.push(row);return clone(row);}
  createOrganization(input){const now=new Date().toISOString();const row={id:randomUUID(),name:input.name,address:'',vatNumber:'',iban:'',email:'',createdAt:now,updatedAt:now};this.organizations.push(row);return clone(row);}
  addMembership(orgId,userId,role='owner'){this.memberships.push({organizationId:orgId,userId,role});return {organizationId:orgId,userId,role};}
  listMemberships(userId){return this.memberships.filter(x=>x.userId===userId).map(x=>({...clone(x),organization:this.getOrganization(x.organizationId)}));}
  createSession(input){const row={id:randomUUID(),...input,createdAt:new Date().toISOString()};this.sessions.push(row);return clone(row);}
  getSession(hash){const row=this.sessions.find(x=>x.tokenHash===hash&&new Date(x.expiresAt)>new Date());if(!row)return null;const membership=this.memberships.find(x=>x.userId===row.userId&&x.organizationId===row.organizationId);const user=this.users.find(x=>x.id===row.userId);return membership&&user?{...clone(row),role:membership.role,user:{id:user.id,email:user.email}}:null;}
  deleteSession(hash){const n=this.sessions.length;this.sessions=this.sessions.filter(x=>x.tokenHash!==hash);return this.sessions.length<n;}

  listClients(organizationId){return clone(this.clients.filter(x=>x.organizationId===organizationId));}
  getClient(organizationId,id){const x=this.clients.find(r=>r.organizationId===organizationId&&r.id===id);return x?clone(x):null;}
  createClient(organizationId,input){const now=new Date().toISOString();const x={id:randomUUID(),organizationId,name:String(input.name||'').trim(),email:String(input.email||'').trim(),vatNumber:String(input.vatNumber||'').trim(),address:String(input.address||'').trim(),createdAt:now,updatedAt:now};this.clients.push(x);return clone(x);}
  updateClient(organizationId,id,patch){const i=this.clients.findIndex(r=>r.organizationId===organizationId&&r.id===id);if(i<0)return null;const c=this.clients[i];this.clients[i]={...c,...patch,id,organizationId,updatedAt:new Date().toISOString()};return clone(this.clients[i]);}
  deleteClient(organizationId,id){if(this.invoices.some(r=>r.organizationId===organizationId&&r.clientId===id)||this.quotes.some(r=>r.organizationId===organizationId&&r.clientId===id))return{deleted:false,reason:'client_has_documents'};const n=this.clients.length;this.clients=this.clients.filter(r=>!(r.organizationId===organizationId&&r.id===id));return{deleted:this.clients.length<n};}

  listInvoices(organizationId){return clone(this.invoices.filter(x=>x.organizationId===organizationId));}
  getInvoice(organizationId,id){const x=this.invoices.find(r=>r.organizationId===organizationId&&r.id===id);return x?clone(x):null;}
  createInvoice(organizationId,input){const now=new Date().toISOString();const x={id:randomUUID(),organizationId,clientId:input.clientId,number:input.number,status:input.status||'draft',issueDate:input.issueDate||now.slice(0,10),dueDate:input.dueDate||null,lines:clone(input.lines||[]),totals:clone(input.totals||null),sourceQuoteId:input.sourceQuoteId||null,createdAt:now,updatedAt:now};if(x.sourceQuoteId&&this.invoices.some(r=>r.organizationId===organizationId&&r.sourceQuoteId===x.sourceQuoteId))throw new Error('quote_already_converted');this.invoices.push(x);return clone(x);}
  updateInvoiceStatus(organizationId,id,status){const i=this.invoices.findIndex(r=>r.organizationId===organizationId&&r.id===id);if(i<0)return null;this.invoices[i]={...this.invoices[i],status,updatedAt:new Date().toISOString()};return clone(this.invoices[i]);}

  listQuotes(organizationId){return clone(this.quotes.filter(x=>x.organizationId===organizationId));}
  getQuote(organizationId,id){const x=this.quotes.find(r=>r.organizationId===organizationId&&r.id===id);return x?clone(x):null;}
  createQuote(organizationId,input){const now=new Date().toISOString();const x={id:randomUUID(),organizationId,clientId:input.clientId,number:input.number,status:input.status||'draft',issueDate:input.issueDate||now.slice(0,10),validUntil:input.validUntil||null,lines:clone(input.lines||[]),totals:clone(input.totals||null),convertedInvoiceId:null,createdAt:now,updatedAt:now};this.quotes.push(x);return clone(x);}
  updateQuoteStatus(organizationId,id,status){const i=this.quotes.findIndex(r=>r.organizationId===organizationId&&r.id===id);if(i<0)return null;this.quotes[i]={...this.quotes[i],status,updatedAt:new Date().toISOString()};return clone(this.quotes[i]);}
  markQuoteConverted(organizationId,id,invoiceId){const i=this.quotes.findIndex(r=>r.organizationId===organizationId&&r.id===id);if(i<0)return null;if(this.quotes[i].convertedInvoiceId)return {alreadyConverted:true,quote:clone(this.quotes[i])};this.quotes[i]={...this.quotes[i],status:'converted',convertedInvoiceId:invoiceId,updatedAt:new Date().toISOString()};return {alreadyConverted:false,quote:clone(this.quotes[i])};}
}
