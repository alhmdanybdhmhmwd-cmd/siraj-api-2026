import test from "node:test";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { handleResumableMediaUpload, cleanupExpiredUploadSessions } from "../src/src/media_multipart_routes.js";

const MiB = 1024 * 1024;
const USER = { sub: "user-1" };

class FakeD1 {
  constructor() {
    this.sessions = new Map(); this.chunks = new Map(); this.parts = new Map();
    this.friendships = new Set(["user-1:friend-1","user-1:friend-2"]); this.groups = new Set(["group-1:user-1","group-2:user-1"]);
  }
  prepare(sql) {
    const db=this; let args=[];
    const stmt={
      bind(...v){args=v;return stmt;},
      async first(){
        const q=sql.replace(/\s+/g," ").trim();
        if(q.includes("sqlite_master")) return {name:"media_upload_sessions"};
        if(q.includes("FROM friendships")) return db.friendships.has(args.join(":"))?{1:1}:null;
        if(q.includes("FROM group_members")) return db.groups.has(args.join(":"))?{1:1}:null;
        if(q.includes("FROM media_upload_sessions")&&q.includes("idempotency_key")){
          const r=[...db.sessions.values()].find(x=>x.owner_id===args[0]&&x.idempotency_key===args[1]);
          return r?{id:r.id,state:r.state,size:r.total_size,expectedParts:r.expected_parts,expiresAt:r.expires_at,recipientId:r.recipient_id,groupId:r.group_id,contentType:r.content_type,fileName:r.file_name}:null;
        }
        if(q.includes("FROM media_upload_sessions")&&q.includes("WHERE id = ? AND owner_id = ?")){
          const r=db.sessions.get(args[0]);return r&&r.owner_id===args[1]?{...r}:null;
        }
        if(q.includes("FROM media_upload_parts")&&q.includes("part_number = ?")) return db.parts.get(args[0]+":"+args[1])||null;
        if(q.includes("FROM media_upload_chunks")&&q.includes("chunk_number = ?")) return db.chunks.get(args[0]+":"+args[1])||null;
        return null;
      },
      async all(){
        const q=sql.replace(/\s+/g," ").trim();
        if(q.includes("FROM media_upload_sessions")&&q.includes("expires_at <= ?")) return {results:[...db.sessions.values()].filter(x=>(["uploading","completing","failed"].includes(x.state)&&x.expires_at<=args[0])||(x.state==="completed"&&[...db.chunks.values()].some(ch=>ch.session_id===x.id))).slice(0,50).map(x=>({id:x.id,object_key:x.object_key,storage_upload_id:x.storage_upload_id,state:x.state}))};
        if(q.includes("sqlite_master")) return {results:[{name:"media_upload_sessions"},{name:"media_upload_parts"},{name:"media_upload_chunks"}]};
        if(q.includes("FROM media_upload_parts")) return {results:[...db.parts.values()].filter(x=>x.session_id===args[0]).sort((a,b)=>a.part_number-b.part_number).map(x=>({partNumber:x.part_number,etag:x.etag,size:x.size}))};
        if(q.includes("FROM media_upload_chunks")&&q.includes("BETWEEN")) return {results:[...db.chunks.values()].filter(x=>x.session_id===args[0]&&x.chunk_number>=args[1]&&x.chunk_number<=args[2]).sort((a,b)=>a.chunk_number-b.chunk_number).map(x=>({chunkNumber:x.chunk_number,size:x.size}))};
        if(q.includes("FROM media_upload_chunks")) return {results:[...db.chunks.values()].filter(x=>x.session_id===args[0]).map(x=>({chunkNumber:x.chunk_number}))};
        return {results:[]};
      },
      async run(){
        const q=sql.replace(/\s+/g," ").trim();
        if(q.startsWith("INSERT INTO media_upload_sessions")){
          const [id,owner,recipient,group,objectKey,uploadId,fileName,type,size,partSize,expected,idempotency,expires]=args;
          db.sessions.set(id,{id,owner_id:owner,recipient_id:recipient,group_id:group,object_key:objectKey,storage_upload_id:uploadId,file_name:fileName,content_type:type,total_size:size,part_size:partSize,expected_parts:expected,idempotency_key:idempotency,state:"uploading",expires_at:expires});
          return {meta:{changes:1}};
        }
        if(q.startsWith("INSERT INTO media_upload_chunks")){
          const [sid,n,size]=args;db.chunks.set(sid+":"+n,{session_id:sid,chunk_number:n,size});return {meta:{changes:1}};
        }
        if(q.startsWith("INSERT INTO media_upload_parts")){
          const [sid,n,etag,size]=args;db.parts.set(sid+":"+n,{session_id:sid,part_number:n,etag,size});return {meta:{changes:1}};
        }
        if(q.startsWith("UPDATE media_upload_sessions SET state = 'completing'")){const r=db.sessions.get(args[0]);if(r)r.state="completing";return {meta:{changes:r?1:0}};}
        if(q.startsWith("UPDATE media_upload_sessions SET state = 'uploading'")){const r=db.sessions.get(args[0]);if(r)r.state="uploading";return {meta:{changes:r?1:0}};}
        if(q.startsWith("UPDATE media_upload_sessions SET state = 'completed'")){const r=db.sessions.get(args[0]);if(r)r.state="completed";return {meta:{changes:r?1:0}};}
        if(q.startsWith("UPDATE media_upload_sessions SET state = 'aborted'")){const r=db.sessions.get(args[0]);if(r)r.state="aborted";return {meta:{changes:r?1:0}};}
        if(q.startsWith("UPDATE media_upload_sessions SET updated_at")) return {meta:{changes:1}};
        if(q.startsWith("DELETE FROM media_upload_chunks")&&q.includes("BETWEEN")){for(const [k,r] of db.chunks)if(r.session_id===args[0]&&r.chunk_number>=args[1]&&r.chunk_number<=args[2])db.chunks.delete(k);return {meta:{changes:1}};}
        if(q.startsWith("DELETE FROM media_upload_chunks")){for(const [k,r] of db.chunks)if(r.session_id===args[0])db.chunks.delete(k);return {meta:{changes:1}};}
        if(q.startsWith("DELETE FROM media_upload_sessions")){const r=db.sessions.get(args[0]);if(r&&r.expires_at<=args[1]&&["uploading","completing","failed"].includes(r.state))db.sessions.delete(args[0]);return {meta:{changes:1}};}
        if(q.startsWith("DELETE FROM media_upload_parts")){for(const [k,r] of db.parts)if(r.session_id===args[0])db.parts.delete(k);return {meta:{changes:1}};}
        return {meta:{changes:1}};
      }
    };return stmt;
  }
  async batch(statements){const out=[];for(const s of statements)out.push(await s.run());return out;}
}
function fixture(){
  const DB=new FakeD1(),objects=new Map(),uploads=new Map(),originalFetch=globalThis.fetch;
  globalThis.fetch=async(input,init={})=>{
    const req=input instanceof Request?input:new Request(input,init),u=new URL(req.url);
    const key=decodeURIComponent(u.pathname.split("/").slice(1).join("/")),uploadId=u.searchParams.get("uploadId"),part=Number(u.searchParams.get("partNumber"));
    if(req.method==="POST"&&u.searchParams.has("uploads")){const id="upload-"+(uploads.size+1);uploads.set(id,{key,parts:new Map(),aborted:false});return new Response("<UploadId>"+id+"</UploadId>");}
    if(uploadId&&req.method==="PUT"&&part){const up=uploads.get(uploadId);if(!up||up.aborted)return new Response("",{status:404});const b=new Uint8Array(await req.arrayBuffer()),etag=createHash("md5").update(b).digest("hex");up.parts.set(part,{bytes:b,etag});return new Response("",{headers:{ETag:'"'+etag+'"'}});}
    if(uploadId&&req.method==="POST"){const up=uploads.get(uploadId);if(!up)return new Response("",{status:404});const list=[...up.parts.entries()].sort((a,b)=>a[0]-b[0]),len=list.reduce((s,x)=>s+x[1].bytes.length,0),out=new Uint8Array(len);let off=0;for(const [,p] of list){out.set(p.bytes,off);off+=p.bytes.length;}objects.set(up.key,out);return new Response("<CompleteMultipartUploadResult/>");}
    if(uploadId&&req.method==="DELETE"){const up=uploads.get(uploadId);if(up)up.aborted=true;return new Response(null,{status:204});}
    if(req.method==="PUT"){objects.set(key,new Uint8Array(await req.arrayBuffer()));return new Response("",{status:200});}
    if(req.method==="GET"){const b=objects.get(key);return b?new Response(b):new Response("",{status:404});}
    if(req.method==="DELETE"){objects.delete(key);return new Response(null,{status:204});}
    return new Response("unsupported",{status:400});
  };
  const env={DB,TIGRIS_ACCESS_KEY_ID:"fake-key",TIGRIS_SECRET_ACCESS_KEY:"fake-secret",TIGRIS_BUCKET:"test-bucket"};
  async function call(path,method="POST",body=null,user=USER){
    const request=new Request("https://preview.invalid"+path,{method,headers:{"Content-Type":"application/json"},body:body===null?undefined:(body instanceof Uint8Array?body:JSON.stringify(body))});
    return handleResumableMediaUpload(request,env,user,new URL(request.url),path,method);
  }
  return {DB,objects,uploads,call,restore(){globalThis.fetch=originalFetch;}};
}
const declaration=(size,key="idem-key-0001",extra={})=>({size,contentType:"application/octet-stream",fileName:"payload.bin",recipientId:"friend-1",idempotencyKey:key,...extra});
const chunk=(data,n)=>data.slice((n-1)*MiB,Math.min(n*MiB,data.length));

