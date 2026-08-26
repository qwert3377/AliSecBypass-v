// ElyndorTV VIP v4.0 — 合并精简版
// 合并v3.41会员状态 + v8等级V8，去掉广告拦截和NSDictionary Hook避免卡死

const TAG = { VIP: '[VIP]', JSON: '[JSON]', UD: '[UD]', UI: '[UI]' };
function log(t, m) { console.log(t + ' ' + m); }

// ===================== 字段配置 =====================
// VIP状态字段
const AUTH_KEYS = ['authcode', 'auth_code', 'status'];
// VIP过期字段
const EXPIRE_KEYS = ['expire', 'endtime', 'end_time', 'is_expired'];
// VIP等级字段（混淆+原始）
const LEVEL_KEYS = [
    'participantvoteterm', 'edtcactivedirectacquirecentral',
    'k9mnpq7xzv2r8w4t', 'kgdtdeviceav1forceresetdowngradeversionkey',
    'vip_level', 'viplevel', 'member_level', 'user_level', 'level', 'grade',
    'vipLevel', 'memberLevel', 'userLevel', 'vip_grade', 'vipGrade'
];
// NSUserDefaults关键key
const UD_KEYS = ['kvipStatusStorageKey', 'EDTCActiveDirectAcquireCentral'];

function matchKey(key, list) {
    const k = key.toLowerCase();
    return list.some(v => k === v.toLowerCase() || k.includes(v.toLowerCase()));
}
function isAuthKey(k) { return matchKey(k, AUTH_KEYS); }
function isExpireKey(k) { return matchKey(k, EXPIRE_KEYS); }
function isLevelKey(k) { return matchKey(k, LEVEL_KEYS); }
function isUDKey(k) { return UD_KEYS.some(v => v === k); }

// ===================== JSON Patch =====================
function patchDict(d) {
    if (!d || d.isNull() || !d.isKindOfClass_(ObjC.classes.NSDictionary)) return null;
    const keys = d.allKeys();
    if (!keys || keys.isNull()) return null;
    let need = false;
    for (let i = 0, n = keys.count(); i < n; i++) {
        const k = keys.objectAtIndex_(i).toString().toLowerCase();
        const v = d.objectForKey_(keys.objectAtIndex_(i));
        if (!v || v.isNull()) continue;
        if ((isAuthKey(k) && v.isKindOfClass_(ObjC.classes.NSNumber) && v.intValue() === 0) ||
            (isExpireKey(k) && (v.isKindOfClass_(ObjC.classes.NSString) || v.isKindOfClass_(ObjC.classes.NSNumber))) ||
            (isLevelKey(k) && v.isKindOfClass_(ObjC.classes.NSNumber) && v.intValue() >= 0 && v.intValue() < 8)) {
            need = true;
        }
    }
    if (!need) return null;
    const m = ObjC.classes.NSMutableDictionary.dictionaryWithDictionary_(d);
    for (let i = 0, n = keys.count(); i < n; i++) {
        const key = keys.objectAtIndex_(i);
        const ks = key.toString();
        const kl = ks.toLowerCase();
        const v = d.objectForKey_(key);
        if (!v || v.isNull()) continue;

        // auth/status → 1
        if (isAuthKey(kl)) {
            if (v.isKindOfClass_(ObjC.classes.NSNumber) && v.intValue() === 0) {
                m.setObject_forKey_(ObjC.classes.NSNumber.numberWithInt_(1), key);
                log(TAG.JSON, ks + ': 0→1');
            } else if (v.isKindOfClass_(ObjC.classes.NSString) && v.toString() === '0') {
                m.setObject_forKey_(ObjC.classes.NSString.stringWithString_('1'), key);
                log(TAG.JSON, ks + ': "0"→"1"');
            }
        }
        // expire → 2099
        else if (isExpireKey(kl)) {
            if (v.isKindOfClass_(ObjC.classes.NSString)) {
                m.setObject_forKey_(ObjC.classes.NSString.stringWithString_('2099-12-31'), key);
                log(TAG.JSON, ks + '→2099-12-31');
            } else if (v.isKindOfClass_(ObjC.classes.NSNumber)) {
                m.setObject_forKey_(ObjC.classes.NSNumber.numberWithLongLong_(4102444799000), key);
                log(TAG.JSON, ks + '→MAX');
            }
        }
        // level → 8
        else if (isLevelKey(kl)) {
            if (v.isKindOfClass_(ObjC.classes.NSNumber)) {
                const iv = v.intValue ? v.intValue() : 0;
                if (iv >= 0 && iv < 8) {
                    m.setObject_forKey_(ObjC.classes.NSNumber.numberWithInt_(8), key);
                    log(TAG.JSON, '等级 ' + ks + ': ' + iv + '→8');
                }
            } else if (v.isKindOfClass_(ObjC.classes.NSString)) {
                const s = v.toString();
                if (['0','1','2','3','4','5','6','7'].includes(s)) {
                    m.setObject_forKey_(ObjC.classes.NSString.stringWithString_('8'), key);
                    log(TAG.JSON, '等级 ' + ks + ': "' + s + '"→"8"');
                }
            }
        }
    }
    return m;
}

