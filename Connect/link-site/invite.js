"use strict";
let code="";
let valid=false;
const status=document.getElementById("status");
function renderInvitation(){
  code=window.location.hash.slice(1);
  valid=/^[a-f0-9]{64}$/.test(code)&&window.location.pathname==="/connect/invite"&&!window.location.search;
  document.getElementById("code").value=valid?code:"";
  document.getElementById("invitation").hidden=!valid;
  document.getElementById("copy-status").textContent="";
  status.textContent=valid?"Invitation code ready. The app will verify who can accept it.":"This invitation link is incomplete or invalid. Ask the sender for the complete link or code.";
}
window.addEventListener("hashchange",renderInvitation);
window.addEventListener("pageshow",renderInvitation);
renderInvitation();
document.getElementById("copy").addEventListener("click",async()=>{
  renderInvitation();
  if(!valid)return;
  const requestedCode=code;
  try{
    await navigator.clipboard.writeText(requestedCode);
    if(window.location.hash.slice(1)===requestedCode)document.getElementById("copy-status").textContent="Invitation code copied.";
  }catch{
    if(window.location.hash.slice(1)!==requestedCode)return;
    const field=document.getElementById("code");field.focus();field.select();
    document.getElementById("copy-status").textContent="Automatic copying was unavailable. The code is selected; use your deviceâ€™s Copy command.";
  }
});