test("route integration: interruption, resume, duplicate chunks, exact final bytes and completion retry",async t=>{
  const f=fixture();t.after(f.restore);
  const source=Uint8Array.from({length:5*MiB+17},(_,i)=>(i*31+7)%256);
  const created=await f.call("/api/media/uploads","POST",declaration(source.length));assert.equal(created.status,201);
  const sessionId=(await created.json()).session.id;
  for(let n=1;n<=3;n++)assert.equal((await f.call("/api/media/uploads/"+sessionId+"/chunks/"+n,"PUT",chunk(source,n))).status,200);
  const conflicting=chunk(source,2).slice();conflicting[0]^=0xff;
  assert.equal((await f.call("/api/media/uploads/"+sessionId+"/chunks/2","PUT",conflicting)).status,409);
  assert.equal((await f.call("/api/media/uploads/"+sessionId+"/chunks/2","PUT",chunk(source,2))).status,200);
  assert.equal((await f.call("/api/media/uploads/"+sessionId+"/complete","POST",{})).status,409);
  const resumed=await f.call("/api/media/uploads","POST",declaration(source.length));assert.equal(resumed.status,200);
  const rb=await resumed.json();assert.equal(rb.resumed,true);assert.equal(rb.session.id,sessionId);
  assert.equal((await f.call("/api/media/uploads/"+sessionId+"/chunks/1","PUT",chunk(source,1))).status,200);
  for(let n=4;n<=5;n++)assert.equal((await f.call("/api/media/uploads/"+sessionId+"/chunks/"+n,"PUT",chunk(source,n))).status,200);
  assert.equal(f.DB.parts.has(sessionId+":1"),true);
  assert.equal([...f.DB.chunks.values()].filter(x=>x.session_id===sessionId).length,0);
  assert.equal([...f.objects.keys()].some(k=>k.includes(".barq-staging/")),false);
  const duplicate=await f.call("/api/media/uploads/"+sessionId+"/chunks/5","PUT",chunk(source,5));
  assert.equal(duplicate.status,200);assert.equal((await duplicate.json()).alreadyStored,true);
  const lastChunk=await f.call("/api/media/uploads/"+sessionId+"/chunks/6","PUT",chunk(source,6));assert.equal(lastChunk.status,200,await lastChunk.clone().text());
  assert.equal(f.DB.parts.has(sessionId+":2"),true,"last 17-byte part must be committed");
  const done=await f.call("/api/media/uploads/"+sessionId+"/complete","POST",{});assert.equal(done.status,201,await done.clone().text());
  const attachment=(await done.json()).attachment,stored=f.objects.get(attachment.attachmentId);
  assert.ok(stored);assert.equal(stored.length,source.length);
  assert.equal(createHash("sha256").update(stored).digest("hex"),createHash("sha256").update(source).digest("hex"));
  assert.equal(f.DB.sessions.get(sessionId).state,"completed");
  const retry=await f.call("/api/media/uploads/"+sessionId+"/complete","POST",{});assert.equal(retry.status,200);
  assert.equal((await retry.json()).alreadyCompleted,true);
  assert.equal((await f.call("/api/media/uploads/"+sessionId,"DELETE")).status,409);
  assert.equal(f.objects.has(attachment.attachmentId),true);
});

