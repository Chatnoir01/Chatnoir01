const ORG='demo-org';
const seedClients=[
  {id:'local-1',name:'Atelier Vermeulen',email:'contact@atelier.example'},
  {id:'local-2',name:'Studio Louise',email:'hello@studio.example'},
  {id:'local-3',name:'Nova Services',email:'admin@nova.example'}
];
const seedInvoices=[
  {key:'local-18',id:'FAC-2026-018',client:'Atelier Vermeulen',clientId:'local-1',date:'08/08/2026',amount:1452,status:'Payée'},
  {key:'local-17',id:'FAC-2026-017',client:'Studio Louise',clientId:'local-2',date:'04/08/2026',amount:968,status:'En attente'},
  {key:'local-16',id:'FAC-2026-016',client:'Nova Services',clientId:'local-3',date:'29/07/2026',amount:660,status:'En retard'},
  {key:'local-15',id:'FAC-2026-015',client:'Atelier Vermeulen',clientId:'local-1',date:'22/07/2026',amount:2178,status:'Payée'}
];
const load=(key,fallback)=>{try{return JSON.parse(localStorage.getItem(key))||fallback}catch{return fallback}};
let clients=load('pilot_clients',seedClients);
let invoices=load('pilot_invoices',seedInvoices);
let apiMode=false;

const euro=n=>new Intl.NumberFormat('fr-BE',{style:'currency',currency:'EUR'}).format(Number(n)||0);
const statusClass=s=>s==='Payée'?'paid':s==='En retard'?'late':'pending';
const toast=msg=>{const el=document.querySelector('#toast');el.textContent=msg;el.classList.add('show');clearTimeout(window.__toast);window.__toast=setTimeout(()=>el.classList.remove('show'),2200)};
const apiHeaders=()=>({'content-type':'application/json','x-pilot-organization':ORG});
const api=async(path,options={})=>{
  const response=await fetch(path,{...options,headers:{...apiHeaders(),...(options.headers||{})}});
  const body=response.status===204?null:await response.json().catch(()=>null);
  if(!response.ok)throw new Error(body?.error||`HTTP_${response.status}`);
  return body;
};

function mapApiStatus(status){return status==='paid'?'Payée':status==='overdue'?'En retard':'En attente'}
function mapUiStatus(status){return status==='Payée'?'paid':status==='En retard'?'overdue':'issued'}
function normalizeApiInvoice(row){
  const client=clients.find(c=>c.id===row.clientId);
  return {key:row.id,id:row.number,client:client?.name||'Client',clientId:row.clientId,date:new Date(row.issueDate).toLocaleDateString('fr-BE'),amount:row.totals?.gross||0,status:mapApiStatus(row.status)};
}

async function detectApi(){
  try{
    const response=await fetch('/api/health',{cache:'no-store'});
    if(!response.ok)return false;
    const body=await response.json();
    return body?.service==='pilot';
  }catch{return false}
}

async function hydrateFromApi(){
  const clientBody=await api('/api/v1/clients');
  clients=clientBody.data;
  const invoiceBody=await api('/api/v1/invoices');
  invoices=invoiceBody.data.map(normalizeApiInvoice);
}

function persistLocal(){
  if(apiMode)return;
  localStorage.setItem('pilot_clients',JSON.stringify(clients));
  localStorage.setItem('pilot_invoices',JSON.stringify(invoices));
}

document.querySelector('#today').textContent=new Intl.DateTimeFormat('fr-BE',{dateStyle:'long'}).format(new Date());

function row(i){return `<tr><td><b>${i.id}</b></td><td>${i.client}</td><td>${i.date}</td><td><b>${euro(i.amount)}</b></td><td><span class="status ${statusClass(i.status)}">${i.status}</span></td><td><button class="row-action" data-key="${i.key}">•••</button></td></tr>`}

function renderInvoices(filter=''){
  const visible=invoices.filter(i=>(i.id+' '+i.client).toLowerCase().includes(filter.toLowerCase()));
  document.querySelector('#invoiceRows').innerHTML=invoices.slice(0,5).map(row).join('');
  document.querySelector('#allInvoiceRows').innerHTML=visible.map(row).join('');
  const paid=invoices.filter(i=>i.status==='Payée');
  const pending=invoices.filter(i=>i.status==='En attente');
  const late=invoices.filter(i=>i.status==='En retard');
  const pendingTotal=pending.reduce((a,i)=>a+i.amount,0);
  const lateTotal=late.reduce((a,i)=>a+i.amount,0);
  document.querySelector('#paidCount').textContent=paid.length;
  document.querySelector('#pendingCount').textContent=pending.length;
  document.querySelector('#lateCount').textContent=late.length;
  document.querySelector('#pendingAmount').textContent=euro(pendingTotal);
  document.querySelector('#lateAmount').textContent=euro(lateTotal);
  document.querySelector('#outstanding').textContent=euro(pendingTotal+lateTotal);
  document.querySelector('#revenue').textContent=euro(paid.reduce((a,i)=>a+i.amount,0)+9210);
  bindRowActions();
}

