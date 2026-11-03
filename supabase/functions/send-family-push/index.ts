// Miyako family trip Web Push sender.
// Deploy as Supabase Edge Function; do not expose VAPID private key in GitHub.
import webpush from "npm:web-push@3.6.7";

const cors = {"content-type":"application/json"};
const reply = (status:number, data:unknown) => new Response(JSON.stringify(data),{status,headers:cors});
const env = (name:string) => {const v=Deno.env.get(name);if(!v)throw new Error("Missing secret: "+name);return v;};

Deno.serve(async (req:Request)=>{
 if(req.method!=="POST")return reply(405,{error:"POST only"});
 const expected=Deno.env.get("MIYAKO_PUSH_WEBHOOK_SECRET");
 if(!expected || req.headers.get("x-miyako-push-secret")!==expected)return reply(401,{error:"Unauthorized"});
 try{
  const body=await req.json();
  if(body.type!=="INSERT"||body.table!=="family_app_notifications"||!body.record?.id)return reply(202,{skipped:"Not a notification insert"});
  const base=env("SUPABASE_URL");
  const key=env("SUPABASE_SERVICE_ROLE_KEY");
  const headers={apikey:key,Authorization:"Bearer "+key};
  // Retrieve the canonical record: never trust a webhook-supplied recipient.
  const id=encodeURIComponent(String(body.record.id));
  const notificationResponse=await fetch(base+"/rest/v1/family_app_notifications?select=id,recipient_user_id,read_at&id=eq."+id+"&limit=1",{headers});
  if(!notificationResponse.ok)throw new Error("Notification lookup failed: "+notificationResponse.status);
  const notifications=await notificationResponse.json();
  const notification=notifications[0];
  if(!notification?.recipient_user_id||notification.read_at)return reply(200,{skipped:"Missing or already read"});
  const recipient=encodeURIComponent(notification.recipient_user_id);
  const subscriptionsResponse=await fetch(base+"/rest/v1/family_push_subscriptions?select=id,endpoint,p256dh,auth_secret&auth_user_id=eq."+recipient,{headers});
  if(!subscriptionsResponse.ok)throw new Error("Subscriptions lookup failed: "+subscriptionsResponse.status);
  const subscriptions=await subscriptionsResponse.json();
  webpush.setVapidDetails(env("VAPID_SUBJECT"),env("VAPID_PUBLIC_KEY"),env("VAPID_PRIVATE_KEY"));
  // A nonzero badge is an estimate until the app refreshes unread count.
  // Do not send a fabricated count; the app synchronizes the exact count on open.
  const payload=JSON.stringify({event:"family-update"});
  let sent=0,failed=0,expired=0;
  for(const sub of subscriptions){
   try{
    await webpush.sendNotification({endpoint:sub.endpoint,keys:{p256dh:sub.p256dh,auth:sub.auth_secret}},payload,{TTL:3600,urgency:"normal"});
    sent++;
   }catch(error){
    const status=Number((error as {statusCode?:number}).statusCode||0);
    if(status===404||status===410){
     expired++;
     await fetch(base+"/rest/v1/family_push_subscriptions?id=eq."+encodeURIComponent(sub.id),{method:"DELETE",headers});
    }else{failed++;console.error("Web Push failed",status,String(error));}
   }
  }
  return reply(200,{sent,failed,expired});
 }catch(error){console.error("Push sender error",String(error));return reply(500,{error:"Push delivery failed; inspect function logs"});}
});