test("route integration: idempotency declaration mismatch is rejected",async t=>{
  const f=fixture();t.after(f.restore);
  assert.equal((await f.call("/api/media/uploads","POST",declaration(100))).status,201);
  const variants=[declaration(101),declaration(100,"idem-key-0001",{fileName:"other.bin"}),declaration(100,"idem-key-0001",{contentType:"image/png"}),declaration(100,"idem-key-0001",{recipientId:"friend-2"})];
  for(const body of variants)assert.equal((await f.call("/api/media/uploads","POST",body)).status,409);
});

test("route integration: membership is enforced and abort removes staging only",async t=>{
  const f=fixture();t.after(f.restore);
  assert.equal((await f.call("/api/media/uploads","POST",declaration(10,"idem-denied-01",{recipientId:"stranger"}))).status,403);
  const created=await f.call("/api/media/uploads","POST",declaration(10,"idem-abort-001"));assert.equal(created.status,201);
  const id=(await created.json()).session.id;
  assert.equal((await f.call("/api/media/uploads/"+id+"/chunks/1","PUT",Uint8Array.from([1,2,3,4,5,6,7,8,9,10]))).status,200);
  assert.equal((await f.call("/api/media/uploads/"+id,"DELETE")).status,200);
  assert.equal(f.DB.sessions.get(id).state,"aborted");
  assert.equal([...f.objects.keys()].some(k=>k.includes(".barq-staging/")),false);
  assert.equal([...f.objects.keys()].some(k=>k.includes("/chat-media/")),false);
});


