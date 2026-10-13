// Deploy as a scheduled Supabase Edge Function. All provider credentials are server secrets.
// No sporting records, tokens or provider responses are logged.
const enc = new TextEncoder();
const base64url = (data: Uint8Array) => btoa(String.fromCharCode(...data)).replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");
const json64 = (value: unknown) => base64url(enc.encode(JSON.stringify(value)));
function secret(name: string): string { const value=Deno.env.get(name); if(!value) throw new Error("Provider configuration incomplete"); return value; }
async function jwt(header: object, claims: object, pem: string, kind: "EC"|"RSA") {
  const der=Uint8Array.from(atob(pem.replace(/-----[^-]+-----|\s/g,"")),c=>c.charCodeAt(0));
  const algorithm=kind==="EC"?{name:"ECDSA",namedCurve:"P-256"}:{name:"RSASSA-PKCS1-v1_5",hash:"SHA-256"};
  const key=await crypto.subtle.importKey("pkcs8",der,algorithm,false,["sign"]);
  const message=json64(header)+"."+json64(claims);
  const signature=await crypto.subtle.sign(kind==="EC"?{name:"ECDSA",hash:"SHA-256"}:{name:"RSASSA-PKCS1-v1_5"},key,enc.encode(message));
  return message+"."+base64url(new Uint8Array(signature));
}
async function rpc(name: string,body: unknown) {
  const key=secret("SUPABASE_SERVICE_ROLE_KEY");
  const response=await fetch(secret("SUPABASE_URL")+"/rest/v1/rpc/"+name,{signal:AbortSignal.timeout(10000),method:"POST",headers:{apikey:key,Authorization:"Bearer "+key,"Content-Type":"application/json"},body:JSON.stringify(body)});
  if(!response.ok)throw new Error("Notification queue request failed");
  const text=await response.text();return text?JSON.parse(text):null;
}
type Delivery={notification_id:string;installation_id:string;platform:"apns"|"fcm";token:string;message:string;connection_id:string};
async function apns(row:Delivery){
  const now=Math.floor(Date.now()/1000);
  const token=await jwt({alg:"ES256",kid:secret("APNS_KEY_ID")},{iss:secret("APNS_TEAM_ID"),iat:now},secret("APNS_PRIVATE_KEY"),"EC");
  const response=await fetch("https://api.push.apple.com/3/device/"+encodeURIComponent(row.token),{signal:AbortSignal.timeout(10000),method:"POST",headers:{authorization:"bearer "+token,"apns-topic":secret("APNS_TOPIC"),"apns-push-type":"alert","apns-priority":"10","apns-collapse-id":row.notification_id,"apns-expiration":String(now+3600)},body:JSON.stringify({aps:{alert:{title:"Court Story Connect",body:row.message},sound:"default"},connect_notification:row.notification_id,connect_connection:row.connection_id})});
  return {delivered:response.ok,invalid:response.status===410};
}
async function fcm(row:Delivery){
  const service=JSON.parse(secret("FCM_SERVICE_ACCOUNT_JSON"));const now=Math.floor(Date.now()/1000);
  const assertion=await jwt({alg:"RS256",typ:"JWT"},{iss:service.client_email,scope:"https://www.googleapis.com/auth/firebase.messaging",aud:"https://oauth2.googleapis.com/token",iat:now,exp:now+3600},service.private_key,"RSA");
  const tokenResponse=await fetch("https://oauth2.googleapis.com/token",{signal:AbortSignal.timeout(10000),method:"POST",body:new URLSearchParams({grant_type:"urn:ietf:params:oauth:grant-type:jwt-bearer",assertion})});
  if(!tokenResponse.ok)throw new Error("Push authentication failed");const token=await tokenResponse.json();
  const response=await fetch("https://fcm.googleapis.com/v1/projects/"+encodeURIComponent(service.project_id)+"/messages:send",{signal:AbortSignal.timeout(10000),method:"POST",headers:{authorization:"Bearer "+token.access_token,"Content-Type":"application/json"},body:JSON.stringify({message:{token:row.token,data:{connect_notification:row.notification_id,connect_connection:row.connection_id},android:{priority:"high",ttl:"3600s"}}})});
  const result=await response.json();const invalid=(result?.error?.details??[]).some((x:{errorCode?:string})=>x.errorCode==="UNREGISTERED");
  return {delivered:response.ok,invalid};
}
Deno.serve(async(request:Request)=>{
  if(request.method!=="POST")return new Response("Method not allowed",{status:405});
  // The gateway additionally requires a valid legacy JWT. This private header is scheduler-only.
  const given=request.headers.get("X-Connect-Dispatch-Secret")??"";
  const expected=Deno.env.get("CONNECT_DISPATCH_SECRET");
  if(!expected)return new Response("Service unavailable",{status:503});
  const [a,b]=await Promise.all([crypto.subtle.digest("SHA-256",enc.encode(given)),crypto.subtle.digest("SHA-256",enc.encode(expected))]);
  if(!new Uint8Array(a).every((x,i)=>x===new Uint8Array(b)[i]))return new Response("Unauthorized",{status:401});
  let sent=0,failed=0;
  try {
    const deliveries:Delivery[]=await rpc("cs_claim_push",{p_limit:10});
    // Two bounded batches stay within the free worker execution window even if providers stall.
    for(let offset=0;offset<deliveries.length;offset+=5){
      const results=await Promise.allSettled(deliveries.slice(offset,offset+5).map(async row=>{
        let result={delivered:false,invalid:false};
        try{result=await(row.platform==="apns"?apns(row):fcm(row));}catch{ /* retry through the durable queue; never log provider credentials */ }
        await rpc("cs_finish_push",{p_notification:row.notification_id,p_installation:row.installation_id,p_delivered:result.delivered,p_invalid:result.invalid});
        if(result.delivered)sent++;else failed++;
      }));
      if(results.some(result=>result.status==="rejected"))throw new Error("Notification receipt unavailable");
    }
    return Response.json({sent,failed});
  } catch { return Response.json({error:"Notification dispatch unavailable"},{status:503}); }
});
