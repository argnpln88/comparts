// Select the new scoped token only after the project has been activated.
import {existsSync,readFileSync} from 'node:fs';
const root=new URL('../',import.meta.url);
const file=new URL('.env.account-connection.json',root);
if(existsSync(file)){
  const cfg=JSON.parse(readFileSync(file,'utf8'));
  const linked=readFileSync(new URL('supabase/.temp/project-ref',root),'utf8').trim();
  if(cfg.SUPABASE_PROJECT_REF===linked&&cfg.SUPABASE_ACCESS_TOKEN){
    process.env.SUPABASE_ACCESS_TOKEN=cfg.SUPABASE_ACCESS_TOKEN;
  }
}