test("route integration: payload sizes from just over 4 MiB through the 60 MiB ceiling",async t=>{
  const f=fixture();t.after(f.restore);
  const sizes=[4*MiB+17,10*MiB+13,30*MiB+7,60*MiB];
  for(let index=0;index<sizes.length;index++){
    const size=sizes[index],source=new Uint8Array(size);
    for(let i=0;i<size;i++)source[i]=(i*17+size)%251;
    const key="stress-upload-"+String(index+1).padStart(4,"0");
    const created=await f.call("/api/media/uploads","POST",declaration(size,key));
    assert.equal(created.status,201,"create upload for "+size+" bytes");
    const id=(await created.json()).session.id,totalChunks=Math.ceil(size/MiB);
    for(let n=1;n<=totalChunks;n++){
      const response=await f.call("/api/media/uploads/"+id+"/chunks/"+n,"PUT",chunk(source,n));
      assert.equal(response.status,200,"upload chunk "+n+" of "+totalChunks+" for "+size+" bytes");
    }
    const done=await f.call("/api/media/uploads/"+id+"/complete","POST",{});
    assert.equal(done.status,201,"complete upload for "+size+" bytes");
    const attachment=(await done.json()).attachment,stored=f.objects.get(attachment.attachmentId);
    assert.ok(stored,"final object exists for "+size+" bytes");
    assert.equal(stored.length,size);
    assert.equal(createHash("sha256").update(stored).digest("hex"),createHash("sha256").update(source).digest("hex"));
    assert.equal([...f.objects.keys()].some(k=>k.includes(".barq-staging/")),false);
    f.objects.delete(attachment.attachmentId);f.uploads.clear();
  }
});


