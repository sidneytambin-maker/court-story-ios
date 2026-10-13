type Handler=(request:Request)=>Response|Promise<Response>;
const originalServe=Deno.serve, originalFetch=globalThis.fetch;
let handler:Handler;
const assert=(value:unknown,message:string)=>{if(!value)throw new Error(message)};
async function load(path:string){
 Object.defineProperty(Deno,"serve",{value:(fn:Handler)=>{handler=fn;return {}},configurable:true});
 try {await import(path);}finally{Object.defineProperty(Deno,"serve",{value:originalServe,configurable:true});}
 return handler!;
}
Deno.test("Account deletion uses verified caller identity and rejects failed authentication",async()=>{
 Deno.env.set("SUPABASE_URL","https://synthetic.example.invalid");Deno.env.set("SUPABASE_SERVICE_ROLE_KEY","synthetic-test-key");
 const account=await load("../functions/delete-account/index.ts");
 let calls:string[]=[];
 globalThis.fetch=async(input,init)=>{const url=String(input);calls.push(url);if(url.endsWith("/auth/v1/user"))return Response.json({id:"verified-synthetic-user"});assert(url.endsWith("/auth/v1/admin/users/verified-synthetic-user"),"Must delete the authenticated account only");assert(init?.method==="DELETE","Must use deletion endpoint");return new Response(null,{status:204})};
 try {
  assert((await account(new Request("https://local.invalid",{method:"DELETE"}))).status===401,"Missing session denied");assert(calls.length===0,"Unauthenticated request must not contact admin API");
  const response=await account(new Request("https://local.invalid?account=someone-else",{method:"DELETE",headers:{Authorization:"Bearer synthetic-user-session"}}));assert(response.status===204,"Verified deletion succeeds");assert(calls.length===2,"Verify identity before deleting");
  globalThis.fetch=async()=>new Response("private provider response",{status:401});assert((await account(new Request("https://local.invalid",{method:"DELETE",headers:{Authorization:"Bearer invalid"}}))).status===401,"Invalid session denied");
 } finally {globalThis.fetch=originalFetch;}
});
Deno.test("Push dispatch requires scheduler authorization and reports no sensitive provider data",async()=>{
 Deno.env.set("CONNECT_DISPATCH_SECRET","synthetic-scheduler-secret");
 const dispatch=await load("../functions/dispatch-notifications/index.ts");let calls=0;
 globalThis.fetch=async()=>{calls++;return Response.json([])};
 try {
  const denied=await dispatch(new Request("https://local.invalid",{method:"POST",headers:{Authorization:"Bearer wrong"}}));assert(denied.status===401,"Wrong scheduler secret denied");assert(calls===0,"Unauthorized request cannot claim tokens");
  const ok=await dispatch(new Request("https://local.invalid",{method:"POST",headers:{Authorization:"Bearer synthetic-scheduler-secret"}}));assert(ok.status===200,"Authorized empty queue succeeds");const body=await ok.json();assert(body.sent===0&&body.failed===0,"Only counts returned");
  globalThis.fetch=async()=>{throw new Error("sensitive-provider-detail")};const failure=await dispatch(new Request("https://local.invalid",{method:"POST",headers:{Authorization:"Bearer synthetic-scheduler-secret"}}));assert(failure.status===503,"Provider failure is retryable");assert(!(await failure.text()).includes("sensitive-provider-detail"),"Sensitive provider details are not returned");
 } finally {globalThis.fetch=originalFetch;}
});
