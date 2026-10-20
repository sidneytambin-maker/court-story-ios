"use strict";
const hosts=["court-story-connect.web.app","court-story-connect.firebaseapp.com"];
let code="",link="",valid=false;
const status=document.getElementById("status");
function renderInvitation(){
  const fragment=window.location.hash.slice(1);
  code=fragment.split("/")[0];
  valid=/^[a-f0-9]{64}(?:\/(?:accept|decline))?$/.test(fragment)&&hosts.includes(window.location.hostname)&&window.location.pathname==="/connect/invite"&&!window.location.search;
  link=valid?"https://court-story-connect.web.app/connect/invite#"+code:"";

  document.getElementById("code").value=link;
  document.getElementById("invitation").hidden=!valid;
  document.getElementById("copy-status").textContent="";
  for(const action of ["accept","decline"]){
  const button=document.getElementById(action);
  button.removeAttribute("href");
  if(valid){
    // Another associated domain lets Safari hand the link to the app.
    // A user-tapped Android package intent also handles browser link defaults.
    const other=hosts.find(host=>host!==window.location.hostname);
    const fallback="https://"+other+"/connect/invite#"+code+"/"+action;
    button.href=/Android/i.test(navigator.userAgent)?
      "intent://court-story-connect.web.app/connect/invite#"+code+"/"+action+"#Intent;scheme=https;package=com.courtstory.app;S.browser_fallback_url="+encodeURIComponent(fallback)+";end":fallback;
  }
  }
  status.textContent=valid?"You have a connection invitation.":"This invitation is incomplete or invalid. Ask the sender for a new link.";
}
window.addEventListener("hashchange",renderInvitation);
window.addEventListener("pageshow",renderInvitation);
renderInvitation();
for(const action of ["accept","decline"])document.getElementById(action).addEventListener("click",event=>{
  renderInvitation();
  if(!valid){event.preventDefault();return;}
  document.getElementById("open-help").textContent="If Court Story does not open, use 'App did not open?' below. Your response will continue in Court Story. No records are shared until the player approves.";
});
document.getElementById("copy").addEventListener("click",async()=>{
  renderInvitation();if(!valid)return;
  const requestedLink=link;
  try{
    await navigator.clipboard.writeText(requestedLink);
    if(link===requestedLink)document.getElementById("copy-status").textContent="Invitation copied. Open Court Story, choose Connect, then Paste invitation.";
  }catch{
    if(link!==requestedLink)return;
    const field=document.getElementById("code");field.focus();field.select();
    document.getElementById("copy-status").textContent="The invitation is selected. Use your phone's Copy command.";
  }
});