function patchDictRecursively(dict) {
    const p = patchDict(dict);
    if (p) return p;
    // 递归处理嵌套
    try {
        const keys = dict.allKeys();
        let modified = false;
        const m = ObjC.classes.NSMutableDictionary.dictionaryWithDictionary_(dict);
        for (let i = 0; i < keys.count(); i++) {
            const key = keys.objectAtIndex_(i);
            const val = dict.objectForKey_(key);
            if (val.isKindOfClass_(ObjC.classes.NSDictionary)) {
                const nested = patchDictRecursively(val);
                if (nested) { m.setObject_forKey_(nested, key); modified = true; }
            } else if (val.isKindOfClass_(ObjC.classes.NSArray)) {
                const arr = ObjC.classes.NSMutableArray.arrayWithArray_(val);
                let arrMod = false;
                for (let j = 0; j < arr.count(); j++) {
                    const item = arr.objectAtIndex_(j);
                    if (item.isKindOfClass_(ObjC.classes.NSDictionary)) {
                        const np = patchDictRecursively(item);
                        if (np) { arr.replaceObjectAtIndex_withObject_(j, np); arrMod = true; }
                    }
                }
                if (arrMod) { m.setObject_forKey_(arr, key); modified = true; }
            }
        }
        return modified ? m : null;
    } catch(e) { return null; }
}

// ===================== 1. NSJSONSerialization =====================
function hookJSON() {
    const JSON = ObjC.classes.NSJSONSerialization;
    if (!JSON) return;
    try {
        const m = JSON['+ JSONObjectWithData:options:error:'];
        if (m && m.implementation) {
            Interceptor.attach(m.implementation, {
                onLeave(retval) {
                    try {
                        if (retval.isNull()) return;
                        const obj = new ObjC.Object(retval);
                        if (!obj.isKindOfClass_(ObjC.classes.NSDictionary)) return;
                        const p = patchDictRecursively(obj);
                        if (p) retval.replace(p);
                    } catch(e) {}
                }
            });
            log(TAG.VIP, '已Hook NSJSONSerialization');
        }
    } catch(e) {}
}

// ===================== 2. NSUserDefaults（安全版）====================
function hookUserDefaults() {
    const UD = ObjC.classes.NSUserDefaults;
    if (!UD) return;

    // boolForKey:
    try {
        const m = UD['- boolForKey:'];
        if (m && m.implementation) {
            Interceptor.attach(m.implementation, {
                onEnter(args) {
                    try { this.isUD = isUDKey(new ObjC.Object(args[2]).toString()); } catch(e) { this.isUD = false; }
                },
                onLeave(retval) {
                    try { if (this.isUD) retval.replace(1); } catch(e) {}
                }
            });
        }
    } catch(e) {}

    // integerForKey:
    try {
        const m = UD['- integerForKey:'];
        if (m && m.implementation) {
            Interceptor.attach(m.implementation, {
                onEnter(args) {
                    try {
                        const key = new ObjC.Object(args[2]).toString();
                        this.isUD = isUDKey(key);
                        this.isLevel = isLevelKey(key);
                    } catch(e) { this.isUD = false; this.isLevel = false; }
                },
                onLeave(retval) {
                    try {
                        if (this.isUD || this.isLevel) {
                            const val = retval.toInt32 ? retval.toInt32() : parseInt(retval);
                            if (val >= 0 && val < 8) retval.replace(8);
                        }
                    } catch(e) {}
                }
            });
        }
    } catch(e) {}

    // stringForKey: — 安全写法：alloc+init
    try {
        const m = UD['- stringForKey:'];
        if (m && m.implementation) {
            Interceptor.attach(m.implementation, {
                onEnter(args) {
                    try {
                        const key = new ObjC.Object(args[2]).toString();
                        this.isUD = isUDKey(key);
                        this.isLevel = isLevelKey(key);
                    } catch(e) { this.isUD = false; this.isLevel = false; }
                },
                onLeave(retval) {
                    try {
                        if (retval.isNull()) return;
                        if (this.isUD || this.isLevel) {
                            const val = new ObjC.Object(retval).toString();
                            if (['0','1','2','3','4','5','6','7'].includes(val)) {
                                const newStr = ObjC.classes.NSString.alloc().initWithString_('8');
                                retval.replace(newStr);
                                log(TAG.UD, 'UD等级: "' + val + '"→"8"');
                            }
                        }
                    } catch(e) {}
                }
            });
        }
    } catch(e) {}

    // objectForKey:
    try {
        const m = UD['- objectForKey:'];
        if (m && m.implementation) {
            Interceptor.attach(m.implementation, {
                onEnter(args) {
                    try {
                        const key = new ObjC.Object(args[2]).toString();
                        this.isUD = isUDKey(key);
                        this.isLevel = isLevelKey(key);
                    } catch(e) { this.isUD = false; this.isLevel = false; }
                },
                onLeave(retval) {
                    try {
                        if (retval.isNull()) return;
                        if (this.isUD || this.isLevel) {
                            const val = new ObjC.Object(retval);
                            if (val.isKindOfClass_(ObjC.classes.NSNumber)) {
                                const iv = val.intValue ? val.intValue() : 0;
                                if (iv >= 0 && iv < 8) {
                                    retval.replace(ObjC.classes.NSNumber.numberWithInt_(8));
                                    log(TAG.UD, 'UD等级: ' + iv + '→8');
                                }
                            } else if (val.isKindOfClass_(ObjC.classes.NSString)) {
                                const s = val.toString();
                                if (['0','1','2','3','4','5','6','7'].includes(s)) {
                                    retval.replace(ObjC.classes.NSString.alloc().initWithString_('8'));
                                    log(TAG.UD, 'UD等级: "' + s + '"→"8"');
                                }
                            }
                        }
                    } catch(e) {}
                }
            });
        }
    } catch(e) {}

    log(TAG.VIP, '已Hook NSUserDefaults');
}

