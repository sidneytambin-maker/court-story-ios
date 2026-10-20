import {readFileSync} from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const source=readFileSync(new URL('../link-site/invite.js',import.meta.url),'utf8');
function page(hash,{search='',host='court-story-connect.web.app',agent='Android',clipboard=true}={}){
 const elements={};for(const id of ['code','invitation','status','copy','copy-status','accept','decline','open-help'])elements[id]={hidden:true,textContent:'',value:'',addEventListener(event,handler){this[event]=handler;},removeAttribute(key){delete this[key];},focus(){this.focused=true;},select(){this.selected=true;}};
 const copied=[],handlers={};const window={location:{hash,search,hostname:host,pathname:'/connect/invite'},addEventListener:(event,fn)=>handlers[event]=fn};
 vm.runInNewContext(source,{window,document:{getElementById:id=>elements[id]},navigator:{userAgent:agent,clipboard:{writeText:async value=>{if(!clipboard)throw Error('denied');copied.push(value);}}}});
 return {elements,copied,window,handlers};
}
const code='a'.repeat(64),link='https://court-story-connect.web.app/connect/invite#'+code;
const valid=page('#'+code);assert.equal(valid.elements.code.value,link);assert.equal(valid.elements.invitation.hidden,false);await valid.elements.copy.click();assert.deepEqual(valid.copied,[link]);
assert.ok(valid.elements['accept'].href.startsWith('intent://court-story-connect.web.app/connect/invite#'+code+'/accept#Intent;scheme=https;package=com.courtstory.app;'));
for(const fragment of ['','#'+code.slice(1),'#<script>alert(1)</script>','#'+code+'extra']){
 const bad=page(fragment);assert.equal(bad.elements.invitation.hidden,true);assert.equal(bad.elements['accept'].href,undefined);await bad.elements.copy.click();assert.deepEqual(bad.copied,[]);
 let prevented=false;bad.elements['accept'].click({preventDefault(){prevented=true;}});assert.equal(prevented,true);
}
assert.equal(page('#'+code,{search:'?code=leak'}).elements.invitation.hidden,true);
assert.equal(page('#'+code,{host:'evil.example'}).elements.invitation.hidden,true);
const denied=page('#'+code,{clipboard:false});await denied.elements.copy.click();assert.equal(denied.elements.code.selected,true);assert.equal(denied.elements.code.focused,true);
for(const host of ['court-story-connect.web.app','court-story-connect.firebaseapp.com']){
 const ios=page('#'+code,{host,agent:'iPhone Safari'});const target=new URL(ios.elements['accept'].href);assert.notEqual(target.hostname,host);assert.equal(target.hash,'#'+code+'/accept');assert.equal(target.search,'');
}
valid.window.location.hash='#'+'b'.repeat(64);valid.handlers.hashchange();assert.ok(valid.elements['accept'].href.includes('b'.repeat(64)));assert.equal(valid.elements['copy-status'].textContent,'');
valid.window.location.hash='#invalid';valid.handlers.pageshow();assert.equal(valid.elements['accept'].href,undefined);assert.equal(valid.elements.invitation.hidden,true);
// No page-load navigation, fetch, credentials or background clipboard access.
assert.equal(valid.window.location.hostname,'court-story-connect.web.app');assert.equal(valid.copied.length,1);
console.log('Invitation fallback: Android intent, alternate iPhone domain, user gesture, malformed/foreign/query links, copy, stale-link restoration and denied clipboard passed.');

for (const agent of ['Android Chrome','Android SamsungBrowser','iPhone Safari','iPad']) {
 for(const host of ['court-story-connect.web.app','court-story-connect.firebaseapp.com']) {
  const sample=page('#'+code,{host,agent});
  for(const action of ['accept','decline']) {
   assert.ok(sample.elements[action].href.includes(code+'/'+action));
   assert.ok(!sample.elements[action].href.includes('?code='));
   let prevented=false;sample.elements[action].click({preventDefault(){prevented=true;}});assert.equal(prevented,false);
  }
 }
}
for(const suffix of ['/accept/decline','/delete','/ACCEPT','/accept?other=1'])assert.equal(page('#'+code+suffix).elements.invitation.hidden,true);
for(const action of ['accept','decline']) {
 const restored=page('#'+code+'/'+action);assert.equal(restored.elements.invitation.hidden,false);
 assert.ok(restored.elements[action].href.includes(code+'/'+action));
}
const html=readFileSync(new URL('../link-site/index.html',import.meta.url),'utf8');
assert.ok(html.includes('>Accept invitation</a>'));assert.ok(html.includes('>Decline invitation</a>'));
assert.ok(!html.includes('id="open-app"'));
console.log('Accept and Decline carry independent responses across both hosts; malformed responses and redundant Open app button rejected.');
