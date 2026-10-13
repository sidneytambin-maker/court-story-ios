"use strict";
const code=window.location.hash.slice(1);
const valid=/^[a-f0-9]{64}$/.test(code)&&window.location.pathname==="/connect/invite"&&!window.location.search;
const status=document.getElementById("status");
if(valid){document.getElementById("code").value=code;document.getElementById("invitation").hidden=false;status.textContent="Invitation code ready. The app will verify who can accept it.";}else{status.textContent="This invitation link is incomplete or invalid. Ask the sender for the complete link or code.";}
document.getElementById("copy").addEventListener("click",async()=>{if(!valid)return;try{await navigator.clipboard.writeText(code);document.getElementById("copy-status").textContent="Invitation code copied.";}catch{const field=document.getElementById("code");field.focus();field.select();document.getElementById("copy-status").textContent="Automatic copying was unavailable. The code is selected; use your device’s Copy command.";}});