// ===================== 3. NSMutableDictionary setObject:forKey: =====================
function hookMutableDict() {
    const MD = ObjC.classes.NSMutableDictionary;
    if (!MD) return;
    try {
        const m = MD['- setObject:forKey:'];
        if (m && m.implementation) {
            Interceptor.attach(m.implementation, {
                onEnter(args) {
                    try {
                        const key = new ObjC.Object(args[3]).toString();
                        const val = new ObjC.Object(args[2]);
                        const kl = key.toLowerCase();

                        if (isAuthKey(kl)) {
                            if (val.isKindOfClass_(ObjC.classes.NSNumber) && val.intValue() === 0) {
                                args[2] = ObjC.classes.NSNumber.numberWithInt_(1);
                                log(TAG.VIP, 'MD auth: 0→1');
                            } else if (val.isKindOfClass_(ObjC.classes.NSString) && val.toString() === '0') {
                                args[2] = ObjC.classes.NSString.stringWithString_('1');
                                log(TAG.VIP, 'MD auth: "0"→"1"');
                            }
                        } else if (isExpireKey(kl) && val.isKindOfClass_(ObjC.classes.NSString)) {
                            args[2] = ObjC.classes.NSString.stringWithString_('2099-12-31');
                            log(TAG.VIP, 'MD expire→2099');
                        } else if (isLevelKey(kl)) {
                            if (val.isKindOfClass_(ObjC.classes.NSNumber)) {
                                const iv = val.intValue ? val.intValue() : 0;
                                if (iv >= 0 && iv < 8) {
                                    args[2] = ObjC.classes.NSNumber.numberWithInt_(8);
                                    log(TAG.VIP, 'MD等级: ' + iv + '→8');
                                }
                            }
                        }
                    } catch(e) {}
                }
            });
            log(TAG.VIP, '已Hook NSMutableDictionary');
        }
    } catch(e) {}
}

// ===================== 4. UILabel setText: =====================
function hookUILabel() {
    const LABEL = ObjC.classes.UILabel;
    if (!LABEL) return;
    try {
        const m = LABEL['- setText:'];
        if (m && m.implementation) {
            Interceptor.attach(m.implementation, {
                onEnter(args) {
                    try {
                        const t = new ObjC.Object(args[2]).toString();
                        let nt = null;
                        if (t.includes('立即开通') || t.includes('尚未开通') || t.includes('未开通') || t.includes('非会员')) {
                            nt = 'VIP会员已开通';
                            log(TAG.UI, '"' + t + '"→"VIP会员已开通"');
                        }
                        if (nt) args[2] = ObjC.classes.NSString.stringWithString_(nt);
                    } catch(e) {}
                }
            });
            log(TAG.VIP, '已Hook UILabel');
        }
    } catch(e) {}
}

// ===================== 5. hasVipMembership =====================
function forceVIP() {
    const cls = ObjC.classes['ElyndorTVCode.EDTCDeviceCoreHandler'];
    if (!cls) {
        log(TAG.VIP, '[-] 未找到 EDTCDeviceCoreHandler');
        return;
    }
    try {
        const m = cls['+ hasVipMembership'];
        if (m && m.implementation) {
            Interceptor.attach(m.implementation, {
                onLeave(retval) {
                    try {
                        const val = retval.toInt32 ? retval.toInt32() : parseInt(retval);
                        if (val === 0) {
                            retval.replace(1);
                            log(TAG.VIP, 'hasVipMembership: 0→1');
                        }
                    } catch(e) {}
                }
            });
            log(TAG.VIP, '已Hook hasVipMembership');
        }
    } catch(e) {}
}

// ===================== Main =====================
function main() {
    console.log('\n=== ElyndorTV VIP v4.0 ===');
    console.log('=== 合并精简版 (v3.41会员 + v8等级V8) ===\n');

    if (!ObjC.available) {
        console.log('[-] ObjC不可用');
        return;
    }

    hookJSON();
    hookUserDefaults();
    hookMutableDict();
    hookUILabel();
    forceVIP();

    console.log('\n=== 已激活 ===');
    console.log('=== NSJSONSerialization + NSUserDefaults + NSMutableDictionary + UILabel + hasVipMembership ===\n');
}

setTimeout(main, 500);
