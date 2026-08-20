const fs=require('fs');
const html=fs.readFileSync('delivery-payload/templates/common-doc-template.html','utf8');
const blocks=[...html.matchAll(/<script>([\s\S]*?)<\/script>/g)].map(m=>m[1]);
const targets=[
  {name:'目次生成ブロック',index:blocks.findIndex(b=>b.includes("getElementById('toc-list')"))},
  {name:'.toc-link操作ブロック',index:blocks.findIndex(b=>b.includes("querySelectorAll('.toc-link')"))}
];
const missing=targets.filter(target=>target.index<0).map(target=>target.name);
if(missing.length){console.log('FAIL: 対象の処理が見つからない → '+missing.join(', '));process.exit(1);}
if(new Set(targets.map(target=>target.index)).size!==targets.length){console.log('FAIL: 2つの処理が別々のscriptブロックに存在しない');process.exit(1);}

function verifyTocGeneration(code){
  const content={innerHTML:'',querySelector:()=>null,querySelectorAll:()=>[]};
  const elements={
    'doc-md':{textContent:JSON.stringify('# 文書タイトル')},
    'doc-content':content,
    'dp-hero-title':{textContent:''},
    'doc-empty-callout':{hidden:true},
    'toc-list':null
  };
  global.document={
    getElementById:id=>Object.prototype.hasOwnProperty.call(elements,id)?elements[id]:null,
    createElement:()=>({style:{},classList:{add(){},remove(){}},appendChild(){},setAttribute(){}})
  };
  global.window={addEventListener:()=>{},requestAnimationFrame:f=>f()};
  global.requestAnimationFrame=global.window.requestAnimationFrame;
  new Function(code)();
}

function verifyTocLinks(code){
  let clickHandler=null;
  let popstateHandler=null;
  const link={
    classList:{add(){},remove(){}},
    getAttribute:name=>name==='href'?'#missing':null,
    addEventListener:(event,handler)=>{if(event==='click')clickHandler=handler;}
  };
  const section={id:'present'};
  global.document={
    getElementById:()=>null,
    querySelectorAll:selector=>selector==='.toc-link'?[link]:selector==='.sec-block'?[section]:[]
  };
  global.window={
    addEventListener:(event,handler)=>{if(event==='popstate')popstateHandler=handler;},
    matchMedia:()=>({matches:false}),
    location:{hash:'#missing'},
    history:{pushState(){}}
  };
  global.requestAnimationFrame=f=>f();
  global.IntersectionObserver=class {
    constructor(callback,options){if(options.root!==null)throw new Error('main-scroll欠落時のrootがnullではない');this.callback=callback;}
    observe(target){this.callback([{isIntersecting:true,target}]);}
  };
  new Function(code)();
  if(!clickHandler||!popstateHandler)throw new Error('イベントハンドラが登録されない');
  clickHandler.call(link,{preventDefault(){}});
  popstateHandler();
}

try{
  verifyTocGeneration(blocks[targets[0].index]);
  verifyTocLinks(blocks[targets[1].index]);
  console.log('PASS: 2つのscriptブロックが検査対象要素の欠落時も例外を投げずに終了する');
  process.exit(0);
}
catch(e){console.log('FAIL: 例外が発生 → '+e.message+'\n'+String(e.stack).split('\n').slice(1,4).join('\n'));process.exit(1);}
