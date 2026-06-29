//<![CDATA[
(function(){'use strict';
var _csrfToken = (typeof document!=='undefined' && document.token) ? document.token : null;
var formState = {
  applied: false,
  originalMac: '',
  logical: '',
  device: '',
  spoofSupported: false,
  portalType: '',
  deviceVendor: '' 
};
var isEditingProfile = false;
var currentEditProfileId = null;
var savedProfileInterfaces = new Set();
var portalConfig = {};
var AUTOLOGIN_CONFIG = {
  VENDOR_OUI: {
    android:["A45046","B0F28D","FCF136","9C028E","F0EE10","286C07","64CC2E","28E347","F8A45F","A09347","BC3AEA","2C282D","50D2F5","E45AA2","6CFE54","D4F9A4","C8D15E","E8CD2D","08152F","F4F5DB","D85D4C","88D7F6","70EF00","04FE8D","A42BB0","98FAA7","60A44C","24DA9B"],
    macos:["ACDE48","F01898","D4619D","3C0754","A4B197","F40F24","28CFDA","7CD1C3","40A6D9","B8E856","001CB3","002332","00254B","68A86D","7C6D62"],
    linux:["B827EB","D83ADD","E45F01","50C7BF","60E327","F4EC38","0896AD","D4CA6D","4C5E0C","0016E3","001A4B","080027","525400","000569","00163E","001C14"],
    windows:["F0DEF1","3C5282","40B034","C85B76","0024D7","E8B1FC","AC220B","005056","00155D","001C42","001DE0","00215A","00248E","3C970E","549F35","B42E99"]
  },
  LOGIN_METHODS: [
    { value: '', label: 'Pilih Login Method' },
    { value: 'Standar', label: 'Standar' },
	{ value: 'Wico', label: 'Wico' },
    { value: 'Komunitas', label: 'Komunitas', sub: [
      { value: '', label: 'Pilih Opsi' },
      { value: 'Voucher Gift', label: 'Voucher Gift' },
      { value: 'Grosir & UMKM', label: 'Grosir & UMKM' },
      { value: 'Smart Bisnis', label: 'Smart Bisnis' },
      { value: 'Kampus', label: 'Kampus' },
      { value: 'Rumah Sakit', label: 'Rumah Sakit' },
      { value: 'Internetku', label: 'Internetku' },
      { value: 'SSO', label: 'SSO' }
    ]},
    { value: 'ISP', label: 'ISP', sub: [
      { value: '', label: 'Pilih Opsi' },
      { value: 'Boingo', label: 'Boingo' },
      { value: 'iPass', label: 'iPass' },
      { value: 'Nusanet', label: 'Nusanet' }
    ]}
  ],
  CAMPUS_CONFIG: {
    'ut.ac.id': { targetDomain: 'com.ut', description: 'Universitas Terbuka' },
    'unej.ac.id': { targetDomain: 'com.unej', description: 'Universitas Jember' },
    'umaha.ac.id': { targetDomain: 'com.umaha', description: 'Universitas Mahasaraswati' },
    'trisakti.ac.id': { targetDomain: 'com.trisakti', description: 'Universitas Trisakti' },
    'itdel.ac.id': { targetDomain: 'com.itdel', description: 'Institut Teknologi Del' },
    'polije.ac.id': { targetDomain: 'com.polije', description: 'Politeknik Negeri Jember' },
    'unsiq.ac.id': { targetDomain: 'com.unsiq', description: 'Universitas Sains Al-Qur\'an' }
  }
};

var WMS_USERNAME_SUFFIXES = {
  "violet": "@violet", "violet.unm": "@violet.unm", "violet.ugm": "@violet.ugm",
  "violet.unpatti": "@violet.unpatti", "violet.unp": "@violet.unp", "violet.uho": "@violet.uho",
  "violet.murid": "@violet.murid", "violet.guru": "@violet.guru", "violet.pjk": "@violet.pjk",
  "violet.mesh": "@violet.mesh", "lolipop": "@lolipop", "sooltan.id": "@sooltan.id"
};

var USERNAME_SUFFIX_MAP = {
    'Standar': '@spin2',
	'Wico': '@violet',
    'Komunitas': {
        'Voucher Gift': '@gift',
        'Grosir & UMKM': '@com.grosirbersama',
        'Smart Bisnis': '@com.smartbisnis',
        'Internetku': '@com.internetku',
        'SSO': '.vmgmt@wms.00000000.000',
        'Rumah Sakit': '.vmgmt@wms.00000000.000'
    },
    'ISP': {
        'Boingo': '@mb.boingo.com',
        'iPass': '@ipass',
        'Nusanet': '@com.nusanet'
    }
};

function transformUsername(rawUser, loginMethod, subMethod) {
    if (!rawUser) return '';
    
    if (rawUser.indexOf('@') !== -1) {
        var parts = rawUser.split('@');
        var trail = parts[1];
        var specialAccounts = ['violet', 'violet.unp', 'violet.unm', 'violet.ugm', 'violet.unpatti', 'violet.uho', 'violet.gamer', 'violet.on', 'giga.wigo', 'mb.boingo.com', 'boingo.com', 'sooltan.id'];
        if (specialAccounts.indexOf(trail) !== -1) {
            return rawUser;
        }
        if (loginMethod === 'Komunitas' && subMethod === 'Kampus') {
            return processCampusUsername(rawUser);
        }
        return rawUser;
    }
    
    if (loginMethod === 'Standar') {
        return rawUser + USERNAME_SUFFIX_MAP['Standar'];
    }
    if (loginMethod === 'Wico') {
        return rawUser + USERNAME_SUFFIX_MAP['Wico'];
    }
    if (loginMethod === 'Komunitas' || loginMethod === 'ISP') {
        if (loginMethod === 'Komunitas' && subMethod === 'Kampus') {
            return '';
        }
        if (USERNAME_SUFFIX_MAP[loginMethod] && USERNAME_SUFFIX_MAP[loginMethod][subMethod]) {
            return rawUser + USERNAME_SUFFIX_MAP[loginMethod][subMethod];
        }
    }
    return rawUser;
}

function formatWmsUsername(rawUser) {
    if (!rawUser) return { raw: '', formatted: '' };
    var parts = rawUser.split('@');
    var baseUser = parts[0];
    var domain = parts.length > 1 ? parts[1] : '';
    var suffix = WMS_USERNAME_SUFFIXES[domain] || '@violet';
    var formattedUser = baseUser + suffix;
    return { raw: rawUser, formatted: formattedUser };
}



function processCampusUsername(rawUser) {
    if (!rawUser) return '';
    var atPos = rawUser.lastIndexOf('@');
    if (atPos === -1) {
        return '';
    }
    var localPart = rawUser.substring(0, atPos);
    var domain = rawUser.substring(atPos + 1);
    var campusConfig = AUTOLOGIN_CONFIG.CAMPUS_CONFIG;
    if (campusConfig && campusConfig[domain] && campusConfig[domain].targetDomain) {
        return localPart + '@' + campusConfig[domain].targetDomain;
    }
    return rawUser;
}

var VENDOR_OUI = AUTOLOGIN_CONFIG.VENDOR_OUI;

var elCardTitle = document.getElementById('al-card-title');
var elScanSection = document.getElementById('al-scan-section');
var elFormContainer = document.getElementById('al-form-container');
var btnAddProfile = document.getElementById('btn-add-profile');

function fnv1aHash(s){var h=2166136261;for(var i=0;i<s.length;i++){h^=s.charCodeAt(i);h=(h*16777619)>>>0;}return h;}
function toHex(n){var h='0123456789ABCDEF';return h[(n>>4)&15]+h[n&15];}
function setLaaUnicast(b){b=Math.floor(b)%256;return Math.floor(b/4)*4+2;}
function generateEntropy(o,t){var h=fnv1aHash(o+':'+Date.now()+':'+Math.random());return toHex((h>>16)&255)+':'+toHex((h>>8)&255)+':'+toHex(h&255);}
function generateVendorMac(t,o){
  if(t==='default'||t===''){return o||'';}
  var ou=VENDOR_OUI[t];
  if(!ou||ou.length===0)return null;
  var oH=ou[Math.floor(Math.random()*ou.length)];
  var o1=setLaaUnicast(parseInt(oH.substring(0,2),16));
  var o2=parseInt(oH.substring(2,4),16);
  var o3=parseInt(oH.substring(4,6),16);
  var e=generateEntropy(o,t);
  return toHex(o1)+':'+toHex(o2)+':'+toHex(o3)+':'+e;
}
function validateMac(m){return /^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$/.test(m);}

function syncUrlClientMac() {
    var macField = document.getElementById('f-mac');
    var urlField = document.getElementById('f-url');
    var cmacField = document.getElementById('f-cmac');
    if (!macField || !macField.value) return;
    var currentMac = macField.value.trim();
    if (urlField && urlField.value) {
        if (urlField.value.match(/([?&])client_mac=/i)) {
            urlField.value = urlField.value.replace(/([?&])client_mac=[^&]*/i, '$1client_mac=' + currentMac);
        }
    }
    if (urlField && urlField.value && cmacField) {
        cmacField.value = currentMac;
    }
}

function syncSessionGridFromUrl() {
    var urlField = document.getElementById('f-url');
    var macField = document.getElementById('f-mac');
    var gwidEl = document.getElementById('f-gwid');
    var wlanEl = document.getElementById('f-wlan');
    var sidEl = document.getElementById('f-sid');
    var ipcEl = document.getElementById('f-ipc');
    var cmacEl = document.getElementById('f-cmac');
    
    if (!urlField) return;
    
    var currentUrl = urlField.value;
    var getParam = function(url, name) {
        var match = url.match(new RegExp('[?&]' + name + '=([^&]*)'));
        return match ? decodeURIComponent(match[1]) : '';
    };
    
    var gwid = getParam(currentUrl, 'gw_id');
    var wlan = getParam(currentUrl, 'wlan');
    var sid = getParam(currentUrl, 'sessionid');
    var ipc = getParam(currentUrl, 'ipc');
    var cmac = getParam(currentUrl, 'client_mac');
    
    if (gwidEl && gwid !== '') gwidEl.value = gwid;
    if (wlanEl && wlan !== '') wlanEl.value = wlan;
    if (sidEl && sid !== '') sidEl.value = sid;
    if (ipcEl && ipc !== '') {
        ipcEl.value = ipc;
    } else if (ipcEl && formState.interfaceIp) {
        ipcEl.value = formState.interfaceIp;
    }
    if (cmacEl && macField && macField.value) {
        cmacEl.value = macField.value;
    }
}

function extractPathFromUrl(url) {
    if (!url) return '';
    try { var u = new URL(url); return u.pathname; } catch(e) {
        var match = url.match(/https?:\/\/[^\/]+(\/[^?#]*)/);
        return match ? match[1] : '';
    }
}

function normalizePath(path) {
    if (!path) return '';
    var normalized = path;
    if (normalized.charAt(0) !== '/') normalized = '/' + normalized;
    if (normalized.charAt(normalized.length - 1) !== '/') normalized = normalized + '/';
    for (var key in portalConfig) {
        var feat = portalConfig[key];
        if (feat.known_paths) {
            for (var i = 0; i < feat.known_paths.length; i++) {
                var knownPath = feat.known_paths[i];
                if (knownPath === normalized || knownPath.replace(/\/$/, '') === normalized.replace(/\/$/, '')) {
                    if (feat.normalize_path && feat.normalize_path !== '') {
                        return feat.normalize_path;
                    }
                    return normalized;
                }
            }
        }
    }
    return '';
}

function replacePathInUrl(url, newPath) {
    if (!url) return url;
    try { var u = new URL(url); u.pathname = newPath; return u.toString(); } catch(e) {
        return url.replace(/(https?:\/\/[^\/]+)\/[^?#]*/i, '$1' + newPath);
    }
}

function handleUrlPathChange() {
    var urlField = document.getElementById('f-url');
    var ptField = document.getElementById('f-pt');
    if (!urlField || !ptField) return;
    var currentPortalType = formState.portalType || '';
    if (!currentPortalType || !portalConfig[currentPortalType]) return;
    var feat = portalConfig[currentPortalType];
    if (!feat.has_login_method && !feat.has_session_grid) return;
    var currentUrl = urlField.value;
    var rawPath = extractPathFromUrl(currentUrl);
    var currentPath = normalizePath(rawPath);
    var previousPath = formState.currentPath || '';
    
    var prevType = null;
    var currType = null;
    for (var key in portalConfig) {
        var known = portalConfig[key].known_paths;
        if (known && known.indexOf(previousPath) !== -1) prevType = key;
        if (known && known.indexOf(currentPath) !== -1) currType = key;
    }
    
    if (currentPath === previousPath) return;
    
    if (prevType && currType && prevType !== currType) {
        var modalTitle = 'Konfirmasi Perubahan ke ' + portalConfig[currType].label;
        var modalMsg = 'URL terdeteksi berubah dari ' + portalConfig[prevType].label + ' ke ' + portalConfig[currType].label + '. Ubah struktur form secara otomatis?';
        if (document.getElementById('al-mac-modal')) document.getElementById('al-mac-modal').remove();
        var m = document.createElement('div'); m.id = 'al-mac-modal'; m.className = 'al-modal-overlay';
        m.innerHTML = '<div class="al-modal-box"><h3 class="al-modal-title">' + modalTitle + '</h3><p class="al-modal-msg">' + modalMsg + '</p><div class="al-modal-actions"><button id="al-modal-cancel" class="al-btn al-btn-secondary">TIDAK</button><button id="al-modal-confirm" class="al-btn al-btn-primary">YA, LANJUTKAN</button></div></div>';
        (document.getElementById('autologin-root') || document.body).appendChild(m);
        document.getElementById('al-modal-cancel').onclick = function() { m.style.display = 'none'; };
        document.getElementById('al-modal-confirm').onclick = function() {
            m.style.display = 'none';
            applyPathTransformation(currentUrl, currentPath, true);
        };
        m.style.display = 'flex';
    } else if (currType && currType === formState.portalType) {
        applyPathTransformation(currentUrl, currentPath, false);
    }
}

function applyPathTransformation(url, newPath, toWifiId) {
    var urlField = document.getElementById('f-url');
    var ptField = document.getElementById('f-pt');
    var loginMethodSelect = document.getElementById('sel-login-method');
    if (!urlField || !ptField) return;
    var normalizedPath = normalizePath(newPath);
    urlField.value = replacePathInUrl(url, normalizedPath);
    applyPortalTypeToUI(normalizedPath);
    formState.currentPath = normalizedPath;
}

function applyPortalTypeToUI(normalizedPath) {
    var ptField = document.getElementById('f-pt');
    var loginMethodSelect = document.getElementById('sel-login-method');
    if (!ptField) return;
    
    var foundType = null;
    for (var key in portalConfig) {
        if (portalConfig[key].known_paths && portalConfig[key].known_paths.indexOf(normalizedPath) !== -1) {
            foundType = key;
            break;
        }
    }
    if (foundType) {
        var feat = portalConfig[foundType];
        ptField.value = feat.label || foundType;
        formState.portalType = foundType;
        if (loginMethodSelect) {
            if (feat.login_method_disabled) {
                loginMethodSelect.value = '';
            }
            loginMethodSelect.disabled = feat.login_method_disabled || false;
            if (typeof updateSecondaryDropdown === 'function') updateSecondaryDropdown();
        }
    } else {
        ptField.value = normalizedPath;
        if (loginMethodSelect) loginMethodSelect.disabled = false;
    }
    if (typeof validateSaveForm === 'function') {
        setTimeout(validateSaveForm, 50);
    }
}

function updateButtonStates(selDevice, inpMac, btnRandom, btnApply, btnDetectUrl) {
  if (!selDevice || !inpMac || !btnRandom || !btnApply) return;
  var selectedVendor = selDevice.value;
  var spoof = formState.spoofSupported;
  var isApplied = formState.applied;
  if (isApplied) {
    btnRandom.disabled = true;
    btnApply.disabled = false;
    return;
  }
  if (selectedVendor === '' || selectedVendor === 'default') {
    btnRandom.disabled = true;
  } else {
    btnRandom.disabled = false;
  }
  if (!spoof || selectedVendor === '' || selectedVendor === 'default') {
    btnApply.disabled = true;
    btnApply.textContent = 'APPLY MAC';
    btnApply.classList.remove('al-btn-revert');
  } else {
    btnApply.disabled = false;
    btnApply.textContent = 'APPLY MAC';
    btnApply.classList.remove('al-btn-revert');
  }
  if (btnDetectUrl) {
    if (selectedVendor === '') {
      btnDetectUrl.disabled = true;
    } else {
      btnDetectUrl.disabled = false;
    }
  }
}

function applyInitialFormState(selDevice, inpMac, btnRandom, btnApply) {
  var ptClean = (formState.portalType || '');
  var feat = portalConfig[ptClean];
  var isWmsOrWifiId = feat && (feat.has_login_method || feat.has_session_grid);
  var spoof = formState.spoofSupported;
  var selectedVendor = selDevice.value;
  if (formState.applied) return;
  selDevice.disabled = false;
  var btnDetectUrl = document.getElementById('btn-detect-url');
  updateButtonStates(selDevice, inpMac, btnRandom, btnApply, btnDetectUrl);
  updateMacFromDevice();
}

function execMac(action){
  var btn=document.getElementById('btn-mac-apply');
  var originalText = btn.textContent;
  btn.textContent='PROCESSING...'; btn.disabled=true;
  var url='/cgi-bin/luci/admin/autologin/'+(action==='apply'?'apply_mac':'revert_mac');
  var params = new URLSearchParams();
  params.append('logical', formState.logical);
  params.append('device', formState.device);
  if(action === 'apply') {
      var vendor = document.getElementById('f-device').value;
      params.append('device_type', vendor);
      params.append('target_mac', document.getElementById('f-mac').value);
  } else {
      params.append('original_mac', formState.originalMac);
  }
  var xhr=new XMLHttpRequest();
  xhr.open('POST', url, true);
  xhr.setRequestHeader('Content-Type', 'application/x-www-form-urlencoded');
  xhr.timeout = 15000;
  xhr.onload=function(){
    try{
      var r=JSON.parse(xhr.responseText);
      if(r.status==='success'){
        formState.applied=(action==='apply');
        var targetIfaceStr = formState.logical + '/' + formState.device;
        var pickBtn = document.querySelector('.al-pick-btn[data-iface="' + targetIfaceStr + '"]');
        if (pickBtn) {
            var newMac = (action === 'apply') ? document.getElementById('f-mac').value : formState.originalMac;
            var newVendor = (action === 'apply') ? document.getElementById('f-device').value : '';
            var isModified = (action === 'apply') ? 'true' : 'false';
            pickBtn.setAttribute('data-mac', newMac);
            pickBtn.setAttribute('data-mac-modified', isModified);
            pickBtn.setAttribute('data-mac-vendor', newVendor);
            var row = pickBtn.closest('tr');
            if (row) {
                var macCells = row.querySelectorAll('td');
                if (macCells[4]) macCells[4].textContent = newMac;
            }
        }
        syncUi();
        alert(r.message || 'Operasi MAC berhasil.');
      }else{
        alert('Gagal: '+(r.message||'Unknown error'));
        btn.textContent=action==='apply'?'APPLY MAC':'REVERT';
        btn.disabled=false;
      }
    }catch(e){console.error('[autologin] execMac parse error:', e); alert('Server response error: HTTP '+xhr.status);btn.textContent=originalText;btn.disabled=false;}
  };
  xhr.onerror=function(){console.error('[autologin] execMac network error');alert('Network error during MAC operation.');btn.textContent=originalText;btn.disabled=false;};
  xhr.send(params.toString());
}

function syncUi(){
  var s=document.getElementById('f-device');
  var m=document.getElementById('f-mac');
  var r=document.getElementById('btn-mac-random');
  var a=document.getElementById('btn-mac-apply');
  if(!s||!m||!r||!a) return;
  if(formState.applied){
    s.disabled = false;
    s.classList.add('al-state-applied');
    s.onfocus = function(){ this.blur(); };
    r.disabled = true;
    a.textContent = 'REVERT';
    a.classList.add('al-btn-revert');
    a.disabled = false;
  } else {
    s.value = '';
    m.value = '';
    formState.deviceVendor = '';
    s.onfocus = null;
    s.classList.remove('al-state-applied');
    s.disabled = false;
    applyInitialFormState(s, m, r, a);
  }
}

function buildModal(){
  if(document.getElementById('al-mac-modal')) document.getElementById('al-mac-modal').remove();
  var m=document.createElement('div');m.id='al-mac-modal';m.className='al-modal-overlay';
  m.innerHTML='<div class="al-modal-box"><h3 class="al-modal-title">Konfirmasi Ganti MAC</h3><p class="al-modal-msg">Tindakan ini akan mengganti MAC address secara permanen dan memutus koneksi jaringan sementara (~3-8 detik). Lanjutkan?</p><div class="al-modal-actions"><button id="al-modal-cancel" class="al-btn al-btn-secondary">TIDAK</button><button id="al-modal-confirm" class="al-btn al-btn-primary">YA, LANJUTKAN</button></div></div>';
  (document.getElementById('autologin-root') || document.body).appendChild(m);
  document.getElementById('al-modal-cancel').onclick=function(){m.style.display='none';};
  document.getElementById('al-modal-confirm').onclick=function(){m.style.display='none';execMac('apply');};
}

function setButtonStateByUci(btnApply, isMacModified) {
  if (!btnApply) return;
  if (isMacModified) {
    btnApply.textContent = 'REVERT';
    btnApply.classList.add('al-btn-revert');
    btnApply.disabled = false;
  } else {
    btnApply.textContent = 'APPLY MAC';
    btnApply.classList.remove('al-btn-revert');
  }
}

btnAddProfile.addEventListener('click', function(){
    var btn = this;
    var container = document.getElementById('scan-result-container');
    container.innerHTML = '';
    btn.disabled = true;
    btn.innerHTML = '<svg class="al-spinner"><circle cx="8" cy="8" r="6" fill="none" stroke="currentColor" stroke-width="2" stroke-dasharray="12" stroke-linecap="round"><animateTransform attributeName="transform" type="rotate" from="0 8 8" to="360 8 8" dur="0.8s" repeatCount="indefinite"/></circle></svg><span>SCANNING...</span>';
    var oldBadge = document.getElementById('mac-spoof-indicator');
    if (oldBadge) oldBadge.remove();
    var xhrTime = new XMLHttpRequest();
    xhrTime.open('GET', '/cgi-bin/luci/admin/autologin/sync_time?_=' + Date.now(), true);
    xhrTime.timeout = 3000;
    xhrTime.send();
    var macData = null;
    var pendingRequests = 2;
    function checkAllDone() {
        pendingRequests--;
        if (pendingRequests === 0) renderBadge();
    }

    var xhrMac = new XMLHttpRequest();
    xhrMac.open('GET', '/cgi-bin/luci/admin/autologin/mac_spoof_check?token=' + (_csrfToken || ''), true);
    xhrMac.timeout = 8000;
    xhrMac.onload = function() {
        if (xhrMac.status === 200) {
            try { macData = JSON.parse(xhrMac.responseText); } catch(e) {}
            formState.spoofSupported = (macData && (macData.supported === true || macData.supported === 'true'));
        }
        checkAllDone();
    };
    xhrMac.onerror = function() { console.error('[autologin] MAC spoof check network error'); checkAllDone(); };
    xhrMac.send();
    var renderBadge = function() {
        var badge = document.createElement('span');
        badge.id = 'mac-spoof-indicator';
        if (macData && (macData.supported === true || macData.supported === 'true')) {
            badge.className = 'al-badge al-badge-success';
            badge.textContent = 'SUPPORT MAC SPOOF';
        } else {
            badge.className = 'al-badge al-badge-error';
            badge.textContent = 'TIDAK SUPPORT';
        }
        btn.parentNode.insertBefore(badge, btn.nextSibling);
    };
    var restoreBtn = function(disabled, hasPortals) {
    btn.disabled = disabled;
    if (hasPortals === true) {
        btn.innerHTML = 'DAFTAR INTERFACE';
    } else if (hasPortals === false) {
        btn.innerHTML = 'NO INTERFACE';
    } else {
        btn.innerHTML = 'CEK INTERFACE';
    }
	};    
    var xhrScan = new XMLHttpRequest();
    xhrScan.open('GET', '/cgi-bin/luci/admin/autologin/scan?token=' + (_csrfToken || ''), true);
    xhrScan.timeout = 60000;
    xhrScan.onload = function() {

        if (xhrScan.status === 200) {
            try {
                var data = JSON.parse(xhrScan.responseText);
				if (data.portal_config) { portalConfig = data.portal_config; }
                if (data.interfaces && data.interfaces.length > 0) {
                    var html = '<table class="al-table"><thead><tr><th>Portal</th><th>Interface/Device</th><th>IP</th><th>Gateway</th><th>MAC</th><th>URL</th><th>Status</th><th>Aksi</th></tr></thead><tbody>';
                    data.interfaces.forEach(function(f){
                        var pt = f.portal_label || f.portal_type;
                        var iface = (f.interface || '?') + '/' + (f.device || '?');
                        var macMod = (f.mac_modified===true?'true':'false');
                        var macVendor = f.mac_vendor || '';
                        var isAlreadySaved = savedProfileInterfaces.has(iface);
                        var dataAttr = 'data-type="'+(f.portal_type||'')+'" data-iface="'+((f.interface||'')+'/'+(f.device||''))+'" data-pt="'+pt+'" data-mac="'+(f.mac||'')+'" data-url="'+(f.portal_url_display || f.portal_url)+'" data-gwid="'+(f.gw_id||'')+'" data-cmac="'+(f.client_mac||'')+'" data-wlan="'+(f.wlan||'')+'" data-sid="'+(f.sessionid||'')+'" data-ipc="'+(f.ipc||'')+'" data-ip="'+(f.ip||'')+'" data-mac-modified="'+macMod+'" data-mac-vendor="'+macVendor+'"';
                        var actionButton = '';
                        if (isAlreadySaved) {
                            actionButton = '<button class="al-btn al-btn-secondary" disabled title="Profil untuk interface ini sudah tersimpan">SUDAH TERSIMPAN</button>';
                        } else {
                            actionButton = '<button class="al-btn al-btn-primary al-pick-btn" '+dataAttr+'>PILIH INTERFACE</button>';
                        }
                        html += '<tr>' +
                            '<td>' + pt + '</td>' +
                            '<td class="al-cell-iface">' + iface + '</td>' +
                            '<td>' + (f.ipc || f.ip || '-') + '</td>' +
                            '<td>' + f.gateway + '</td>' +
                            '<td>' + f.mac + '</td>' +
                            '<td class="al-cell-url">' + (f.portal_url_display || f.portal_url) + '</td>' +
                            '<td><span class="al-text-portal-login">' + (f.status || 'Portal Login') + '</span></td>' +
                            '<td>' + actionButton + '</td>' +
                        '</tr>';
                    });
                    html += '</tbody></table>';
                    container.innerHTML = html;
                    restoreBtn(false, true);
                } else {
                    container.innerHTML = '<p class="al-notification">Tidak ada interface dengan captive portal terdeteksi.</p>';
                    restoreBtn(false, false);
                }

            } catch(e) {
                container.innerHTML = '<p class="al-notification al-notification-error">Error parsing response.</p>';
                btn.disabled = false;
				btn.innerHTML = 'CEK INTERFACE';
            }
        } else {
            container.innerHTML = '<p class="al-notification al-notification-error">Scan failed: HTTP ' + xhrScan.status + '</p>';
            btn.disabled = false;
			btn.innerHTML = 'CEK INTERFACE';
        }
        checkAllDone();
    };
    xhrScan.onerror = function() {
        console.error('[autologin] Scan network error');
        container.innerHTML = '<p class="al-notification al-notification-error">Network error during scan.</p>';
        btn.disabled = false;
		btn.innerHTML = 'CEK INTERFACE';
        checkAllDone();
    };
    xhrScan.send();
});

document.getElementById('scan-result-container').addEventListener('click', function(e){
    if(e.target && e.target.classList.contains('al-pick-btn')){
        var d = e.target.dataset;
        switchToForm(d);
    }
});

function switchToForm(data, isEdit){
    elScanSection.style.display = 'none';
    elFormContainer.style.display = 'block';
    
    var profSec = document.getElementById('al-profiles-section');
    if (profSec) {
        profSec.style.display = 'none';
    }
    var ifaceParts = (data.iface || '').split('/');
    formState.logical = ifaceParts[0] || '';
    formState.device = ifaceParts[1] || '';
    formState.originalMac = data.mac || '';
    formState.portalType = data.type || data.pt || '';
    formState.applied = (data.macModified === 'true' || data.macModified === true);
    formState.deviceVendor = data.macVendor || formState.deviceVendor || '';
    formState.interfaceIp = data.ipc || data.ip || '';
    formState.originalPath = extractPathFromUrl(data.url || '') || '';
    formState.currentPath = formState.originalPath;
    if (!isEdit) {
        data.url = '';
        data.gw_id = '';
        data.client_mac = '';
        data.wlan = '';
        data.sessionid = '';
        data.ipc = '';
    }
    elFormContainer.innerHTML = generateFormHTML(data.type, data, isEdit);
    attachFormEvents();
    setTimeout(function() { validateSaveForm(); checkInitialLoginState(); }, 150);
}

function switchToScan(){
    elFormContainer.style.display = 'none';
    elFormContainer.innerHTML = '';
    elScanSection.style.display = 'block';
    isEditingProfile = false;
    currentEditProfileId = null;
    var profSec = document.getElementById('al-profiles-section');
    if (profSec) {
        profSec.style.display = 'block';
    }
}

function generateFormHTML(type, d, isEdit){
    var isWmsOrWifiId = (portalConfig[type] && (portalConfig[type].has_login_method || portalConfig[type].has_session_grid));
    var html = '';
    if (isEdit) {
        html += '<h3 id="edit-config-heading" class="al-card-title al-form-title">Edit Konfigurasi Interface</h3>';
    } else {
        html += '<h3 class="al-card-title al-form-title">Konfigurasi Interface</h3>';
    }
    html += '<div class="al-form-grid">';
    html += '<div class="al-form-group"><label>INTERFACE</label><input type="text" class="al-input" id="f-iface" value="'+(d.iface||'')+'" readonly></div>';
    html += '<div class="al-form-group"><label>PORTAL TYPE</label><input type="text" class="al-input" id="f-pt" value="'+(d.pt||'')+'" readonly></div>';
    if(isWmsOrWifiId){
        var disabledAttr = (portalConfig[type] && portalConfig[type].login_method_disabled) ? 'disabled' : '';
        html += '<div class="al-form-group al-col-span-2" id="grp-login-method"><label>LOGIN METHOD</label>';
        html += '<select class="al-select" id="sel-login-method" '+disabledAttr+'>';
        var methods = AUTOLOGIN_CONFIG.LOGIN_METHODS;
        for (var i = 0; i < methods.length; i++) {
            var lmSelected = (isEdit && methods[i].value === d.login_method) ? 'selected' : '';
            html += '<option value="' + methods[i].value + '" ' + lmSelected + '>' + methods[i].label + '</option>';
        }
        html += '</select></div>';
        var dynamicDisplayStyle = 'none';
        var dynamicLabelVisibility = 'hidden';
        var dynamicLabelText = '&nbsp;';
        var subSelectHtml = '';
        if (isEdit && d.login_method && (d.login_method === 'Komunitas' || d.login_method === 'ISP')) {
            var selectedMainMethod = null;
            for(var k=0; k<methods.length; k++) {
                if(methods[k].value === d.login_method && methods[k].sub) {
                    selectedMainMethod = methods[k];
                    break;
                }
            }
            if (selectedMainMethod) {
                dynamicDisplayStyle = 'flex';
                dynamicLabelVisibility = 'visible';
                dynamicLabelText = selectedMainMethod.label;
                subSelectHtml = '<select class="al-select" id="f-' + d.login_method.toLowerCase() + '">';
                for(var j=0; j<selectedMainMethod.sub.length; j++) {
                    var subValue = selectedMainMethod.sub[j].value || '';
                    var subLabel = selectedMainMethod.sub[j].label || '';
                    var subSel = (subValue === d.sub_method) ? 'selected' : '';
                    subSelectHtml += '<option value="' + subValue + '" ' + subSel + '>' + subLabel + '</option>';
                }
                subSelectHtml += '</select>';
            }
        }
        html += '<div class="al-form-group" id="grp-dynamic-side" style="display:'+dynamicDisplayStyle+'">';
        html += '<label id="lbl-dynamic" style="visibility:'+dynamicLabelVisibility+'">'+dynamicLabelText+'</label>';
        html += '<div id="sel-dynamic-container" class="al-select-wrapper">' + subSelectHtml + '</div>';
        html += '</div>';
    }
    html += '<div class="al-form-group"><label>USERNAME</label><input type="text" class="al-input" id="f-user" value="'+(d.username||'')+'" placeholder="Masukkan Username"></div>';
    html += '<div class="al-form-group"><label>PASSWORD</label><input type="password" class="al-input" id="f-pass" value="'+(d.password||'')+'" placeholder="Masukkan Password"></div>';
    html += '<div class="al-form-group"><label>PERANGKAT</label>';
    html += '<select class="al-select" id="f-device">';
    var currentVendor = (d.macVendor || '').toLowerCase();
    html += '<option value="" ' + (currentVendor === '' ? 'selected' : '') + '>Pilih Perangkat</option>';
    html += '<option value="default" ' + (currentVendor === 'default' ? 'selected' : '') + '>Default</option>';
    html += '<option value="android" ' + (currentVendor === 'android' ? 'selected' : '') + '>Android</option>';
    html += '<option value="linux" ' + (currentVendor === 'linux' ? 'selected' : '') + '>Linux</option>';
    html += '<option value="macos" ' + (currentVendor === 'macos' ? 'selected' : '') + '>MacOS</option>';
    html += '<option value="windows" ' + (currentVendor === 'windows' ? 'selected' : '') + '>Windows</option>';
    html += '</select></div>';
    html += '<div class="al-form-group"><label>MAC ADDRESS</label><div class="al-mac-row"><input type="text" class="al-input" id="f-mac" value="'+(d.mac||'')+'" placeholder="XX:XX:XX:XX:XX:XX" readonly data-original-mac="'+(d.mac||'')+'"><button type="button" class="al-btn al-btn-mac-random" id="btn-mac-random" disabled>MAC ACAK</button><button type="button" class="al-btn al-btn-primary" id="btn-mac-apply">APPLY MAC</button></div></div>';
    html += '<div class="al-form-group al-col-span-2"><label>URL LOGIN</label><div class="al-url-row"><input type="text" class="al-input" id="f-url" value="'+(d.url||'')+'" placeholder="Masukkan URL Login"><button type="button" class="al-btn al-btn-primary" id="btn-detect-url">DETECT URL</button></div></div>';
    if(isWmsOrWifiId){
        html += '<div class="al-col-span-2 al-readonly-grid">';
        html += '<div class="al-form-group"><label>GW_ID</label><input type="text" class="al-input" id="f-gwid" value="'+(d.gw_id||'')+'" readonly></div>';
        html += '<div class="al-form-group"><label>CLIENT_MAC</label><input type="text" class="al-input" id="f-cmac" value="'+(d.client_mac || '')+'" readonly></div>';
        html += '<div class="al-form-group"><label>WLAN</label><input type="text" class="al-input" id="f-wlan" value="'+(d.wlan||'')+'" readonly></div>';
        html += '<div class="al-form-group"><label>SESSIONID</label><input type="text" class="al-input" id="f-sid" value="'+(d.sessionid||'')+'" readonly></div>';
        html += '<div class="al-form-group"><label>IPC</label><input type="text" class="al-input" id="f-ipc" value="'+(d.ipc||'')+'" readonly></div>';
        html += '</div>';
    }
    var alEnabled = d.auto_login_enabled !== undefined ? d.auto_login_enabled : true;
    var arEnabled = d.auto_reconnect_enabled !== undefined ? d.auto_reconnect_enabled : true;
    var hInterval = d.health_check_interval || 30;
    var stabDelay = d.stabilization_delay || 15;
    var failCd = d.failure_cooldown || 5;
    var mRetry = d.max_retry || 5;
    var abEnabled = d.anti_blocking_enabled !== undefined ? d.anti_blocking_enabled : true;
    var tgEnabled = d.telegram_enabled || false;
    var tgToken = d.telegram_token || '';
    var tgChat = d.telegram_chat_id || '';
    html += '<div class="al-col-span-2 al-advanced-section">';
    html += '<h4 class="al-advanced-title">ADVANCED SETTINGS</h4>';
    var toggleWithText = function(id, label, isChecked, textId) {
        var chk = isChecked ? 'checked' : '';
        var txt = isChecked ? 'Aktif' : 'Tidak Aktif';
        var txtClass = isChecked ? 'active' : 'inactive';
        return '<div class="al-toggle-item">' +
               '<label class="al-toggle-label-text">' + label + '</label>' +
               '<div class="al-toggle-switch-wrapper">' +
               '<label class="al-toggle-switch"><input type="checkbox" id="' + id + '" ' + chk + ' onchange="var t=document.getElementById(\'' + textId + '\'); t.textContent=this.checked?\'Aktif\':\'Tidak Aktif\'; t.className=\'al-toggle-label \' + (this.checked?\'active\':\'inactive\');"><span class="al-toggle-slider"></span></label>' +
               '<span id="' + textId + '" class="al-toggle-label ' + txtClass + ' al-toggle-text-min">' + txt + '</span>' +
               '</div></div>';
    };
    html += '<div class="al-toggle-group">';
    html += toggleWithText('f-auto-login', 'AUTO-LOGIN', alEnabled, 'txt-al');
    html += toggleWithText('f-auto-reconnect', 'AUTO-RECONNECT', arEnabled, 'txt-ar');
    html += toggleWithText('f-anti-blocking', 'ANTI BLOKIR', abEnabled, 'txt-ab');
    html += '</div>';
    html += '<div class="al-advanced-row">';
    html += '<div class="al-advanced-item">';
    html += '<label class="al-advanced-label">HEALTH INTERVAL</label>';
    html += '<select class="al-select" id="f-health-interval"><option value="5" ' + (hInterval==5?'selected':'') + '>5 detik</option><option value="10" ' + (hInterval==10?'selected':'') + '>10 detik</option><option value="15" ' + (hInterval==15?'selected':'') + '>15 detik</option><option value="30" ' + (hInterval==30?'selected':'') + '>30 detik</option><option value="60" ' + (hInterval==60?'selected':'') + '>60 detik</option></select>';
    html += '</div>';
    html += '<div class="al-advanced-item">';
    html += '<label class="al-advanced-label" title="Waktu tunggu setelah Anti-Blokir berhasil, agar routing & DHCP stabil sebelum login ulang">DELAY <span class="al-label-sub">(detik)</span></label>';
    html += '<select class="al-select" id="f-stab-delay"><option value="10" ' + (stabDelay==10?'selected':'') + '>10 detik</option><option value="15" ' + (stabDelay==15?'selected':'') + '>15 detik</option><option value="30" ' + (stabDelay==30?'selected':'') + '>30 detik</option><option value="60" ' + (stabDelay==60?'selected':'') + '>60 detik</option></select>';
    html += '</div>';
    html += '<div class="al-advanced-item al-advanced-item-cooldown">';
    html += '<label class="al-advanced-label" title="Waktu tunggu sistem jika Anti-Blokir gagal total atau Max Retry tercapai, untuk mencegah pembebanan CPU">COOLDOWN ANTI BLOKIR <span class="al-label-sub">(menit)</span></label>';
    html += '<select class="al-select" id="f-fail-cd"><option value="3" ' + (failCd==3?'selected':'') + '>3 menit</option><option value="5" ' + (failCd==5?'selected':'') + '>5 menit</option><option value="10" ' + (failCd==10?'selected':'') + '>10 menit</option><option value="20" ' + (failCd==20?'selected':'') + '>20 menit</option><option value="30" ' + (failCd==30?'selected':'') + '>30 menit</option></select>';
    html += '</div>';
    html += '<div class="al-advanced-item al-advanced-item-retry">';
    html += '<label class="al-advanced-label">MAX RETRY</label>';
    html += '<input type="number" class="al-input" id="f-max-retry" value="' + mRetry + '" min="1" max="10">';
    html += '</div>';
    html += '</div>';
    var tgDisabled = tgEnabled ? '' : 'disabled';
    html += '<div class="al-telegram-section">';
    html += '<div class="al-telegram-item">';
    html += '<label class="al-advanced-label">NOTIFIKASI TELEGRAM</label>';
    html += '<div class="al-telegram-wrapper">';
    html += '<input type="text" class="al-input al-input-telegram-token" id="f-telegram-token" value="' + tgToken + '" placeholder="Bot Token" ' + tgDisabled + '>';
    html += '<input type="text" class="al-input al-input-telegram-chat" id="f-telegram-chat" value="' + tgChat + '" placeholder="Chat ID" ' + tgDisabled + '>';
    html += '<div class="al-telegram-toggle-wrapper">';
    html += '<label class="al-toggle-switch"><input type="checkbox" id="f-telegram" ' + (tgEnabled ? 'checked' : '') + ' onchange="var d1=document.getElementById(\'f-telegram-token\'); var d2=document.getElementById(\'f-telegram-chat\'); var t=document.getElementById(\'txt-tg\'); if(this.checked){d1.disabled=false; d2.disabled=false; t.textContent=\'Aktif\'; t.className=\'al-toggle-label active\';} else {d1.disabled=true; d2.disabled=true; t.textContent=\'Tidak Aktif\'; t.className=\'al-toggle-label inactive\';}"><span class="al-toggle-slider"></span></label>';
    html += '<span id="txt-tg" class="al-toggle-label ' + (tgEnabled ? 'active' : 'inactive') + ' al-toggle-label-tg">' + (tgEnabled ? 'Aktif' : 'Tidak Aktif') + '</span>';
    html += '</div></div></div>';
    html += '</div>';
    html += '</div>';
    html += '<div class="al-col-span-2 hidden" id="al-login-notification"></div>';
    html += '<div class="al-form-actions al-col-span-2 al-form-actions-wrapper">';
    html += '<button type="button" class="al-btn al-btn-secondary al-btn-back" id="btn-back">KEMBALI</button>';
    var btnSaveText = isEdit ? 'UPDATE' : 'SIMPAN';
    var loginDisabled = isEdit ? 'disabled' : '';
    var loginClass = isEdit ? 'al-btn-login-disabled' : '';
    html += '<div class="al-btn-group">';
    html += '<button type="button" class="al-btn al-btn-primary ' + loginClass + '" id="btn-login" ' + loginDisabled + '>LOGIN</button>';
    html += '<button type="button" class="al-btn al-btn-primary" id="btn-save">' + btnSaveText + '</button>';
    html += '</div>';
    html += '</div>';
    html += '</div>';
    return html;
}

function updateSecondaryDropdown() {
    var selM = document.getElementById('sel-login-method');
    var grpMethod = document.getElementById('grp-login-method');
    var grpSide = document.getElementById('grp-dynamic-side');
    var lblDynamic = document.getElementById('lbl-dynamic');
    var selContainer = document.getElementById('sel-dynamic-container');
    if (!selM || !grpMethod || !grpSide) return;
    var v = selM.value;
    var currentSubSelect = selContainer.querySelector('select');
    var preservedSubValue = currentSubSelect ? currentSubSelect.value : '';
    selContainer.innerHTML = '';
    var methods = AUTOLOGIN_CONFIG.LOGIN_METHODS;
    var selected = null;
    for (var i = 0; i < methods.length; i++) {
        if (methods[i].value === v && methods[i].sub) {
            selected = methods[i];
            break;
        }
    }
    if (selected) {
        grpMethod.classList.remove('al-col-span-2');
        grpSide.style.display = 'flex';
        lblDynamic.textContent = selected.label;
        lblDynamic.style.visibility = 'visible';
        var opts = '';
        for (var j = 0; j < selected.sub.length; j++) {
            var subValue = selected.sub[j].value || '';
            var isSelected = (subValue === preservedSubValue && preservedSubValue !== '') ? 'selected' : '';
            opts += '<option value="' + subValue + '" ' + isSelected + '>' + selected.sub[j].label + '</option>';
        }
        selContainer.innerHTML = '<select class="al-select" id="f-' + selected.value.toLowerCase() + '">' + opts + '</select>';
    } else {
        grpMethod.classList.add('al-col-span-2');
        grpSide.style.display = 'none';
    }
    validateSaveForm();
    setTimeout(function() {
        ['f-komunitas', 'f-isp'].forEach(function(id) {
            var dynEl = document.getElementById(id);
            if (dynEl) {
                dynEl.addEventListener('change', validateSaveForm);
            }
        });
    }, 50);
}

function updateMacFromDevice(forceUpdate) {
    var selDevice = document.getElementById('f-device');
    var inpMac = document.getElementById('f-mac');
    var btnRandom = document.getElementById('btn-mac-random');
    if(!selDevice || !inpMac) return;
    if(formState.applied) return; 
    
    var selectedVendor = selDevice.value;
    var originalMac = formState.originalMac || '';
    
    if(isEditingProfile && !forceUpdate && formState.originalMac) {
        inpMac.value = formState.originalMac.toUpperCase();
    } else if(selectedVendor === ''){
        inpMac.value = '';
        var urlField = document.getElementById('f-url');
        if(urlField) urlField.value = '';
        ['f-gwid', 'f-cmac', 'f-wlan', 'f-sid', 'f-ipc'].forEach(function(id){
            var el = document.getElementById(id);
            if(el) el.value = '';
        });
    } else {
        var newMac = generateVendorMac(selectedVendor, originalMac);
        if(newMac && validateMac(newMac)){
            inpMac.value = newMac.toUpperCase();
        } else {
            inpMac.value = originalMac || '';
        }
    }
    syncUrlClientMac();
    var btnApply = document.getElementById('btn-mac-apply');
    var btnDetectUrl = document.getElementById('btn-detect-url');
    updateButtonStates(selDevice, inpMac, btnRandom, btnApply, btnDetectUrl);
}

function attachFormEvents(){
    var btnBack = document.getElementById('btn-back');
    if (btnBack) {
        btnBack.addEventListener('click', function() {
            if (isEditingProfile) {
                elFormContainer.style.display = 'none';
                elFormContainer.innerHTML = '';
                elScanSection.style.display = 'block';
                elCardTitle.textContent = 'Konfigurasi Interface';
                isEditingProfile = false;
                currentEditProfileId = null;
                var profSec = document.getElementById('al-profiles-section');
                if (profSec) {
                    profSec.style.display = 'block';
                }
            } else {
                switchToScan();
            }
        });
    }
    var btnLogin = document.getElementById('btn-login');
    if (btnLogin) {
        btnLogin.onclick = performLogin;
        btnLogin.disabled = true;
    }
    var btnSave = document.getElementById('btn-save');
    if (btnSave) {
        btnSave.addEventListener('click', performSave);
        btnSave.disabled = true;
    }
    attachSaveValidationListeners();
    var btnDetectUrl = document.getElementById('btn-detect-url');
    if (btnDetectUrl) btnDetectUrl.onclick = function(){
        if(btnDetectUrl.disabled) return;
        var urlField = document.getElementById('f-url');
        if (urlField && urlField.value && urlField.value.trim() !== '') {
            if (!confirm('URL sudah terisi. Apakah Anda yakin ingin mendeteksi ulang? URL saat ini akan ditimpa.')) {
                return;
            }
        }
        var originalText = btnDetectUrl.textContent;
        btnDetectUrl.textContent = 'RESTARTING...';
        btnDetectUrl.disabled = true;       
        var targetIface = formState.logical || '';
        var targetDev = formState.device || '';
        var restartXhr = new XMLHttpRequest();
        restartXhr.open('GET', '/cgi-bin/luci/admin/autologin/restart_interface?logical=' + encodeURIComponent(targetIface) + '&device=' + encodeURIComponent(targetDev) + '&_=' + Date.now(), true);
        restartXhr.timeout = 35000;
        restartXhr.onload = function() {
            if (restartXhr.status === 200) {
                try {
                    var restartResult = JSON.parse(restartXhr.responseText);
                    if (restartResult.status === 'success' || restartResult.status === 'warning') {
                        btnDetectUrl.textContent = 'DETECTING...';
                        var xhr = new XMLHttpRequest();
                        xhr.open('GET', '/cgi-bin/luci/admin/autologin/scan?token=' + (_csrfToken || '') + '&device=' + encodeURIComponent(targetDev), true);
                        xhr.timeout = 15000;
                        xhr.onload = function(){
                            if(xhr.status === 200){
                                try {
                                    var data = JSON.parse(xhr.responseText);
									if (data.portal_config) {
                                        portalConfig = data.portal_config;
									}
                                    var detectedUrl = '';
                                    if(data.interfaces && data.interfaces.length > 0){
                                        for(var i=0; i<data.interfaces.length; i++){
                                            var iface = data.interfaces[i];
                                            if(iface.interface === targetIface && iface.device === targetDev){
                                                detectedUrl = iface.portal_url || '';
                                                break;
                                            }
                                        }
                                    }
                                    var urlField = document.getElementById('f-url');
                                    if(urlField && detectedUrl){
                                        var macField = document.getElementById('f-mac');
                                        var displayUrl = iface.portal_url_display || detectedUrl;
                                        if(macField && macField.value){
                                            var newMac = macField.value.trim().toUpperCase();
                                            displayUrl = displayUrl.replace(/([?&])client_mac=[^&]*/i, '$1client_mac=' + newMac);
                                        }
                                        if (portalConfig[formState.portalType] && portalConfig[formState.portalType].has_session_grid && iface && iface.ip) {
                                            formState.interfaceIp = iface.ip;
                                        }
                                        urlField.value = displayUrl;
                                        var currentPortalType = formState.portalType || '';
                                        var feat = portalConfig[currentPortalType];
                                        var isSessionGrid = feat && feat.has_session_grid;
                                        if (isSessionGrid) {
                                            var newPath = extractPathFromUrl(displayUrl) || '';
                                            var normalizedPath = normalizePath(newPath);
                                            formState.currentPath = normalizedPath;
                                            applyPortalTypeToUI(normalizedPath);
                                        if (urlField && urlField.value) {
                                            syncSessionGridFromUrl();
                                        }
                                            validateSaveForm();
                                        }
                                    }
                                    setTimeout(validateSaveForm, 100);
                                } catch(e){
                                    showNotification('Error parsing response.', 'error');
                                }
                            } else {
                                showNotification('Scan failed: HTTP ' + xhr.status, 'error');
                            }
                            btnDetectUrl.textContent = originalText;
                            btnDetectUrl.disabled = false;
                            setTimeout(validateSaveForm, 200);
                        };
                        xhr.onerror = function(){
                            btnDetectUrl.textContent = originalText;
                            btnDetectUrl.disabled = false;
                            showNotification('Network error during scan.', 'error');
                        };
                        xhr.send();
                        
                    } else {
                        showNotification('Gagal restart interface: ' + (restartResult.message || 'Unknown error'), 'error');
                        btnDetectUrl.textContent = originalText;
                        btnDetectUrl.disabled = false;
                    }
                } catch(e) {
                    showNotification('Error parsing restart response.', 'error');
                    btnDetectUrl.textContent = originalText;
                    btnDetectUrl.disabled = false;
                }
            } else {
                showNotification('Restart interface failed: HTTP ' + restartXhr.status, 'error');
                btnDetectUrl.textContent = originalText;
                btnDetectUrl.disabled = false;
            }
        };
        restartXhr.onerror = function(){
            btnDetectUrl.textContent = originalText;
            btnDetectUrl.disabled = false;
            showNotification('Network error during interface restart.', 'error');
        };
        restartXhr.send();
    };
    buildModal();
    var btnMacApply = document.getElementById('btn-mac-apply');
    if (btnMacApply) {
        btnMacApply.addEventListener('click', function(){
            if(btnMacApply.disabled) return;
            var modal = document.getElementById('al-mac-modal');
            if(!modal) buildModal();
            modal = document.getElementById('al-mac-modal');
            var title = modal.querySelector('.al-modal-title');
            var msg = modal.querySelector('.al-modal-msg');
            var confirmBtn = document.getElementById('al-modal-confirm');
            if(formState.applied){
                title.textContent = 'Konfirmasi Revert MAC';
                msg.textContent = 'Apakah Anda yakin ingin mengembalikan ke MAC address asli perangkat?';
                confirmBtn.onclick = function(){ modal.style.display='none'; execMac('revert'); };
            } else {
                title.textContent = 'Konfirmasi Ganti MAC';
                msg.textContent = 'Tindakan ini akan mengganti MAC address secara permanen dan memutus koneksi jaringan sementara (~3-8 detik). Lanjutkan?';
                confirmBtn.onclick = function(){ modal.style.display='none'; execMac('apply'); };
            }
            modal.style.display = 'flex';
        });
    }
    var btnMacRandom = document.getElementById('btn-mac-random');
    if (btnMacRandom) {
        btnMacRandom.addEventListener('click', function(){ 
            if(btnMacRandom.disabled || formState.applied) return;
            var selDevice = document.getElementById('f-device');
            var inpMac = document.getElementById('f-mac');
            if(selDevice && inpMac && selDevice.value){
                var newMac = generateVendorMac(selDevice.value, formState.originalMac);
                if(newMac && validateMac(newMac)){
                    inpMac.value = newMac.toUpperCase();
                    inpMac.classList.remove('al-mac-applied');
                    void inpMac.offsetWidth;
                    inpMac.classList.add('al-mac-applied');
                    syncUrlClientMac();
                }
            }
        });
    }
    var selM = document.getElementById('sel-login-method');
    if (selM) {
        selM.addEventListener('change', updateSecondaryDropdown);
        updateSecondaryDropdown();
    }
    var selDevice = document.getElementById('f-device');
    if (selDevice) {
	selDevice.addEventListener('change', function() {
        updateMacFromDevice(true);
	});
    }
    var inpMacEl = document.getElementById('f-mac');
    var btnRandEl = document.getElementById('btn-mac-random');
    var btnApplyEl = document.getElementById('btn-mac-apply');
    if(selDevice && inpMacEl && btnRandEl && btnApplyEl){
        if (formState.applied) {
            selDevice.disabled = false;
            selDevice.classList.add('al-state-applied');
            selDevice.onfocus = function(){ this.blur(); };
            btnRandEl.disabled = true;
            btnApplyEl.textContent = 'REVERT';
            btnApplyEl.classList.add('al-btn-revert');
            btnApplyEl.disabled = false;
        } else {
            applyInitialFormState(selDevice, inpMacEl, btnRandEl, btnApplyEl);
        }
        setButtonStateByUci(btnApplyEl, formState.applied);
        if (inpMacEl) {
            inpMacEl.addEventListener('input', function() {
                var currentMac = this.value.trim();
                var cmacField = document.getElementById('f-cmac');
                if (cmacField) cmacField.value = currentMac;
                var urlField = document.getElementById('f-url');
                if (urlField && urlField.value && currentMac) {
                    if (urlField.value.match(/([?&])client_mac=/i)) {
                        urlField.value = urlField.value.replace(/([?&])client_mac=[^&]*/i, '$1client_mac=' + currentMac);
                    }
                }
            });
        }
        var urlField = document.getElementById('f-url');
        if (urlField) {
            urlField.addEventListener('input', function() {
                syncSessionGridFromUrl();
                var currentPortalType = formState.portalType || '';
                var feat = portalConfig[currentPortalType];
                if (feat && feat.has_session_grid) {
                    setTimeout(validateSaveForm, 50);
                }
            });
            urlField.addEventListener('keydown', function(e) {
                if (e.keyCode === 13) {
                    e.preventDefault();
                    handleUrlPathChange();
                }
            });
        }
    }
    setTimeout(function() {
        validateSaveForm();
    }, 100);
}

function showNotification(message, type) {
    var notifEl = document.getElementById('al-login-notification');
    if (!notifEl) return;
    notifEl.style.display = '';
    notifEl.textContent = message;
    notifEl.classList.remove('success', 'error', 'warning', 'info', 'bug', 'hidden');
    notifEl.classList.add('al-notification-box', 'al-col-span-2', type);
}

function loadSavedProfiles() {
    var xhr = new XMLHttpRequest();
    xhr.open('GET', '/cgi-bin/luci/admin/autologin/get_profiles?_=' + Date.now(), true);
    xhr.timeout = 5000;
    xhr.onload = function() {
        if (xhr.status === 200) {
            try {
                var data = JSON.parse(xhr.responseText);
				if (data.portal_config) { portalConfig = data.portal_config; }
                savedProfileInterfaces.clear();
                if (data && data.profiles) {
                    data.profiles.forEach(function(p) {
                        var iface = (p.logical || '') + '/' + (p.device || '');
                        if (iface && iface !== '/') {
                            savedProfileInterfaces.add(iface);
                        }
                    });
                }
                if (data && data.profiles && data.profiles.length > 0) {
                    renderProfileSection(data.profiles);
                    var newInterval = calculatePollingInterval(data.profiles);
                    startStatusPolling(newInterval);
                } else {
                    hideProfileSection();
                    stopStatusPolling();
                }
            } catch(e) { console.error('[autologin] loadSavedProfiles parse error', e); }
        }
    };
    xhr.send();
}

function renderProfileSection(profiles) {
    var scanSection = document.getElementById('al-scan-section');
    if (!scanSection) return;
    if (document.getElementById('al-profiles-section')) {
        renderProfilesTable(profiles);
        return;
    }
    var div = document.createElement('div');
    div.id = 'al-profiles-section';
    div.innerHTML = 
        '<h3 class="al-card-title al-profiles-title">Profil Tersimpan</h3>' +
        '<div id="profiles-table-container"></div>' +
        '<div class="al-profiles-divider"></div>';
    scanSection.parentNode.insertBefore(div, scanSection);
    renderProfilesTable(profiles);
}

function renderProfilesTable(profiles) {
    var container = document.getElementById('profiles-table-container');
    if (!container) return;
    var html = '<table class="al-table"><thead><tr>' +
        '<th>PORTAL TYPE</th><th>INTERFACE</th><th>IP</th><th>MAC ADDRESS</th>' +
        '<th>STATUS</th><th>NOTIFIKASI</th><th>DAYA</th><th>AKSI</th></tr></thead><tbody>';
    profiles.forEach(function(p) {
        var ptText = (portalConfig[p.portal_type] && portalConfig[p.portal_type].label) || p.portal_type || 'Unknown';
        var notifBadge = p.telegram_enabled ? '<span class="al-badge al-badge-success">ON</span>' : '<span class="al-badge al-badge-off">OFF</span>';
        var initialStatusHTML = '<span class="al-status-loading">Loading...</span>';
        var toggleTextClass = p.enabled ? 'al-toggle-text-on' : 'al-toggle-text-off';
        var toggleText = p.enabled ? 'Aktif' : 'Tidak Aktif';
        var dayaColumn = 
            '<div class="al-cell-daya">' +
            '<label class="al-toggle-switch">' +
            '<input type="checkbox" class="profile-enable-toggle" data-id="' + p.id + '" ' + (p.enabled ? 'checked' : '') + ' onchange="toggleProfileEnabled(this)">' +
            '<span class="al-toggle-slider"></span>' +
            '</label>' +
            '<div class="al-toggle-status-text ' + toggleTextClass + '">' + toggleText + '</div>' +
            '</div>';
        html += '<tr>' +
            '<td>' + ptText + '</td>' +
            '<td class="al-cell-iface">' + (p.logical || '') + '/' + (p.device || '') + '</td>' +
            '<td>' + (p.ipc || '-') + '</td>' +
            '<td>' + (p.mac || '-') + '</td>' +
            '<td class="status-cell">' + initialStatusHTML + '</td>' +
            '<td>' + notifBadge + '</td>' +
            '<td>' + dayaColumn + '</td>' +
            '<td>' +
            '<div class="al-action-btn-group">' +
            '<button class="al-btn al-btn-primary al-btn-sm" data-action="edit" data-id="' + p.id + '">EDIT</button>' +
            '<button class="al-btn al-btn-danger al-btn-sm" data-action="delete" data-id="' + p.id + '">HAPUS</button>' +
            '</div>' +
            '</td>' +
        '</tr>';
    });
    html += '</tbody></table>';
    container.innerHTML = html;
    setTimeout(pollStatus, 100);
}

function refreshProfilesTable() {
    var xhr = new XMLHttpRequest();
    xhr.open('GET', '/cgi-bin/luci/admin/autologin/get_profiles?_=' + Date.now(), true);
    xhr.timeout = 5000;
    xhr.onload = function() {
        if (xhr.status === 200) {
            try {
                var data = JSON.parse(xhr.responseText);
				if (data.portal_config) { portalConfig = data.portal_config; }
                savedProfileInterfaces.clear();
                if (data && data.profiles) {
                    data.profiles.forEach(function(p) {
                        var iface = (p.logical || '') + '/' + (p.device || '');
                        if (iface && iface !== '/') {
                            savedProfileInterfaces.add(iface);
                        }
                    });
                }
                if (data && data.profiles && data.profiles.length > 0) {
                    if (!document.getElementById('al-profiles-section')) {
                        renderProfileSection(data.profiles);
                    } else {
                        renderProfilesTable(data.profiles);
                    }
                    var newInterval = calculatePollingInterval(data.profiles);
                    startStatusPolling(newInterval);
                } else {
                    hideProfileSection();
                    stopStatusPolling();
                }
            } catch(e) { console.error('[autologin] refreshProfilesTable parse error', e); }
        }
    };
    xhr.send();
}

function hideProfileSection() {
    var sec = document.getElementById('al-profiles-section');
    if (sec) sec.remove();
}

function pollStatus() {
    var xhr = new XMLHttpRequest();
    xhr.open('GET', '/cgi-bin/luci/admin/autologin/get_status?_=' + Date.now(), true);
    xhr.timeout = 3000;
    xhr.onload = function() {
        if (xhr.status === 200) {
            try {
                var statusData = JSON.parse(xhr.responseText);
                updateStatusColumn(statusData);
            } catch(e) {
                console.error('[autologin] pollStatus parse error', e);
            }
        }
    };
    xhr.onerror = function() {
        console.error('[autologin] pollStatus network error');
    };
    xhr.send();
}

function updateStatusColumn(statusData) {
    var rows = document.querySelectorAll('#profiles-table-container tbody tr');
    rows.forEach(function(row) {
        var editBtn = row.querySelector('[data-action="edit"]');
        if (editBtn) {
            var profileId = editBtn.getAttribute('data-id');
            var status = statusData[profileId];
            if (status) {
                var cells = row.querySelectorAll('td');
                if (cells[4]) {
                    cells[4].innerHTML = getStatusHTML(status);
                }
            }
        }
    });
}

function getStatusHTML(status) {
    var statusClassMap = {
        'CONNECTED': 'al-status-connected',
        'PORTAL_DETECTED': 'al-status-portal',
        'DISCONNECTED': 'al-status-disconnected',
        'IDLE': 'al-status-idle',
        'CHECKING': 'al-status-checking',
        'PERMANENT_ERROR': 'al-status-error'
    };
    var textMap = {
        'CONNECTED': 'CONNECTED',
        'PORTAL_DETECTED': 'LOGGING IN...',
        'DISCONNECTED': 'RECONNECTING',
        'IDLE': 'STANDBY',
        'CHECKING': 'MEMERIKSA...',
        'PERMANENT_ERROR': 'ERROR'
    };
    var cssClass = statusClassMap[status.status] || 'al-status-idle';
    var text = textMap[status.status] || 'STANDBY';
    var retryInfo = status.retry_count > 0 ? '<br><span class="al-status-retry-info">Retry: ' + status.retry_count + '</span>' : '';
    return '<span class="al-status-badge ' + cssClass + '">' + text + retryInfo + '</span>';
}

var statusPollingInterval = null;
var currentPollingInterval = 10000;

function calculatePollingInterval(profiles) {
    if (!profiles || profiles.length === 0) {
        return 10000;
    }
    var minInterval = Infinity;
    profiles.forEach(function(p) {
        var interval = parseInt(p.health_check_interval) || 30;
        if (interval < minInterval) {
            minInterval = interval;
        }
    });
    var intervalMs = Math.max(minInterval * 1000, 5000);
    return intervalMs;
}

function startStatusPolling(intervalMs) {
    if (!intervalMs) {
        intervalMs = currentPollingInterval;
    }
    if (intervalMs !== currentPollingInterval || !statusPollingInterval) {
        if (statusPollingInterval) {
            clearInterval(statusPollingInterval);
        }
        currentPollingInterval = intervalMs;
        pollStatus();
        statusPollingInterval = setInterval(pollStatus, intervalMs);
        console.log('[autologin] Status polling interval: ' + (intervalMs / 1000) + ' detik');
    }
}

function recalculateAndRestartPolling() {
    var xhr = new XMLHttpRequest();
    xhr.open('GET', '/cgi-bin/luci/admin/autologin/get_profiles?_=' + Date.now(), true);
    xhr.timeout = 5000;
    xhr.onload = function() {
        if (xhr.status === 200) {
            try {
                var data = JSON.parse(xhr.responseText);
                if (data && data.profiles) {
                    var newInterval = calculatePollingInterval(data.profiles);
                    startStatusPolling(newInterval);
                }
            } catch(e) {
                console.error('[autologin] recalculateAndRestartPolling parse error', e);
            }
        }
    };
    xhr.send();
}

function stopStatusPolling() {
    if (statusPollingInterval) {
        clearInterval(statusPollingInterval);
        statusPollingInterval = null;
    }
}

function editProfile(profileId) {
    showNotification('Memuat data profil...', 'warning');
    var spoofData = null;
    var profileData = null;
    var requestsCompleted = 0;
    var totalRequests = 2;
    function checkAllRequestsComplete() {
        requestsCompleted++;
        if (requestsCompleted === totalRequests) {
            processEditForm(profileId, spoofData, profileData);
        }
    }
    var xhrMac = new XMLHttpRequest();
    xhrMac.open('GET', '/cgi-bin/luci/admin/autologin/mac_spoof_check?_=' + Date.now(), true);
    xhrMac.timeout = 8000;
    xhrMac.onload = function() {
        if (xhrMac.status === 200) {
            try { spoofData = JSON.parse(xhrMac.responseText); } catch(e) { spoofData = { supported: false }; }
        } else { spoofData = { supported: false }; }
        checkAllRequestsComplete();
    };
    xhrMac.onerror = function() { spoofData = { supported: false }; checkAllRequestsComplete(); };
    xhrMac.send();
    var xhrProfile = new XMLHttpRequest();
    xhrProfile.open('GET', '/cgi-bin/luci/admin/autologin/get_profiles?_=' + Date.now(), true);
    xhrProfile.timeout = 5000;
    xhrProfile.onload = function() {
        if (xhrProfile.status === 200) {
            try {
                var data = JSON.parse(xhrProfile.responseText);
                if (data && data.profiles) {
                    for (var i = 0; i < data.profiles.length; i++) {
                        if (data.profiles[i].id === profileId) {
                            profileData = data.profiles[i];
                            break;
                        }
                    }
                }
            } catch(e) { console.error('[editProfile] get_profiles parse error', e); }
        }
        checkAllRequestsComplete();
    };
    xhrProfile.onerror = function() { showNotification('Network error saat load profil', 'error'); };
    xhrProfile.send();
}

function processEditForm(profileId, spoofData, profileData) {
    if (!profileData) { showNotification('Profil tidak ditemukan', 'error'); return; }
    formState.spoofSupported = (spoofData && (spoofData.supported === true || spoofData.supported === 'true'));
    isEditingProfile = true;
    currentEditProfileId = profileId;
    var vendorForForm = profileData.device_vendor || profileData.mac_vendor || '';
    var mockData = {
        iface: (profileData.logical || '') + '/' + (profileData.device || ''),
        type: profileData.portal_type,
        pt: (portalConfig[profileData.portal_type] && portalConfig[profileData.portal_type].label) || profileData.portal_type,
        mac: profileData.mac,
        url: profileData.url,
        macModified: (profileData.mac_modified === true || profileData.mac_modified === 'true') ? 'true' : 'false',
        macVendor: vendorForForm,
        ip: profileData.ipc || '',
        username: profileData.username,
        password: profileData.password,
        auto_login_enabled: profileData.auto_login_enabled,
        auto_reconnect_enabled: profileData.auto_reconnect_enabled,
        health_check_interval: profileData.health_check_interval || 30,
        stabilization_delay: profileData.stabilization_delay || 15,
        failure_cooldown: profileData.failure_cooldown || 5,
        max_retry: profileData.max_retry || 5,
        anti_blocking_enabled: profileData.anti_blocking_enabled,
        telegram_enabled: profileData.telegram_enabled,
        telegram_token: profileData.telegram_token,
        telegram_chat_id: profileData.telegram_chat_id,
        gw_id: profileData.gw_id,
        wlan: profileData.wlan,
        sessionid: profileData.sessionid,
        ipc: profileData.ipc,
        login_method: profileData.login_method,
        sub_method: profileData.sub_method
    };
    switchToForm(mockData, true);
    setTimeout(function() {
        validateSaveForm();
        checkInitialLoginState();
        showNotification('Silakan edit data dan klik UPDATE', 'success');
    }, 150);
}

function deleteProfile(profileId) {
    var xhr = new XMLHttpRequest();
    xhr.open('POST', '/cgi-bin/luci/admin/autologin/delete_profile', true);
    xhr.setRequestHeader('Content-Type', 'application/x-www-form-urlencoded');
    xhr.timeout = 15000;
    xhr.onload = function() {
        if (xhr.status === 200) {
            try {
                var r = JSON.parse(xhr.responseText);
                if (r.status === 'success') {
                    showNotification(r.message || 'Profil berhasil dihapus', 'success');
                    
                    setTimeout(function() {
                        refreshProfilesTable();
						
						if (btnAddProfile) {
						    btnAddProfile.click();
						}
                       
                        setTimeout(function() {
                            refreshProfilesTable();
                        }, 2000);
                    }, 500);
                    
                    if (isEditingProfile && currentEditProfileId === profileId) {
                        setTimeout(function() {
                            elFormContainer.style.display = 'none';
                            elFormContainer.innerHTML = '';
                            elScanSection.style.display = 'block';
                            isEditingProfile = false;
                            currentEditProfileId = null;
                            var profSec = document.getElementById('al-profiles-section');
                            if (profSec) {
                                profSec.style.display = 'block';
                            }
                        }, 500);
                    }
                } else {
                    showNotification(r.message || 'Gagal menghapus profil', 'error');
                }
            } catch(e) { 
                console.error('[autologin] deleteProfile parse error:', e);
                showNotification('Error parsing response', 'bug'); 
            }
        } else {
            showNotification('Delete failed: HTTP ' + xhr.status, 'error');
        }
    };
    xhr.onerror = function() { 
        console.error('[autologin] deleteProfile network error');
        showNotification('Network error', 'error'); 
    };
    xhr.ontimeout = function() {
        showNotification('Delete timeout', 'error');
    };
    xhr.send('profile_id=' + encodeURIComponent(profileId));
}

document.addEventListener('click', function(e) {
    if (e.target && e.target.matches('[data-action="edit"]')) {
        e.preventDefault();
        editProfile(e.target.getAttribute('data-id'));
    } else if (e.target && e.target.matches('[data-action="delete"]')) {
        e.preventDefault();
        var profileId = e.target.getAttribute('data-id');
        if (document.getElementById('al-delete-modal')) document.getElementById('al-delete-modal').remove();
        var m = document.createElement('div'); m.id = 'al-delete-modal'; m.className = 'al-modal-overlay';
        m.innerHTML = '<div class="al-modal-box"><h3 class="al-modal-title">Konfirmasi Hapus Profil</h3><p class="al-modal-msg">Apakah Anda yakin ingin menghapus profil ini? Tindakan ini tidak dapat dibatalkan.</p><div class="al-modal-actions"><button id="al-delete-cancel" class="al-btn al-btn-secondary">TIDAK</button><button id="al-delete-confirm" class="al-btn" style="background:#ef4444;border-color:#ef4444;color:#fff;">YA, HAPUS</button></div></div>';
        (document.getElementById('autologin-root') || document.body).appendChild(m);
        document.getElementById('al-delete-cancel').onclick = function() { m.style.display = 'none'; m.remove(); };
        document.getElementById('al-delete-confirm').onclick = function() { 
            m.style.display = 'none'; m.remove(); 
            deleteProfile(profileId);
        };
        m.style.display = 'flex';
    }
});

function toggleProfileEnabled(el) {
    var profileId = el.getAttribute('data-id');
    var isEnabled = el.checked;
    var statusTextEl = el.parentElement.nextElementSibling;
    
    statusTextEl.textContent = isEnabled ? 'Aktif' : 'Tidak Aktif';
    statusTextEl.classList.remove('al-toggle-text-on', 'al-toggle-text-off');
    statusTextEl.classList.add(isEnabled ? 'al-toggle-text-on' : 'al-toggle-text-off');

    var xhr = new XMLHttpRequest();
    xhr.open('POST', '/cgi-bin/luci/admin/autologin/update_enabled_status', true);
    xhr.setRequestHeader('Content-Type', 'application/x-www-form-urlencoded');
    xhr.timeout = 5000;
    xhr.onload = function() {
        if (xhr.status === 200) {
            try {
                var r = JSON.parse(xhr.responseText);
                if (r.status !== 'success') {
                    el.checked = !isEnabled;
                    statusTextEl.textContent = !isEnabled ? 'Aktif' : 'Tidak Aktif';
                    statusTextEl.classList.remove('al-toggle-text-on', 'al-toggle-text-off');
                    statusTextEl.classList.add(!isEnabled ? 'al-toggle-text-on' : 'al-toggle-text-off');
                    showNotification(r.message || 'Gagal mengubah status profil', 'error');
                } else {
                    showNotification(isEnabled ? 'Profil diaktifkan dan state dibersihkan.' : 'Profil dinonaktifkan dan state dibersihkan.', 'success');
                    setTimeout(refreshProfilesTable, 500);
                }
            } catch(e) {
                showNotification('Error parsing response', 'bug');
            }
        } else {
            el.checked = !isEnabled;
            statusTextEl.textContent = !isEnabled ? 'Aktif' : 'Tidak Aktif';
            statusTextEl.classList.remove('al-toggle-text-on', 'al-toggle-text-off');
            statusTextEl.classList.add(!isEnabled ? 'al-toggle-text-on' : 'al-toggle-text-off');
            showNotification('Network error', 'error');
        }
    };
    xhr.onerror = function() { 
        el.checked = !isEnabled;
        statusTextEl.textContent = !isEnabled ? 'Aktif' : 'Tidak Aktif';
        statusTextEl.classList.remove('al-toggle-text-on', 'al-toggle-text-off');
        statusTextEl.classList.add(!isEnabled ? 'al-toggle-text-on' : 'al-toggle-text-off');
        showNotification('Network error', 'error');
    };
    xhr.send('profile_id=' + encodeURIComponent(profileId) + '&enabled=' + (isEnabled ? 'true' : 'false'));
}

function transformButtonToLogout() {
    var btn = document.getElementById('btn-login');
    if (!btn) return;
    btn.textContent = 'LOGOUT';
    btn.classList.remove('al-btn-primary');
    btn.classList.add('al-btn-revert');
    btn.disabled = false;
    btn.onclick = performLogout;
    formState.isLogoutMode = true;
}

function transformButtonToLogin() {
    var btn = document.getElementById('btn-login');
    if (!btn) return;
    btn.textContent = 'LOGIN';
    btn.classList.remove('al-btn-revert');
    btn.classList.add('al-btn-primary');
    btn.disabled = false;
    btn.onclick = performLogin;
    formState.isLogoutMode = false;
}

function performLogout() {
    var btnLogout = document.getElementById('btn-login');
    btnLogout.textContent = 'PROCESSING...';
    btnLogout.disabled = true;
    showNotification('Membersihkan state dan mengirim logout...', 'warning');

    var payload = {
        portal_type: formState.portalType,
        url: document.getElementById('f-url') ? document.getElementById('f-url').value : '',
        device: formState.device,
        logical: formState.logical,
        mac: document.getElementById('f-mac') ? document.getElementById('f-mac').value : ''
    };
	
    var xhr = new XMLHttpRequest();
    xhr.open('POST', '/cgi-bin/luci/admin/autologin/logout', true);
    xhr.setRequestHeader('Content-Type', 'application/json');
    xhr.timeout = 15000;
    xhr.onload = function() {
        btnLogout.disabled = false;
        try {
            var r = JSON.parse(xhr.responseText);
            if (r.status === 'success' || r.status === 'warning') {
                showNotification(r.message || 'Logout berhasil! Firewall & network sedang direstart...', 'success');
                setTimeout(function() {
                    showNotification('Firewall & network telah direstart. State jaringan bersih total.', 'success');
                }, 3000);
                transformButtonToLogin();
            } else {
                showNotification(r.message || 'Logout gagal.', 'error');
                transformButtonToLogin();
            }
        } catch(e) {
            showNotification('Error parsing logout response.', 'bug');
            transformButtonToLogin();
        }
    };
    xhr.onerror = function() {
        btnLogout.disabled = false;
        showNotification('Network error during logout.', 'error');
        transformButtonToLogin();
    };
    payload.telegram_enabled = document.getElementById('f-telegram') ? document.getElementById('f-telegram').checked : false;
    payload.telegram_token = document.getElementById('f-telegram-token') ? document.getElementById('f-telegram-token').value : '';
    payload.telegram_chat_id = document.getElementById('f-telegram-chat') ? document.getElementById('f-telegram-chat').value : '';
	xhr.send(JSON.stringify(payload));
}

function checkInitialLoginState() {
    var profileId = (formState.logical || 'unknown') + '_' + (formState.portalType || 'unknown').toLowerCase();
    profileId = profileId.replace(/[^a-z0-9_]/g, '_');
    
    var xhr = new XMLHttpRequest();
    xhr.open('GET', '/cgi-bin/luci/admin/autologin/get_status?_=' + Date.now(), true);
    xhr.timeout = 3000;
    xhr.onload = function() {
        if (xhr.status === 200) {
            try {
                var statusData = JSON.parse(xhr.responseText);
                if (statusData[profileId] && statusData[profileId].status === 'CONNECTED') {
                    transformButtonToLogout();
                } else {
                    transformButtonToLogin();
                }
            } catch(e) {}
        }
    };
    xhr.send();
}

function performLogin() {
    var btnLogin = document.getElementById('btn-login');
    var originalText = btnLogin.textContent;
    var urlField = document.getElementById('f-url');
    var userField = document.getElementById('f-user');
    var passField = document.getElementById('f-pass');
    if (!urlField || !userField || !passField || !urlField.value || !userField.value || !passField.value) {
        showNotification('Gagal: URL, Username, dan Password wajib diisi!', 'error');
        return;
    }
    btnLogin.textContent = 'PROCESSING...';
    btnLogin.disabled = true;
    var notifEl = document.getElementById('al-login-notification');
    if (notifEl) notifEl.style.display = 'none';

    showNotification('Memproses login...', 'warning');

    var rawUser = userField.value;
	var originalUsername = rawUser;
    var lmEl = document.getElementById('sel-login-method');
    var loginMethod = lmEl ? lmEl.value : '';
    var subMethod = '';
    if (loginMethod === 'Komunitas' || loginMethod === 'ISP') {
        var subEl = document.getElementById('f-' + loginMethod.toLowerCase());
        subMethod = subEl ? subEl.value : '';
    } else {
        subMethod = loginMethod;
    }
	
    var finalUser = transformUsername(rawUser, loginMethod, subMethod);

    syncUrlClientMac();
	var currentSpoofedMac = document.getElementById('f-mac') ? document.getElementById('f-mac').value.trim() : formState.originalMac;
    
    var handlerScript = '';
    var urlField = document.getElementById('f-url');
    if (urlField && urlField.value && portalConfig) {
        var currentPath = extractPathFromUrl(urlField.value);
        var normalizedPath = normalizePath(currentPath);
        if (normalizedPath) {
            for (var key in portalConfig) {
                if (key === '_default_path') continue;
                var feat = portalConfig[key];
                if (feat.known_paths && feat.known_paths.indexOf(normalizedPath) !== -1) {
                    // Cari di daftar handlers berdasarkan path
                    if (feat.handlers && feat.handlers.length > 0) {
                        for (var i = 0; i < feat.handlers.length; i++) {
                            if (feat.handlers[i].path === normalizedPath) {
                                handlerScript = feat.handlers[i].handler;
                                break;
                            }
                        }
                    }
                    if (!handlerScript && feat.handler_script) {
                        handlerScript = feat.handler_script;
                    }
                    if (handlerScript) break;
                }
            }
        }
    }
    if (!handlerScript && portalConfig[formState.portalType] && portalConfig[formState.portalType].handler_script) {
        handlerScript = portalConfig[formState.portalType].handler_script;
    }
    
    var payload = {
        portal_type: formState.portalType,
        url: urlField.value,
        username: finalUser,
		original_username: originalUsername,
        password: passField.value,
        device: formState.device,
        logical: formState.logical,
        mac: currentSpoofedMac,
        login_method: loginMethod,
        sub_method: subMethod,
        handler_script: handlerScript
    };
    if (portalConfig[formState.portalType] && portalConfig[formState.portalType].has_session_grid) {
        var gwidEl = document.getElementById('f-gwid');
        var wlanEl = document.getElementById('f-wlan');
        var sidEl = document.getElementById('f-sid');
        var ipcEl = document.getElementById('f-ipc');
        if (gwidEl && wlanEl && sidEl && ipcEl) {
            payload.gw_id = gwidEl.value;
            payload.wlan = wlanEl.value;
            payload.sessionid = sidEl.value;
            payload.ipc = ipcEl.value;
        }
    }
    if (portalConfig[formState.portalType] && portalConfig[formState.portalType].wms_username) {
        var wmsFormat = formatWmsUsername(userField.value);
        payload.username_ = wmsFormat.raw;
        payload.username = wmsFormat.formatted;
    }
    
    var xhr = new XMLHttpRequest();
    xhr.open('POST', '/cgi-bin/luci/admin/autologin/login', true);
    xhr.setRequestHeader('Content-Type', 'application/json');
    xhr.timeout = 20000;
    xhr.onload = function() {
        btnLogin.textContent = originalText;
        btnLogin.disabled = false;
        try {
            var r = JSON.parse(xhr.responseText);
            if (r.status === 'success') {
                showNotification(r.message || 'Login berhasil!', 'success');
                transformButtonToLogout();
            } else if (r.status === 'error') {
                showNotification(r.message || 'Login gagal.', 'error');
            } else if (r.status === 'bug') {
                showNotification('Bug Sistem: ' + (r.message || 'Terjadi kesalahan internal handler.'), 'bug');
            } else {
                showNotification('Respons tidak dikenal dari server.', 'warning');
            }
        } catch(e) {
            console.error('[autologin] performLogin parse error:', e);
            showNotification('Error: Gagal memparse respons server (HTTP ' + xhr.status + ').', 'bug');
        }
    };
    xhr.onerror = function() {
        btnLogin.textContent = originalText;
        btnLogin.disabled = false;
        showNotification('Error: Koneksi jaringan terputus saat proses login.', 'error');
    };
    xhr.ontimeout = function() {
        btnLogin.textContent = originalText;
        btnLogin.disabled = false;
        showNotification('Error: Waktu proses login habis (timeout). Portal mungkin tidak merespons.', 'error');
    };
    payload.telegram_enabled = document.getElementById('f-telegram') ? document.getElementById('f-telegram').checked : false;
    payload.telegram_token = document.getElementById('f-telegram-token') ? document.getElementById('f-telegram-token').value : '';
    payload.telegram_chat_id = document.getElementById('f-telegram-chat') ? document.getElementById('f-telegram-chat').value : '';
	xhr.send(JSON.stringify(payload));
}

var tabButtons = document.querySelectorAll('.al-tab');
tabButtons.forEach(function(btn) {
    btn.addEventListener('click', function() {
        var targetTab = this.getAttribute('data-tab');
        tabButtons.forEach(function(b) { b.classList.remove('active'); });
        this.classList.add('active');
        var panes = document.querySelectorAll('.al-pane');
        panes.forEach(function(p) { p.classList.remove('active'); });
        var targetPane = document.getElementById('tab-' + targetTab);
        if (targetPane) {
            targetPane.classList.add('active');
        }
    });
});

function validateSaveForm() {
    var btnLogin = document.getElementById('btn-login');
    var btnSave = document.getElementById('btn-save');
    if (!btnLogin && !btnSave) return;
    var device = document.getElementById('f-device') ? document.getElementById('f-device').value : '';
    var mac = document.getElementById('f-mac') ? document.getElementById('f-mac').value : '';
    var url = document.getElementById('f-url') ? document.getElementById('f-url').value : '';
    var user = document.getElementById('f-user') ? document.getElementById('f-user').value : '';
    var pass = document.getElementById('f-pass') ? document.getElementById('f-pass').value : '';
    var isLoginValid = (url.trim() !== '') && (user.trim() !== '') && (pass.trim() !== '');
    var loginMethodEl = document.getElementById('sel-login-method');
    var loginMethod = loginMethodEl ? loginMethodEl.value : '';
    var subMethod = '';
    if (loginMethod === 'Komunitas' || loginMethod === 'ISP') {
        var subEl = document.getElementById('f-' + loginMethod.toLowerCase());
        subMethod = subEl ? subEl.value : '';
    } else {
        subMethod = loginMethod;
    }
    if (loginMethod === 'Komunitas' && subMethod === 'Kampus') {
        if (user.indexOf('@') === -1) {
            isLoginValid = false;
        }
    }
    var pType = formState.portalType || '';
    var gwidEl = document.getElementById('f-gwid');
    var wlanEl = document.getElementById('f-wlan');
    var sidEl = document.getElementById('f-sid');
    var ipcEl = document.getElementById('f-ipc');
    var sessionValid = true;
    if (portalConfig[pType] && portalConfig[pType].has_session_grid) {
        sessionValid = (gwidEl && gwidEl.value.trim() !== '') &&
                       (wlanEl && wlanEl.value.trim() !== '') &&
                       (sidEl && sidEl.value.trim() !== '') &&
                       (ipcEl && ipcEl.value.trim() !== '');
    }
    var loginMethodValid = true;
    if (portalConfig[pType] && portalConfig[pType].has_login_method) {
        var loginMethodEl = document.getElementById('sel-login-method');
        if (loginMethodEl) {
            var loginMethod = loginMethodEl.value;
            var subMethodValid = false;
            if (loginMethod === 'Standar') {
                subMethodValid = true;
            } else if (loginMethod === 'Komunitas' || loginMethod === 'ISP') {
                var subSelect = document.getElementById('f-' + loginMethod.toLowerCase());
                if (subSelect && subSelect.value !== '') {
                    subMethodValid = true;
                }
            }
            loginMethodValid = (loginMethod !== '') && subMethodValid;
        }
    }
    isLoginValid = isLoginValid && sessionValid && loginMethodValid;
    var isSaveValid = isLoginValid && (device !== '') && validateMac(mac);
    if (btnLogin) {
        if (isEditingProfile) {
            btnLogin.disabled = true;
        } else {
            btnLogin.disabled = !isLoginValid;
        }
    }
    if (btnSave) {
        btnSave.disabled = !isSaveValid;
    }
}

function attachSaveValidationListeners() {
    var fieldsToWatch = [
        'f-device', 'f-mac', 'f-url', 'f-user', 'f-pass',
        'sel-login-method', 'f-gwid', 'f-wlan', 'f-sid', 'f-ipc'
    ];
    fieldsToWatch.forEach(function(id) {
        var el = document.getElementById(id);
        if (el) {
            el.addEventListener('input', validateSaveForm);
            el.addEventListener('change', validateSaveForm);
            el.addEventListener('paste', validateSaveForm);
            el.addEventListener('cut', validateSaveForm);
            if (el.type === 'password') {
                el.addEventListener('keyup', validateSaveForm);
            }
        }
    });
    var dynamicObserver = new MutationObserver(function(mutations) {
        mutations.forEach(function(mutation) {
            if (mutation.type === 'childList') {
                ['f-komunitas', 'f-isp'].forEach(function(dynamicId) {
                    var dynEl = document.getElementById(dynamicId);
                    if (dynEl && !dynEl._hasValidationListener) {
                        dynEl.addEventListener('change', validateSaveForm);
                        dynEl._hasValidationListener = true;
                    }
                });
            }
        });
    });
    var container = document.getElementById('sel-dynamic-container');
    if (container) {
        dynamicObserver.observe(container, { childList: true, subtree: true });
    }
    validateSaveForm();
}

function performSave() {
    var btnSave = document.getElementById('btn-save');
    var originalText = btnSave.textContent;
    validateSaveForm();
    if (btnSave.disabled) return;
    btnSave.textContent = 'MENYIMPAN...';
    btnSave.disabled = true;

    var rawUser = document.getElementById('f-user').value;
    var lmEl = document.getElementById('sel-login-method');
    var loginMethod = lmEl ? lmEl.value : '';
    var subMethod = '';
    if (loginMethod === 'Komunitas' || loginMethod === 'ISP') {
        var subEl = document.getElementById('f-' + loginMethod.toLowerCase());
        subMethod = subEl ? subEl.value : '';
    } else {
        subMethod = loginMethod;
    }
	
    var finalUser = transformUsername(rawUser, loginMethod, subMethod);
	
	syncUrlClientMac();

    var isNewProfile = !isEditingProfile;
    var hasSessionGrid = false;
    if (portalConfig[formState.portalType] && portalConfig[formState.portalType].has_session_grid) {
        hasSessionGrid = true;
    }
    
    var payload = {
        logical: formState.logical,
        device: formState.device,
        portal_type: formState.portalType,
        mac: document.getElementById('f-mac').value,
        url: document.getElementById('f-url').value,
        username: finalUser,
		original_username: rawUser,
        password: document.getElementById('f-pass').value,
        device_vendor: document.getElementById('f-device').value,
        auto_login_enabled: document.getElementById('f-auto-login').checked,
        auto_reconnect_enabled: document.getElementById('f-auto-reconnect').checked,
        health_check_interval: parseInt(document.getElementById('f-health-interval').value) || 30,
        stabilization_delay: parseInt(document.getElementById('f-stab-delay').value) || 15,
        failure_cooldown: parseInt(document.getElementById('f-fail-cd').value) || 5,
        max_retry: parseInt(document.getElementById('f-max-retry').value) || 5,
        anti_blocking_enabled: document.getElementById('f-anti-blocking').checked,
        telegram_enabled: document.getElementById('f-telegram').checked,
        telegram_token: document.getElementById('f-telegram-token').value,
        telegram_chat_id: document.getElementById('f-telegram-chat').value,
        login_method: loginMethod,
        sub_method: subMethod,
        is_new: isNewProfile,
        has_session_grid: hasSessionGrid
    };
    if (portalConfig[formState.portalType] && portalConfig[formState.portalType].has_session_grid) {
        var gwidEl = document.getElementById('f-gwid');
        var wlanEl = document.getElementById('f-wlan');
        var sidEl = document.getElementById('f-sid');
        var ipcEl = document.getElementById('f-ipc');
        if (gwidEl) payload.gw_id = gwidEl.value;
        if (wlanEl) payload.wlan = wlanEl.value;
        if (sidEl) payload.sessionid = sidEl.value;
        if (ipcEl) payload.ipc = ipcEl.value;
    }
    var xhr = new XMLHttpRequest();
    xhr.open('POST', '/cgi-bin/luci/admin/autologin/save_profile', true);
    xhr.setRequestHeader('Content-Type', 'application/json');
    xhr.timeout = 10000;
    xhr.onload = function() {
        btnSave.textContent = originalText;
        validateSaveForm();
        try {
            var r = JSON.parse(xhr.responseText);
            if (r.status === 'success') {
                showNotification(r.message || 'Profil berhasil disimpan!', 'success');
                
                var savedIface = formState.logical + '/' + formState.device;
                savedProfileInterfaces.add(savedIface);
                
                var scanRows = document.querySelectorAll('#scan-result-container .al-pick-btn');
                scanRows.forEach(function(btn) {
                    if (btn.getAttribute('data-iface') === savedIface) {
                        var row = btn.closest('tr');
                        if (row) {
                            var statusCell = row.querySelector('.al-text-portal-login');
                            if (statusCell) {
                                statusCell.textContent = 'Auto Login';
                                statusCell.classList.add('al-text-auto-login');
                            }
                        }
                        btn.textContent = 'TERSIMPAN';
                        btn.classList.remove('al-btn-primary');
                        btn.classList.add('al-btn-secondary');
                        btn.disabled = true;
                    }
                });
                
                refreshProfilesTable();
                isEditingProfile = false;
                currentEditProfileId = null;
                setTimeout(function() {
                    elFormContainer.style.display = 'none';
                    elFormContainer.innerHTML = '';
                    elScanSection.style.display = 'block';
                    var profSec = document.getElementById('al-profiles-section');
                    if (profSec) {
                        profSec.style.display = 'block';
                    }
                }, 1000);
            } else {
                showNotification(r.message || 'Gagal menyimpan profil.', 'error');
            }
        } catch(e) { showNotification('Error: Gagal memparse respons server.', 'bug'); }
    };
    xhr.onerror = function() {
        btnSave.textContent = originalText;
        validateSaveForm();
        showNotification('Error: Koneksi jaringan terputus saat menyimpan.', 'error');
    };
    xhr.ontimeout = function() {
        btnSave.textContent = originalText;
        validateSaveForm();
        showNotification('Error: Waktu penyimpanan habis.', 'error');
    };
    xhr.send(JSON.stringify(payload));
}

loadSavedProfiles();

window.addEventListener('beforeunload', function() {
    stopStatusPolling();
});

window.toggleProfileEnabled = toggleProfileEnabled;


(function initSpeedTestRandom() {
    var speedtestFrame = document.querySelector('#tab-speedtest iframe');
    if (!speedtestFrame) return;

    var services = [
        { url: 'https://openspeedtest.com/speedtest', label: 'OpenSpeedtest' },
        { url: 'https://fast.com', label: 'Fast.com' }
    ];
    var label = document.getElementById('speedtest-label');

    function loadRandomSpeedTest() {
        var randomIndex = Math.floor(Math.random() * services.length);
        var chosen = services[randomIndex];
        if (speedtestFrame) {
            speedtestFrame.src = chosen.url;
        }
        if (label) {
            label.textContent = chosen.label;
        }
    }

    var tabs = document.querySelectorAll('.al-tab');
    tabs.forEach(function(tab) {
        tab.addEventListener('click', function() {
            if (this.getAttribute('data-tab') === 'speedtest') {
                loadRandomSpeedTest();
            }
        });
    });

    // Jika tab Speed Test aktif saat halaman dimuat, langsung random
    if (document.getElementById('tab-speedtest').classList.contains('active')) {
        loadRandomSpeedTest();
    }
})();


})();
//]]>