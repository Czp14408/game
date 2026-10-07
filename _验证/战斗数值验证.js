
const api=(function(){
const defs={
 knife:{cd:40,type:"weapon",v:[12,18,28,42],size:2},
 short:{cd:20,type:"weapon",v:[4,6,9,13],size:1},
 bandit:{cd:30,type:"weapon",v:[8,12,18,26],size:1},
 hammer:{cd:70,type:"weapon",v:[30,45,65,90],size:3},
 ward:{cd:50,type:"shield",v:[12,20,32,48],size:2,charge:true},
 shield:{cd:80,type:"shield",v:[28,45,70,105],size:3},
 heal:{cd:60,type:"heal",v:[8,13,20,30],size:2},
 fire:{cd:50,type:"burn",v:[4,6,9,13],size:2},
 poison:{cd:60,type:"poison",v:[2,3,5,8],size:2},
 haste:{cd:60,type:"haste",v:[20,30,40,50],size:1},
 slow:{cd:70,type:"slow",v:[30,40,50,60],size:2},
 freeze:{cd:80,type:"freeze",v:[10,15,20,25],size:2}
};
function actor(spec){
 const max=spec.max??(spec.blood==="tough"?120:100);
 return {max,hp:spec.hp??max,shield:0,burn:0,poison:0,prof:spec.prof,blood:spec.blood,skills:spec.skills??{},
 items:spec.items.map(([id,q=0,extra=0])=>({...defs[id],id,q,value:defs[id].v[q]+extra,left:defs[id].cd,freeze:0,slow:0,haste:0,growth:0,uses:0})),
 healActual:0,healComputed:0,stormDamage:0};
}
function fight(ps,es,seed=1){
 let rng=seed>>>0;function random(){rng+=0x6D2B79F5;let z=rng;z=Math.imul(z^(z>>>15),z|1);z^=z+Math.imul(z^(z>>>7),z|61);return((z^(z>>>14))>>>0)/4294967296;}
 const p=actor(ps),e=actor(es),sides=[p,e]; let frames=0;
 function heal(a,n){n+=a.prof==="medic"?2:0;a.healComputed+=n;const actual=Math.min(n,a.max-a.hp);a.hp+=actual;a.healActual+=actual;return true;}
 function ordinary(a,n){const used=Math.min(a.shield,n);a.shield-=used;a.hp-=n-used;}
 for(let t=1;t<=2000;t++){
 frames=t; const locked=sides.map(a=>a.items.filter(x=>{
 const frozen=x.freeze>0;const speed=x.haste>0&&x.slow>0?1:x.haste>0?2:x.slow>0?.5:1;
 if(!frozen)x.left=Math.max(0,x.left-speed);
 x.freeze=Math.max(0,x.freeze-1);x.slow=Math.max(0,x.slow-1);x.haste=Math.max(0,x.haste-1);
 return !frozen&&x.left<=0;
 }));
 const events=[[],[]];
 sides.forEach((a,i)=>{for(const x of locked[i]){
 x.left=x.cd;x.uses++;
 if(x.type==="shield"){a.shield+=x.value;events[i].push(["shieldUse",x]);}
 if(x.type==="heal"){heal(a,x.value);events[i].push(["heal",x]);}
 }});
 sides.forEach((a,i)=>{const target=sides[1-i];for(const x of locked[i]){
 if(x.type==="weapon"){ordinary(target,x.value+x.growth+(a.prof==="warrior"?2:0));events[i].push(["weaponUse",x]);}
 }});
 if(t%10===0){for(const a of sides){ordinary(a,a.burn);a.burn=Math.max(0,a.burn-1);a.hp-=a.poison;}}
 if(t>=300&&t%10===0){const n=5*(1+(t-300)/10);for(const a of sides){a.hp-=n;a.stormDamage+=n;}}
 if(p.hp<=0||e.hp<=0)break;
 sides.forEach((a,i)=>{
 const target=sides[1-i];
 for(const x of locked[i]){
 if(x.type==="burn"){target.burn+=x.value;events[i].push(["burnApply",x]);}
 if(x.type==="poison")target.poison+=x.value;
 if(["slow","freeze","haste"].includes(x.type)){
 const pool=x.type==="haste"?a.items.filter(y=>y!==x):target.items;
 if(pool.length){const y=pool[Math.floor(random()*pool.length)];y[x.type]+=x.value;}
 }
 }
 for(const [event] of events[i]){
 if(event==="weaponUse"){
 for(const y of a.items)if(y.charge)y.left=Math.max(0,y.left-10);
 if(a.blood==="vampire"){heal(a,1);if(a.skills.recovery!=null)a.shield+=[2,3,5,8][a.skills.recovery];}
 }
 if(event==="shieldUse"&&a.skills.rage!=null)for(const y of a.items)if(y.type==="weapon")y.growth+=[1,2,3,4][a.skills.rage];
 if(event==="burnApply"&&a.skills.fire!=null)a.shield+=[2,4,7,11][a.skills.fire];
 if(event==="heal"&&a.skills.recovery!=null)a.shield+=[2,3,5,8][a.skills.recovery];
 }
 });
 }
 const report=a=>({hp:Math.max(0,a.hp),shield:a.shield,healActual:a.healActual,healComputed:a.healComputed,stormDamage:a.stormDamage,uses:a.items.map(x=>[x.id,x.q,x.uses])});
 return{win:p.hp>0&&e.hp<=0,timeout:frames===2000&&p.hp>0&&e.hp>0,time:frames/10,p:report(p),e:report(e)};
}
return {fight,defs};
})();
const {fight}=api;
const base={prof:"warrior",blood:"tough"};
const enemies={normal:{max:48,items:[["bandit"]]},guard:{max:60,items:[["knife"],["ward"]]},camp:{max:48,items:[["knife"]]},head:{max:84,items:[["hammer",0,6]]}};
const templates=[{name:"直接攻击",items:[["knife",1],["short"],["ward"]]},{name:"防御恢复",items:[["knife"],["shield"],["heal"]]},{name:"持续伤害",items:[["fire"],["poison"],["ward"]]}];
const result={assumptions:{stepSeconds:.1,crit:0,randomSeeds:"1..100",scope:"首阶段样本，随机商品与掉落序列作为明确输入，不估计总体通关率"}};
function route(kind){
 let hp=120;const out=[];
 for(const node of["02","05","08","12","15"]){
  if(kind!=="failure"&&node==="08"||kind==="failure"&&node==="12")hp=Math.min(120,hp+30);
  let items=[["knife"]];
  if(node!=="02")items.push(["ward",kind==="normal"&&["12","15"].includes(node)?1:0]);
  if(kind!=="failure"&&["08","12","15"].includes(node))items.push(["short"]);
  if(kind==="normal"&&node==="15")items[0][1]=1;
  const r=fight({...base,hp,items},enemies[({"02":"normal","05":"normal","08":"guard","12":"camp","15":"head"})[node]]);
  out.push({node,startHp:hp,...r});hp=r.p.hp;
 }
 return out;
}
result.normal=route("normal");result.low=route("low");result.failure=route("failure");
result.bossGrid=[];
for(const upgraded of[false,true])for(const template of templates)for(const extra of["heal","slow","freeze"]){
 let wins=0,minHp=Infinity,maxHp=0,maxTime=0;
 for(let seed=1;seed<=100;seed++){const r=fight({...base,items:[["knife",upgraded?1:0],["ward",upgraded?1:0],["short"]]}, {max:100,items:[...template.items,[extra]]},seed);
 wins+=r.win;minHp=Math.min(minHp,r.p.hp);maxHp=Math.max(maxHp,r.p.hp);maxTime=Math.max(maxTime,r.time);}
 result.bossGrid.push({upgraded,template:template.name,extra,wins,trials:100,minHp,maxHp,maxTime});
}
result.adjustments=[];
for(const set of[{name:"短刃白银",items:[["knife"],["ward"],["short",1]]},{name:"越战越勇",items:[["knife"],["ward"],["short"]],skills:{rage:0}},{name:"治疗",items:[["knife"],["ward"],["short"],["heal"]]},{name:"重锤",items:[["knife"],["ward"],["short"],["hammer"]]}]){
 result.adjustments.push({name:set.name,results:[0,2].map(i=>({template:templates[i].name,...fight({...base,...set},{max:100,items:[...templates[i].items,["heal"]]},1)}))});
}
result.retry={head:fight({...base,items:[["knife"],["ward"],["short"]]},enemies.head),boss:fight({...base,items:[["knife"],["ward"],["short"]],skills:{rage:0}}, {max:100,items:[...templates[2].items,["heal"]]},1)};
const regressions=[
 [fight({items:[["knife"],["ward"]]},enemies.head),28,28,true],
 [fight({items:[["knife"],["ward"],["short"]]},enemies.head),18,76,true],
 [fight({hp:72,items:[["knife"],["ward"]]},enemies.head),28,0,false]
];
for(const[r,t,h,w]of regressions)if(r.time!==t||r.p.hp!==h||r.win!==w)throw new Error("基础规则回归失败");
result.cash={
 normal:30+30+12+24+7-54-22,
 lowBeforeStage:30+30+12+24+20-44-22,
 lowAfterSkill:30+30+12+24+20-44-22-12,
 failureAfterRetries:30+30+12+24+20-44-22-12
};
if(result.normal.at(-1).p.hp!==102||result.low.at(-1).p.hp!==78||result.failure.at(-1).win||result.retry.head.p.hp!==96||result.retry.boss.p.hp!==60)throw new Error("路线结果不一致");
process.stdout.write(JSON.stringify(result,null,2));