test("route security: upload sessions are isolated to their owner",async t=>{
  const f=fixture();t.after(f.restore);
  const created=await f.call("/api/media/uploads","POST",declaration(32,"owner-only-001"));
  assert.equal(created.status,201);
  const id=(await created.json()).session.id;
  const intruder={sub:"user-2"};
  const read=await f.call("/api/media/uploads/"+id+"/complete","POST",{},intruder);
  assert.equal(read.status,404,"another account must not discover or complete this session");
  const chunk=await f.call("/api/media/uploads/"+id+"/chunks/1","PUT",Uint8Array.from({length:32},(_,i)=>i),intruder);
  assert.equal(chunk.status,404,"another account must not upload into this session");
  assert.equal(f.DB.sessions.get(id).state,"uploading");
});

test("route security: expired sessions reject chunk upload and completion",async t=>{
  const f=fixture();t.after(f.restore);
  const created=await f.call("/api/media/uploads","POST",declaration(32,"expired-session-001"));
  assert.equal(created.status,201);
  const id=(await created.json()).session.id;
  f.DB.sessions.get(id).expires_at="2000-01-01T00:00:00.000Z";
  const chunk=await f.call("/api/media/uploads/"+id+"/chunks/1","PUT",new Uint8Array(32));
  assert.equal(chunk.status,410);
  const complete=await f.call("/api/media/uploads/"+id+"/complete","POST",{});
  assert.equal(complete.status,410);
});


test("route security: revoked conversation membership blocks further upload and completion",async t=>{
  const f=fixture();t.after(f.restore);
  const created=await f.call("/api/media/uploads","POST",declaration(32,"revoked-member-001"));
  assert.equal(created.status,201);
  const id=(await created.json()).session.id;
  f.DB.friendships.delete("user-1:friend-1");
  const chunk=await f.call("/api/media/uploads/"+id+"/chunks/1","PUT",new Uint8Array(32));
  assert.equal(chunk.status,403,"revoked member must not upload more bytes");
  const complete=await f.call("/api/media/uploads/"+id+"/complete","POST",{});
  assert.equal(complete.status,403,"revoked member must not complete an upload");
  assert.equal(f.DB.sessions.get(id).state,"uploading");
});


test("cleanup integration: expired incomplete sessions abort multipart and remove staging only",async t=>{
  const f=fixture();t.after(f.restore);
  const created=await f.call("/api/media/uploads","POST",declaration(64,"cleanup-expired-001"));
  assert.equal(created.status,201);
  const id=(await created.json()).session.id;
  const session=f.DB.sessions.get(id);
  session.expires_at="2000-01-01T00:00:00.000Z";
  const stagingKey=session.object_key+".barq-staging/"+id+"/1";
  f.objects.set(stagingKey,Uint8Array.from([1,2,3]));
  const result=await cleanupExpiredUploadSessions({DB:f.DB,TIGRIS_ACCESS_KEY_ID:"fake-key",TIGRIS_SECRET_ACCESS_KEY:"fake-secret",TIGRIS_BUCKET:"test-bucket"},Date.parse("2001-01-01T00:00:00.000Z"));
  assert.equal(result.checked,1);assert.equal(result.cleaned,1);
  assert.equal(f.DB.sessions.has(id),false);
  assert.equal(f.objects.has(stagingKey),false);
  assert.equal([...f.objects.keys()].some(k=>k.includes("/chat-media/")),false,"cleanup must not touch final media");
});
