function ensureProductUi(){
  if(document.querySelector('[data-view="settings"]'))return;
  const nav=document.querySelector('nav');
  const button=document.createElement('button');button.className='nav';button.dataset.view='settings';button.textContent='Paramètres';nav.appendChild(button);
  const section=document.createElement('section');section.id='settings';section.className='view';section.innerHTML=`<div class="panel"><div class="panel-head"><div><h3>Paramètres entreprise</h3><p>Informations utilisées sur vos documents commerciaux.</p></div></div><form id="companyForm" class="settings-form"><div class="form-grid"><label>Nom de l’entreprise<input id="companyName" required></label><label>E-mail<input id="companyEmail" type="email" required></label></div><label>Adresse<input id="companyAddress" required></label><div class="form-grid"><label>N° TVA / BCE<input id="companyVat" required placeholder="BE0123.456.789"></label><label>IBAN<input id="companyIban" required placeholder="BE00 0000 0000 0000"></label></div><div class="settings-actions"><button class="primary" type="submit">Enregistrer</button><button class="ghost" type="button" id="logoutButton">Se déconnecter</button></div><p class="settings-note">Ces informations apparaissent sur les factures imprimées. Vérifiez-les avant émission.</p></form></div>`;
  document.querySelector('main').appendChild(section);
  const style=document.createElement('style');style.textContent=`.settings-form{max-width:760px}.settings-actions{display:flex;gap:10px;align-items:center;margin-top:8px}.settings-note{margin-top:18px!important}.pdf-action{border:0;background:#eef0f3;padding:7px 10px;border-radius:8px;cursor:pointer;font-weight:700;margin-right:5px;font-size:11px}`;document.head.appendChild(style);
  document.querySelectorAll('.nav').forEach(btn=>btn.onclick=()=>{document.querySelectorAll('.nav,.view').forEach(x=>x.classList.remove('active'));btn.classList.add('active');document.querySelector('#'+btn.dataset.view).classList.add('active');if(btn.dataset.view==='settings')loadCompanySettings();});
  section.querySelector('#companyForm').onsubmit=saveCompanySettings;
  section.querySelector('#logoutButton').onclick=logoutPilot;
}
async function loadCompanySettings(){
  if(!apiMode){toast('Les paramètres persistants nécessitent le serveur Pilot');return;}
  try{const body=await api('/api/v1/organization');const c=body.data;document.querySelector('#companyName').value=c.name||'';document.querySelector('#companyEmail').value=c.email||'';document.querySelector('#companyAddress').value=c.address||'';document.querySelector('#companyVat').value=c.vatNumber||'';document.querySelector('#companyIban').value=c.iban||'';}catch{toast('Impossible de charger les paramètres');}
}
async function saveCompanySettings(e){
  e.preventDefault();
  try{const payload={name:document.querySelector('#companyName').value.trim(),email:document.querySelector('#companyEmail').value.trim(),address:document.querySelector('#companyAddress').value.trim(),vatNumber:document.querySelector('#companyVat').value.trim(),iban:document.querySelector('#companyIban').value.trim()};const body=await api('/api/v1/organization',{method:'PATCH',body:JSON.stringify(payload)});if(currentUser)currentUser.organization=body.data;renderApp();toast('Paramètres entreprise enregistrés');}catch(err){toast(err.status===400?'Informations entreprise incomplètes':'Impossible d’enregistrer les paramètres');}
}
async function logoutPilot(){try{await api('/api/auth/logout',{method:'POST'});}catch{}location.reload();}
function attachPdfButtons(){
  if(!apiMode)return;
  document.querySelectorAll('#invoiceRows tr,#allInvoiceRows tr').forEach(tr=>{if(tr.querySelector('.pdf-action'))return;const menu=tr.querySelector('.row-action');if(!menu)return;const pdf=document.createElement('button');pdf.className='pdf-action';pdf.type='button';pdf.textContent='PDF';pdf.onclick=e=>{e.stopPropagation();window.open(`/api/v1/invoices/${encodeURIComponent(menu.dataset.key)}/document`,'_blank','noopener');};menu.parentElement.insertBefore(pdf,menu);});
}
const invoiceObserver=new MutationObserver(()=>attachPdfButtons());
function startProductEnhancements(){ensureProductUi();document.querySelectorAll('#invoiceRows,#allInvoiceRows').forEach(t=>invoiceObserver.observe(t,{childList:true,subtree:true}));attachPdfButtons();}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',startProductEnhancements);else startProductEnhancements();
