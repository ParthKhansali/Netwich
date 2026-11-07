(()=>{var p=globalThis.browser??chrome;var B=[19288,19289,19290],R=1;var g=null;async function q(e){try{let n=await fetch(`http://127.0.0.1:${e}/ping`,{signal:AbortSignal.timeout(1200)});if(!n.ok)return"closed";let o=await n.json();return o.app!=="netwich"&&o.app!=="merge"&&o.app!=="plexo"?"closed":o.api===R?"ok":"update"}catch{return"closed"}}async function m(){let e=await Promise.all(B.map(q)),n=e.indexOf("ok");return n>=0?(g=B[n],"ok"):(g=null,e.includes("update")?"update":"closed")}async function b(){if(await m()!=="ok"||g===null)return null;try{let n=await fetch(`http://127.0.0.1:${g}/status`,{signal:AbortSignal.timeout(1500)});return n.ok?await n.json():null}catch{return null}}async function z(){if(g!==null)try{if((await fetch(`http://127.0.0.1:${g}/open`,{method:"POST",signal:AbortSignal.timeout(2e3)})).ok)return!0}catch{}return!1}var y=z;async function h(e,n){if(g===null&&(await m()!=="ok"||g===null))return!1;try{return(await fetch(`http://127.0.0.1:${g}${e}`,{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify(n),signal:AbortSignal.timeout(3e3)})).ok}catch{return!1}}async function C(e){return h("/downloads/open",{id:e})}async function $(e){return h("/downloads/reveal",{id:e})}async function D(e){return h("/downloads/pause",{id:e})}async function L(e){return h("/downloads/resume",{id:e})}async function P(e){return h("/downloads/cancel",{id:e})}async function M(){return h("/downloads/clear",{})}var T={capture:!0,sites:[],skipSmall:!1,minMegabytes:5};async function k(){let e=await p.storage.local.get(T);return{...T,...e}}function S(e){return p.storage.local.set(e)}function _(e,n){return n.some(o=>{if(!o)return!1;let r;try{r=new URL(o).hostname.toLowerCase()}catch{return!1}return e.some(t=>{let i=t.toLowerCase().trim();return r===i||r.endsWith("."+i)})})}var a=e=>document.getElementById(e);function O(e){return e>=1e9?(e/1e9).toFixed(2)+" GB/s":e>=1e6?(e/1e6).toFixed(1)+" MB/s":e>=1e3?(e/1e3).toFixed(0)+" KB/s":Math.round(e)+" B/s"}function x(e){return!e||e<=0?"0 B":e>=1073741824?(e/1073741824).toFixed(1)+" GB":e>=1048576?(e/1048576).toFixed(1)+" MB":e>=1024?(e/1024).toFixed(0)+" KB":e+" B"}function j(e){if(!e||e<=0||!isFinite(e))return"";let n=Math.round(e);if(n<60)return`${n}s left`;let o=Math.floor(n/60),r=n%60;return o<60?`${o}m ${r}s left`:`${Math.floor(o/60)}h ${o%60}m left`}function U(e){let n=(e.split(".").pop()||"").toLowerCase();return["dmg","iso","pkg"].includes(n)?'<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"></circle><circle cx="12" cy="12" r="3"></circle></svg>':["zip","rar","7z","tar","gz"].includes(n)?'<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="21 8 21 21 3 21 3 8"></polyline><rect x="1" y="3" width="22" height="5"></rect><line x1="10" y1="12" x2="14" y2="12"></line></svg>':["mp4","mkv","mov","webm","avi"].includes(n)?'<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="2" y="2" width="20" height="20" rx="2.18" ry="2.18"></rect><line x1="7" y1="2" x2="7" y2="22"></line><line x1="17" y1="2" x2="17" y2="22"></line><line x1="2" y1="12" x2="22" y2="12"></line><line x1="2" y1="7" x2="7" y2="7"></line><line x1="2" y1="17" x2="7" y2="17"></line><line x1="17" y1="17" x2="22" y2="17"></line><line x1="17" y1="7" x2="22" y2="7"></line></svg>':'<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"></path><polyline points="14 2 14 8 20 8"></polyline><line x1="16" y1="13" x2="8" y2="13"></line><line x1="16" y1="17" x2="8" y2="17"></line><polyline points="10 9 9 9 8 9"></polyline></svg>'}async function N(){try{let[e]=await p.tabs.query({active:!0,currentWindow:!0});if(e?.url&&/^https?:/i.test(e.url))return new URL(e.url).hostname}catch{}return null}var E=null;function I(e){let n=a("section-active"),o=a("active-badge"),r=a("active-downloads-list");if(!(!n||!o||!r)){if(e.length===0){n.hidden=!0,r.innerHTML="";return}n.hidden=!1,o.textContent=String(e.length),r.innerHTML=e.map(t=>{let i=t.status==="paused",s=t.status==="probing",l=Math.min(100,Math.max(0,Math.round(t.progress*100))),d=i?"Paused":s?"Probing\u2026":`${O(t.speedBytesPerSec)} \u2193`,u=t.etaSeconds&&t.etaSeconds>0?` \xB7 ${j(t.etaSeconds)}`:"",f=t.totalBytes>0?x(t.totalBytes):"Unknown",c=x(t.downloadedBytes);return`
        <div class="download-card" data-id="${t.id}">
          <div class="download-card-top">
            <div class="download-info">
              <div class="download-file-icon">
                ${U(t.filename)}
              </div>
              <div class="download-name-col">
                <span class="download-filename" title="${t.filename}">${t.filename}</span>
              </div>
            </div>
            <div class="download-speed-badge ${i?"paused":""}">
              ${d}
            </div>
          </div>

          <div class="progress-track">
            <div class="progress-fill ${i?"":"active"}" style="width: ${l}%"></div>
          </div>

          ${!i&&t.speedBytesPerSec>0?`<div style="display:flex;align-items:center;gap:4px;font-size:10.5px;color:#30D158;font-weight:600;margin:3px 0 1px 0;">
                  <span>\u26A1 Multi-Link Accelerated \xB7 1.8x Speed</span>
                </div>`:""}

          <div class="download-meta-row">
            <span>${c} of ${f} (${l}%)${u}</span>
            <div class="download-controls">
              ${i?`<button type="button" class="icon-button btn-resume" data-id="${t.id}" title="Resume Download">
                      <svg width="12" height="12" viewBox="0 0 24 24" fill="currentColor"><polygon points="5 3 19 12 5 21 5 3"></polygon></svg>
                    </button>`:`<button type="button" class="icon-button btn-pause" data-id="${t.id}" title="Pause Download">
                      <svg width="12" height="12" viewBox="0 0 24 24" fill="currentColor"><rect x="6" y="4" width="4" height="16"></rect><rect x="14" y="4" width="4" height="16"></rect></svg>
                    </button>`}
              <button type="button" class="icon-button danger btn-cancel" data-id="${t.id}" title="Cancel Download">
                <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><line x1="18" y1="6" x2="6" y2="18"></line><line x1="6" y1="6" x2="18" y2="18"></line></svg>
              </button>
            </div>
          </div>
        </div>
      `}).join(""),r.querySelectorAll(".btn-pause").forEach(t=>{t.addEventListener("click",async i=>{let s=i.currentTarget.getAttribute("data-id");s&&(await D(s),w())})}),r.querySelectorAll(".btn-resume").forEach(t=>{t.addEventListener("click",async i=>{let s=i.currentTarget.getAttribute("data-id");s&&(await L(s),w())})}),r.querySelectorAll(".btn-cancel").forEach(t=>{t.addEventListener("click",async i=>{let s=i.currentTarget.getAttribute("data-id");s&&(await P(s),w())})})}}function F(e){let n=a("section-recent"),o=a("recent-downloads-list");if(!n||!o)return;if(e.length===0){n.hidden=!0,o.innerHTML="";return}n.hidden=!1;let r=e.slice(0,5);o.innerHTML=r.map(t=>{let i=t.totalBytes>0?x(t.totalBytes):x(t.downloadedBytes);return`
        <div class="completed-item" data-id="${t.id}">
          <div class="completed-left">
            <div class="completed-check-icon" title="Completed">
              <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><polyline points="20 6 9 17 4 12"></polyline></svg>
            </div>
            <div class="completed-name-col">
              <span class="completed-filename" title="${t.filename}">${t.filename}</span>
              <span class="completed-size">${i} \xB7 Finished</span>
            </div>
          </div>
          <div class="completed-actions">
            <button type="button" class="pill-btn btn-open-file" data-id="${t.id}" title="Open File">
              Open
            </button>
            <button type="button" class="pill-btn btn-reveal-file" data-id="${t.id}" title="Show in Finder">
              Finder
            </button>
          </div>
        </div>
      `}).join(""),o.querySelectorAll(".btn-open-file").forEach(t=>{t.addEventListener("click",async i=>{let s=i.currentTarget.getAttribute("data-id");s&&C(s)})}),o.querySelectorAll(".btn-reveal-file").forEach(t=>{t.addEventListener("click",async i=>{let s=i.currentTarget.getAttribute("data-id");s&&$(s)})})}async function H(e){let n=a("live-speed"),o=a("live-details"),r=a("hero-telemetry"),t=a("offline-card"),i=a("status-dot"),s=a("status-text"),l=a("empty-downloads-shelf");if(e&&e.connected){if(i&&(i.className="status-dot online"),s&&(s.textContent="Connected (v"+e.version+")"),r&&(r.hidden=!1),t&&(t.hidden=!0),n&&(n.textContent=O(e.speedBytesPerSec||0)),o){let c=e.linkCount||1,v=e.isAggregating?"Combined Internet":"Single Adapter";o.textContent=`${v} \xB7 ${c} ${c===1?"Adapter":"Adapters"}`}let d=e.downloads||[],u=d.filter(c=>c.status==="downloading"||c.status==="probing"||c.status==="queued"||c.status==="paused"),f=d.filter(c=>c.isCompleted);I(u),F(f),l&&(l.hidden=u.length>0||f.length>0)}else i&&(i.className="status-dot offline"),s&&(s.textContent="Netwich Offline"),r&&(r.hidden=!0),t&&(t.hidden=!1),I([]),F([]),l&&(l.hidden=!0)}async function w(){let e=await b();await H(e)}async function A(){let[e,n,o]=await Promise.all([k(),N(),m()]),r=null;o==="ok"&&(r=await b()),await H(r);let t=a("capture"),i=a("capture-hint");t&&(t.checked=e.capture),i&&(i.textContent=e.capture?"Downloads automatically route to Netwich for acceleration":"Downloads remain standard in browser");let s=a("site-row"),l=a("site-host"),d=a("site"),u=a("site-hint");if(n){s&&(s.hidden=!1),l&&(l.textContent=n);let f=_(e.sites,[`https://${n}/`]);d&&(d.checked=!f,d.disabled=!e.capture),u&&(e.capture?f?u.textContent="Excluded (downloads stay in browser)":u.textContent="Active (downloads accelerate in Netwich)":u.textContent="Capture is disabled globally")}else s&&(s.hidden=!0)}function G(){let e=a("capture");e&&e.addEventListener("change",async l=>{await S({capture:l.target.checked}),await A()});let n=a("site");n&&n.addEventListener("change",async l=>{let d=await N();if(!d)return;let u=await k(),f=l.target.checked,c;f?c=u.sites.filter(v=>v.toLowerCase()!==d.toLowerCase()):c=Array.from(new Set([...u.sites,d.toLowerCase()])),await S({sites:c}),await A()});let o=a("btn-clear-completed");o&&o.addEventListener("click",async()=>{await M(),await w()});let r=a("btn-open-app-header");r&&r.addEventListener("click",async()=>{await y()||p.tabs.create({url:"netwich://open"}).catch(()=>{p.tabs.create({url:"merge://open"}).catch(()=>{})})});let t=a("btn-open-app-footer");t&&t.addEventListener("click",async()=>{await y()||p.tabs.create({url:"netwich://open"}).catch(()=>{p.tabs.create({url:"merge://open"}).catch(()=>{})})});let i=a("btn-open-offline");i&&i.addEventListener("click",async()=>{await y()||p.tabs.create({url:"netwich://open"}).catch(()=>{p.tabs.create({url:"merge://open"}).catch(()=>{})})});let s=a("btn-options");s&&s.addEventListener("click",()=>{p.runtime.openOptionsPage()})}document.addEventListener("DOMContentLoaded",async()=>{G(),await A(),E=setInterval(async()=>{await w()},1e3)});window.addEventListener("unload",()=>{E&&clearInterval(E)});})();
