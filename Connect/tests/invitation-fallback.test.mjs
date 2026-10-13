import {readFileSync} from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const source=readFileSync(new URL('../link-site/invite.js',import.meta.url),'utf8');
function page(hash,search='',clipboard=true){const elements={};for(const id of ['code','invitation','status','copy','copy-status'])elements[id]={hidden:true,textContent:'',value:'',addEventListener(event,handler){this[event]=handler;},focus(){this.focused=true;},select(){this.selected=true;}};const copied=[];vm.runInNewContext(source,{window:{location:{hash,search,pathname:'/connect/invite'}},document:{getElementById:id=>elements[id]},navigator:{clipboard:{writeText:async value=>{if(!clipboard)throw Error('denied');copied.push(value);}}}});return {elements,copied};}
const code='a'.repeat(64);
const valid=page('#'+code);assert.equal(valid.elements.code.value,code);assert.equal(valid.elements.invitation.hidden,false);await valid.elements.copy.click();assert.deepEqual(valid.copied,[code]);
for(const fragment of ['','#'+code.slice(1),'#<script>alert(1)</script>','#'+code+'extra']){const bad=page(fragment);assert.equal(bad.elements.invitation.hidden,true);await bad.elements.copy.click();assert.deepEqual(bad.copied,[]);}
assert.equal(page('#'+code,'?code=leak').elements.invitation.hidden,true);
const denied=page('#'+code,'',false);await denied.elements.copy.click();assert.equal(denied.elements.code.selected,true);assert.equal(denied.elements.code.focused,true);
console.log('Invitation fallback: valid code, malformed fragments, query rejection and clipboard fallback passed. No network APIs exposed to the page test.');