function bindRowActions(){
  document.querySelectorAll('.row-action').forEach(btn=>btn.onclick=async()=>{
    const inv=invoices.find(i=>i.key===btn.dataset.key);
    if(!inv)return;
    const next=inv.status==='Payée'?'En attente':'Payée';
    if(!confirm(`${inv.id} — ${inv.client}\n\nPasser le statut à « ${next} » ?`))return;
    try{
      if(apiMode){
        const body=await api(`/api/v1/invoices/${inv.key}/status`,{method:'PATCH',body:JSON.stringify({status:mapUiStatus(next)})});
        inv.status=mapApiStatus(body.data.status);
      }else{
        inv.status=next;
        persistLocal();
      }
      renderInvoices(document.querySelector('#invoiceSearch')?.value||'');
      toast(`Statut mis à jour : ${inv.status}`);
    }catch{toast('Impossible de modifier le statut')}
  });
}

function renderClients(){
  document.querySelector('#clientCards').innerHTML=clients.map(c=>`<div class="client-card"><b>${c.name}</b><span>${c.email||'E-mail non renseigné'}</span></div>`).join('');
  document.querySelector('#client').innerHTML=clients.map(c=>`<option value="${c.id}">${c.name}</option>`).join('');
}

document.querySelectorAll('.nav').forEach(btn=>btn.addEventListener('click',()=>{
  document.querySelectorAll('.nav,.view').forEach(x=>x.classList.remove('active'));
  btn.classList.add('active');
  document.querySelector('#'+btn.dataset.view).classList.add('active');
}));

const dialog=document.querySelector('#invoiceDialog');
document.querySelectorAll('#newInvoice,.invoice-trigger').forEach(b=>b.addEventListener('click',()=>dialog.showModal()));
document.querySelector('#closeDialog').addEventListener('click',()=>dialog.close());
const amount=document.querySelector('#amount'),vat=document.querySelector('#vat');
function preview(){const base=Number(amount.value)||0;document.querySelector('#totalPreview').textContent=euro(base*(1+Number(vat.value)/100))}
amount.addEventListener('input',preview);vat.addEventListener('change',preview);

document.querySelector('#invoiceForm').addEventListener('submit',async e=>{
  e.preventDefault();
  const base=Number(amount.value);
  if(!Number.isFinite(base)||base<=0){toast('Montant invalide');return}
  const clientId=document.querySelector('#client').value;
  const client=clients.find(c=>c.id===clientId);
  const description=document.querySelector('#description').value.trim();
  try{
    if(apiMode){
      const body=await api('/api/v1/invoices',{method:'POST',body:JSON.stringify({
        clientId,
        client:client?.name||'Client',
        lines:[{description,quantity:1,unitPrice:base,vat:Number(vat.value),discountPercent:0}]
      })});
      invoices.unshift(normalizeApiInvoice(body.data));
    }else{
      const total=Math.round(base*(1+Number(vat.value)/100)*100)/100;
      const max=invoices.reduce((m,i)=>Math.max(m,Number(i.id.split('-').pop())||0),0);
      invoices.unshift({key:`local-${Date.now()}`,id:`FAC-${new Date().getFullYear()}-${String(max+1).padStart(3,'0')}`,client:client?.name||'Client',clientId,date:new Date().toLocaleDateString('fr-BE'),amount:total,status:'En attente'});
      persistLocal();
    }
    renderInvoices();e.target.reset();preview();dialog.close();document.querySelector('[data-view="invoices"]').click();toast('Facture créée avec succès');
  }catch{toast('Impossible de créer la facture')}
});

document.querySelector('#addClient').addEventListener('click',async()=>{
  const name=prompt('Nom du client');if(!name)return;
  const email=prompt('E-mail du client')||'';
  try{
    if(apiMode){
      const body=await api('/api/v1/clients',{method:'POST',body:JSON.stringify({name,email})});
      clients.push(body.data);
    }else{
      clients.push({id:`local-${Date.now()}`,name,email});persistLocal();
    }
    renderClients();toast('Client ajouté');
  }catch{toast('Impossible d’ajouter le client')}
});

document.querySelector('#showAll').addEventListener('click',()=>document.querySelector('[data-view="invoices"]').click());
document.querySelector('#invoiceSearch').addEventListener('input',e=>renderInvoices(e.target.value));
document.querySelector('#exportInvoices').addEventListener('click',()=>{
  const lines=[['Numero','Client','Date','Montant','Statut'],...invoices.map(i=>[i.id,i.client,i.date,Number(i.amount).toFixed(2),i.status])];
  const csv=lines.map(r=>r.map(v=>`"${String(v).replaceAll('"','""')}"`).join(';')).join('\n');
  const blob=new Blob(['\ufeff'+csv],{type:'text/csv;charset=utf-8'});const a=document.createElement('a');a.href=URL.createObjectURL(blob);a.download='pilot-factures.csv';a.click();URL.revokeObjectURL(a.href);toast('Export CSV généré');
});
document.querySelector('#newQuote').addEventListener('click',()=>toast('Création de devis : prochaine étape du MVP'));

async function boot(){
  apiMode=await detectApi();
  if(apiMode){
    try{await hydrateFromApi();document.querySelector('.demo-pill').textContent='API CONNECTÉE'}catch{apiMode=false;toast('API indisponible — mode démo local')}
  }
  renderClients();renderInvoices();
}
boot();
