"""Existing control and non-combat item contracts, now authored in Excel."""
SPECIAL = {'haste','slow','freeze','consumable','material'}
TARGETS = {'haste':'own_other_active_item','slow':'enemy_active_item','freeze':'enemy_active_item'}


def expand(sheets, item, configured, values, put, rows, fail):
    iid, category = item['A'],item['C']
    if len(values)!=1: fail('物品总表',0,'A',f'{iid} 须有且只有一行四品质数值')
    vn,value=values[0]
    key=category if category in TARGETS else 'value'
    if value.get('B') not in ('',key) or value.get('C') not in ('',key):
        fail('效果数值',vn,'C',f'该模板效果 ID 与参数键应为 {key}')
    if not value.get('B'): put('效果数值',f'B{vn}',key)
    if not value.get('C'): put('效果数值',f'C{vn}',key)
    if category not in TARGETS or configured: return
    en=max([rn for rn,_ in rows(sheets['效果配置'])]+[4])+1
    fields=[iid,key,'1','use_self','self',category,TARGETS[category],'','否',category,'instant','quality_parameter',key,'由控制效果模板 v1 创建时复制']
    for col,val in zip('ABCDEFGHIJKLMN',fields): put('效果配置',f'{col}{en}',val)


def compile_item(sheets, row, n, qrows, *, rows, number, text, fail):
    iid,category=row['A'],row['C']
    values=[(rn,r)for rn,r in rows(sheets['效果数值'])if r.get('A')==iid]
    if len(values)!=1: fail('物品总表',n,'A','该物品须有且只有一行四品质数值')
    vn,v=values[0]
    key=category if category in TARGETS else 'value'
    if v.get('B')!=key or v.get('C')!=key: fail('效果数值',vn,'C',f'效果 ID 与参数键须为 {key}')
    amounts=[float(number(v,c,'效果数值',vn,0,True))for c in 'DEFG']
    if any(a>99999 for a in amounts):fail('效果数值',vn,'D','数值上限为 99999')
    configured=[(rn,r)for rn,r in rows(sheets['效果配置'])if r.get('A')==iid]
    effects=[]
    if category in TARGETS:
        if len(configured)!=1:fail('物品总表',n,'A','控制物品须有且只有一条效果')
        en,e=configured[0]
        expected=dict(B=key,C='1',D='use_self',E='self',F=category,G=TARGETS[category],H='',I='否',J=category,K='instant',L='quality_parameter',M=key)
        for col,value in expected.items():
            if text(e,col,'效果配置',en,False)!=value:fail('效果配置',en,col,f'该控制效果须为 {value or "空白"}')
        if any(a%100 for a in amounts):fail('效果数值',vn,'D','控制持续时间为毫秒，须为 100 毫秒整数倍')
        effects=[dict(id=key,type=category,values=amounts,target=TARGETS[category])]
    elif configured:
        fail('物品总表',n,'A','材料与战斗外恢复品不配置战斗效果')
    heal=amounts[0] if category=='consumable' else 0
    if category in ('consumable','material') and len(set(amounts))!=1:
        fail('效果数值',vn,'D','当前非战斗物品四品质数值须相同')
    return amounts,effects,heal
