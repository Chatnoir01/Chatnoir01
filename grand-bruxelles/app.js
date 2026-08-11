const communes=["Anderlecht","Auderghem","Berchem-Sainte-Agathe","Bruxelles-Ville","Etterbeek","Evere","Forest","Ganshoren","Ixelles","Jette","Koekelberg","Molenbeek-Saint-Jean","Saint-Gilles","Saint-Josse-ten-Noode","Schaerbeek","Uccle","Watermael-Boitsfort","Woluwe-Saint-Lambert","Woluwe-Saint-Pierre"];
const places=[
{name:"Grand-Place",commune:"Bruxelles-Ville",category:"Patrimoine",lat:50.8467,lng:4.3525,featured:true,blurb:"Le cœur historique de Bruxelles et son ensemble architectural emblématique."},
{name:"Atomium",commune:"Bruxelles-Ville",category:"Architecture",lat:50.8949,lng:4.3416,featured:true,blurb:"L’icône futuriste construite pour l’Expo 58, devenue un symbole de Bruxelles."},
{name:"Parc du Cinquantenaire",commune:"Bruxelles-Ville",category:"Parc",lat:50.8419,lng:4.3905,featured:true,blurb:"Arcades monumentales, musées et grande pelouse au cœur du quartier européen."},
{name:"Place Flagey",commune:"Ixelles",category:"Quartier",lat:50.827,lng:4.3728,featured:true,blurb:"Un carrefour vivant d’Ixelles entre culture, cafés, étangs et vie nocturne."},
{name:"Bois de la Cambre",commune:"Bruxelles-Ville",category:"Parc",lat:50.8067,lng:4.382,featured:true,blurb:"Un immense poumon vert relié à la forêt de Soignes."},
{name:"Musées royaux des Beaux-Arts",commune:"Bruxelles-Ville",category:"Culture",lat:50.8429,lng:4.3587,featured:true,blurb:"Un ensemble muséal majeur consacré à plusieurs siècles d’art."},
{name:"Place du Jeu de Balle",commune:"Bruxelles-Ville",category:"Marché",lat:50.837,lng:4.3457,blurb:"Le marché aux puces quotidien au centre du quartier des Marolles."},
{name:"Maison communale de Schaerbeek",commune:"Schaerbeek",category:"Architecture",lat:50.867,lng:4.3735,blurb:"Un monument néo-Renaissance flamande au centre de Schaerbeek."},
{name:"Basilique de Koekelberg",commune:"Koekelberg",category:"Patrimoine",lat:50.8674,lng:4.3171,blurb:"Une basilique Art déco monumentale dominant le nord-ouest de la ville."},
{name:"Parc de Woluwe",commune:"Woluwe-Saint-Pierre",category:"Parc",lat:50.829,lng:4.437,blurb:"Paysages vallonnés, étangs et longues promenades dans l’est bruxellois."},
{name:"Abbaye de la Cambre",commune:"Ixelles",category:"Patrimoine",lat:50.8187,lng:4.3756,blurb:"Un ancien site abbatial niché dans la vallée du Maelbeek."},
{name:"Parc Duden",commune:"Forest",category:"Parc",lat:50.8178,lng:4.3262,blurb:"Un parc escarpé et boisé offrant de belles perspectives sur Bruxelles."},
{name:"Parvis de Saint-Gilles",commune:"Saint-Gilles",category:"Quartier",lat:50.8307,lng:4.3446,blurb:"Terrasses, marché et animation au pied de l’hôtel de ville de Saint-Gilles."},
{name:"Tour & Taxis",commune:"Bruxelles-Ville",category:"Culture",lat:50.8641,lng:4.3482,blurb:"Un ancien site industriel reconverti en pôle culturel, événementiel et urbain."},
{name:"Étangs de Mellaerts",commune:"Woluwe-Saint-Pierre",category:"Parc",lat:50.827,lng:4.43,blurb:"Un paysage d’étangs apprécié pour la promenade et les loisirs."},
{name:"Place Cardinal Mercier",commune:"Jette",category:"Quartier",lat:50.8791,lng:4.3287,blurb:"Le centre animé de Jette, près de la gare et des commerces."},
{name:"Maison d’Érasme",commune:"Anderlecht",category:"Culture",lat:50.8364,lng:4.3066,blurb:"Une maison-musée historique entourée de jardins au cœur d’Anderlecht."},
{name:"Rouge-Cloître",commune:"Auderghem",category:"Patrimoine",lat:50.8133,lng:4.438,blurb:"Ancien prieuré en lisière de la forêt de Soignes, aujourd’hui lieu culturel."},
{name:"Forêt de Soignes — Boitsfort",commune:"Watermael-Boitsfort",category:"Parc",lat:50.7897,lng:4.417,blurb:"Une porte d’entrée bruxelloise vers le grand massif forestier de Soignes."},
{name:"Parc Josaphat",commune:"Schaerbeek",category:"Parc",lat:50.8646,lng:4.3865,blurb:"Un grand parc paysager très apprécié des Schaerbeekois."},
{name:"Place Jourdan",commune:"Etterbeek",category:"Quartier",lat:50.8377,lng:4.381,blurb:"Une place conviviale bordée de restaurants dans le quartier européen."},
{name:"Parc de Laeken",commune:"Bruxelles-Ville",category:"Parc",lat:50.8895,lng:4.356,blurb:"Un vaste domaine vert proche du palais royal et des serres de Laeken."},
{name:"Place Dumon",commune:"Woluwe-Saint-Pierre",category:"Quartier",lat:50.8375,lng:4.4277,blurb:"Un centre commerçant et convivial de Stockel."},
{name:"Parc Elisabeth",commune:"Koekelberg",category:"Parc",lat:50.8672,lng:4.3225,blurb:"Une grande perspective verte menant à la basilique."}
];
const categories=["Tous",...new Set(places.map(p=>p.category))];let activeCategory="Tous";let markers=[];
const communeGrid=document.querySelector("#commune-grid"),featuredGrid=document.querySelector("#featured-grid"),filters=document.querySelector("#filters"),results=document.querySelector("#results"),searchInput=document.querySelector("#search"),menuButton=document.querySelector(".menu-button"),mobileNav=document.querySelector("#mobile-nav");
document.querySelector("#place-count").textContent=places.length;
communeGrid.innerHTML=communes.map((c,i)=>`<article class="commune-card"><span class="commune-index">${String(i+1).padStart(2,"0")}</span><h3>${c}</h3></article>`).join("");
featuredGrid.innerHTML=places.filter(p=>p.featured).map(p=>`<article class="feature-card"><div class="feature-meta">${p.category} · ${p.commune}</div><h3>${p.name}</h3><p>${p.blurb}</p></article>`).join("");
filters.innerHTML=categories.map(c=>`<button type="button" class="filter ${c==="Tous"?"active":""}" data-category="${c}">${c}</button>`).join("");
const map=L.map("map",{zoomControl:true,scrollWheelZoom:false}).setView([50.8466,4.3528],12);
L.tileLayer("https://tile.openstreetmap.org/{z}/{x}/{y}.png",{maxZoom:19,attribution:"&copy; OpenStreetMap contributors"}).addTo(map);
function popupHTML(p){return `<strong>${p.name}</strong><span>${p.category} · ${p.commune}</span><p>${p.blurb}</p>`}
function renderMarkers(list){markers.forEach(m=>map.removeLayer(m));markers=list.map(p=>{const m=L.circleMarker([p.lat,p.lng],{radius:7,color:"#111116",weight:2,fillColor:"#ffd322",fillOpacity:1}).addTo(map).bindPopup(popupHTML(p));m.placeName=p.name;return m})}
function filteredPlaces(){const q=searchInput.value.trim().toLocaleLowerCase("fr");return places.filter(p=>{const category=activeCategory==="Tous"||p.category===activeCategory;const haystack=`${p.name} ${p.commune} ${p.category} ${p.blurb}`.toLocaleLowerCase("fr");return category&&(!q||haystack.includes(q))})}
function render(){const list=filteredPlaces();results.innerHTML=list.length?list.map(p=>`<button type="button" class="result-card" data-place="${p.name}"><strong>${p.name}</strong><span>${p.category} · ${p.commune}</span></button>`).join(""):`<div class="no-results">Aucun lieu ne correspond à cette recherche.</div>`;renderMarkers(list)}
filters.addEventListener("click",e=>{const b=e.target.closest("[data-category]");if(!b)return;activeCategory=b.dataset.category;filters.querySelectorAll(".filter").forEach(i=>i.classList.toggle("active",i===b));render()});
searchInput.addEventListener("input",render);
results.addEventListener("click",e=>{const card=e.target.closest("[data-place]");if(!card)return;const p=places.find(i=>i.name===card.dataset.place);if(!p)return;map.flyTo([p.lat,p.lng],15,{duration:.8});const marker=markers.find(i=>i.placeName===p.name);if(marker)marker.openPopup()});
menuButton.addEventListener("click",()=>{const open=menuButton.getAttribute("aria-expanded")==="true";menuButton.setAttribute("aria-expanded",String(!open));mobileNav.hidden=open});
mobileNav.addEventListener("click",e=>{if(e.target.matches("a")){mobileNav.hidden=true;menuButton.setAttribute("aria-expanded","false")}});
render();
