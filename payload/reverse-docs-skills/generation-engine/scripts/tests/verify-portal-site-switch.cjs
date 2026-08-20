const fs=require('fs'),path=require('path');
const root='generation-engine/samples/project-portal';
function walk(d,a=[]){for(const e of fs.readdirSync(d,{withFileTypes:true})){const p=path.join(d,e.name);e.isDirectory()?walk(p,a):e.name.endsWith('.html')&&a.push(p);}return a;}
const files=walk(root);
let switchData=0, breadcrumbs=0, errs=[], breadcrumbErrs=[];
for(const f of files){
  const h=fs.readFileSync(f,'utf8');
  if(/id=(['"])(?:site-(?:list|switch)|pt-sites-data)\1|siteSwitch|SITE_LIST/.test(h)) switchData++;
  // 切替先要素を参照する処理が存在確認なしに使われていないか
  const m=h.match(/document\.getElementById\((['"])(site-[a-z-]+)\1\)\s*\.\w/g);
  if(m) errs.push(f+' → '+m[0]);
  const crumbs=h.match(/<([a-z][\w:-]*)\b[^>]*\bclass=(['"])(?:[^\s'"]+\s+)*pt-crumb(?:\s+[^\s'"]+)*\2[^>]*>[\s\S]*?<\/\1\s*>/gi)||[];
  breadcrumbs+=crumbs.length;
  for(const crumb of crumbs){
    const tokens=crumb.match(/\{\{[^{}]+\}\}|\{[^{}\s]+\}|｛[^｛｝\s]+｝/g)||[];
    tokens.forEach(token=>breadcrumbErrs.push(f+' → '+token));
  }
}
console.log('走査 '+files.length+' ページ');
console.log('サイト切替データを持つページ: '+switchData);
console.log('存在確認なしで切替先要素を参照: '+errs.length+' 件');
console.log('パンくず検査対象: '+breadcrumbs+' 件');
console.log('パンくず内の未置換記号: '+breadcrumbErrs.length+' 件');
errs.concat(breadcrumbErrs).slice(0,3).forEach(e=>console.log('  '+e));
process.exit(switchData>0&&breadcrumbs>0&&errs.length===0&&breadcrumbErrs.length===0?0:1);
