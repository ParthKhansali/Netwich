(()=>{(function(){if(window!==window.top||window.__netwichHUDInitialized)return;window.__netwichHUDInitialized=!0;let o=null,t=null,f=null,m=null,v=!1,h=!1,w=null;function g(e){return!e||e<=0?"0 B":e>=1073741824?(e/1073741824).toFixed(1)+" GB":e>=1048576?(e/1048576).toFixed(1)+" MB":e>=1024?(e/1024).toFixed(0)+" KB":e+" B"}function C(e){return!e||e<=0?"0 B/s":`${g(e)}/s`}function P(e){let n=e.split(".").pop()?.toLowerCase()||"";return["mp4","mov","webm","mkv","avi"].includes(n)?"\u{1F3AC}":["zip","rar","7z","tar","gz","dmg"].includes(n)?"\u{1F4E6}":["mp3","wav","flac","m4a"].includes(n)?"\u{1F3B5}":["png","jpg","jpeg","webp","svg","gif"].includes(n)?"\u{1F5BC}\uFE0F":["pdf","doc","docx","txt","epub"].includes(n)?"\u{1F4C4}":["exe","pkg","app","iso"].includes(n)?"\u{1F4BF}":"\u26A1"}function A(){if(t&&o&&document.contains(o))return t;let e=document.getElementById("netwich-download-hud-host");if(e)o=e;else{o=document.createElement("div"),o.id="netwich-download-hud-host",o.style.cssText="all: initial; position: fixed; top: 16px; right: 20px; z-index: 2147483647; pointer-events: none;";let s=document.body||document.documentElement;s&&s.appendChild(o)}return o.shadowRoot?(t=o.shadowRoot,t):(t=o.attachShadow({mode:"open"}),t.innerHTML=`
      <style>
        * {
          box-sizing: border-box;
          margin: 0;
          padding: 0;
          font-family: -apple-system, BlinkMacSystemFont, "SF Pro Display", "SF Pro Text", "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
          -webkit-font-smoothing: antialiased;
        }

        .hud-container {
          pointer-events: auto;
          position: relative;
        }

        /* Full Card */
        .hud-card {
          width: 304px;
          border-radius: 16px;
          background: rgba(20, 20, 26, 0.84);
          backdrop-filter: blur(28px) saturate(190%);
          -webkit-backdrop-filter: blur(28px) saturate(190%);
          border: 1px solid rgba(255, 255, 255, 0.14);
          box-shadow: 0 20px 48px rgba(0, 0, 0, 0.55),
                      0 1px 2px rgba(255, 255, 255, 0.18) inset;
          color: #f2f2f7;
          overflow: hidden;
          transition: transform 0.3s cubic-bezier(0.16, 1, 0.3, 1), opacity 0.25s ease, filter 0.25s ease;
          transform: translateY(-16px) scale(0.97);
          opacity: 0;
          display: block;
        }

        .hud-card.visible {
          transform: translateY(0) scale(1);
          opacity: 1;
        }

        .hud-card.minimized {
          display: none !important;
        }

        /* Mini Floating Pill (when minimized) */
        .hud-mini-pill {
          display: none;
          align-items: center;
          gap: 8px;
          padding: 7px 12px;
          border-radius: 20px;
          background: rgba(20, 20, 26, 0.88);
          backdrop-filter: blur(24px) saturate(190%);
          -webkit-backdrop-filter: blur(24px) saturate(190%);
          border: 1px solid rgba(255, 255, 255, 0.16);
          box-shadow: 0 12px 32px rgba(0, 0, 0, 0.45);
          cursor: pointer;
          color: #ffffff;
          font-size: 11.5px;
          font-weight: 500;
          transition: transform 0.2s cubic-bezier(0.16, 1, 0.3, 1), background 0.2s;
        }

        .hud-mini-pill:hover {
          background: rgba(30, 30, 38, 0.95);
          transform: scale(1.03);
        }

        .hud-mini-pill.visible {
          display: flex !important;
        }

        .pill-speed {
          color: #0A84FF;
          font-weight: 600;
        }

        .hud-header {
          display: flex;
          align-items: center;
          justify-content: space-between;
          padding: 10px 12px 8px 12px;
          border-bottom: 1px solid rgba(255, 255, 255, 0.08);
          background: rgba(255, 255, 255, 0.02);
        }

        .hud-brand {
          display: flex;
          align-items: center;
          gap: 6px;
          font-size: 11.5px;
          font-weight: 600;
          color: #a1a1a6;
        }

        .hud-dot {
          width: 7px;
          height: 7px;
          border-radius: 50%;
          background: #30D158;
          box-shadow: 0 0 6px #30D158;
          animation: pulse 2s infinite ease-in-out;
        }

        @keyframes pulse {
          0% { transform: scale(0.95); opacity: 0.8; }
          50% { transform: scale(1.15); opacity: 1; box-shadow: 0 0 10px #30D158; }
          100% { transform: scale(0.95); opacity: 0.8; }
        }

        .hud-controls {
          display: flex;
          align-items: center;
          gap: 2px;
        }

        .hud-btn-icon {
          background: transparent;
          border: none;
          color: #8e8e93;
          font-size: 13px;
          cursor: pointer;
          width: 22px;
          height: 22px;
          display: flex;
          align-items: center;
          justify-content: center;
          border-radius: 6px;
          transition: background 0.15s, color 0.15s;
        }

        .hud-btn-icon:hover {
          background: rgba(255, 255, 255, 0.12);
          color: #ffffff;
        }

        .hud-body {
          padding: 12px;
          display: flex;
          gap: 10px;
        }

        .hud-icon-box {
          width: 38px;
          height: 38px;
          border-radius: 10px;
          background: linear-gradient(135deg, rgba(10, 132, 255, 0.2), rgba(94, 92, 230, 0.15));
          border: 1px solid rgba(10, 132, 255, 0.25);
          display: flex;
          align-items: center;
          justify-content: center;
          font-size: 19px;
          flex-shrink: 0;
        }

        .hud-info {
          flex: 1;
          min-width: 0;
          display: flex;
          flex-direction: column;
          gap: 3px;
        }

        .hud-filename {
          font-size: 12.5px;
          font-weight: 600;
          color: #ffffff;
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }

        .hud-status-line {
          display: flex;
          align-items: center;
          gap: 6px;
          font-size: 11px;
          color: #8e8e93;
        }

        .hud-speed {
          color: #0A84FF;
          font-weight: 600;
          font-feature-settings: "tnum";
        }

        .hud-progress-wrap {
          margin-top: 5px;
          position: relative;
          height: 5px;
          background: rgba(255, 255, 255, 0.1);
          border-radius: 2.5px;
          overflow: hidden;
        }

        .hud-progress-bar {
          height: 100%;
          width: 0%;
          background: linear-gradient(90deg, #0A84FF, #5E5CE6, #30D158);
          border-radius: 2.5px;
          transition: width 0.25s ease;
        }

        .hud-progress-bar.completed {
          background: #30D158;
          box-shadow: 0 0 8px rgba(48, 209, 88, 0.5);
        }

        /* Acceleration Badge Strip */
        .hud-accel-strip {
          margin: 0 12px 6px 12px;
          padding: 4px 8px;
          border-radius: 6px;
          background: rgba(10, 132, 255, 0.1);
          border: 1px solid rgba(10, 132, 255, 0.2);
          display: flex;
          align-items: center;
          justify-content: space-between;
          font-size: 10px;
          color: #0A84FF;
          font-weight: 600;
        }

        .hud-footer {
          padding: 6px 12px 10px 12px;
          display: flex;
          align-items: center;
          justify-content: space-between;
          font-size: 11px;
        }

        .hud-percent {
          font-weight: 600;
          color: #e5e5ea;
          font-feature-settings: "tnum";
        }

        .hud-actions {
          display: flex;
          gap: 6px;
        }

        .hud-btn {
          background: #0A84FF;
          border: 1px solid #0A84FF;
          color: #ffffff;
          font-size: 11px;
          font-weight: 500;
          padding: 4px 10px;
          border-radius: 6px;
          cursor: pointer;
          transition: background 0.15s ease;
        }

        .hud-btn:hover {
          background: #0077ED;
          border-color: #0077ED;
        }
      </style>

      <div class="hud-container" id="container">
        <!-- Full Card -->
        <div class="hud-card" id="card">
          <div class="hud-header">
            <div class="hud-brand">
              <div class="hud-dot" id="dot"></div>
              <span id="header-title">Netwich Download</span>
            </div>
            <div class="hud-controls">
              <button class="hud-btn-icon" id="minimize-btn" title="Minimize to Pill">
                <svg width="10" height="2" viewBox="0 0 10 2" fill="currentColor"><rect width="10" height="2" rx="1"></rect></svg>
              </button>
              <button class="hud-btn-icon" id="close-btn" title="Dismiss">\u2715</button>
            </div>
          </div>

          <div class="hud-body">
            <div class="hud-icon-box" id="file-icon">\u26A1</div>
            <div class="hud-info">
              <div class="hud-filename" id="filename">Preparing download...</div>
              <div class="hud-status-line">
                <span id="status-text">Connecting...</span>
                <span id="dot-sep" style="display:none;">\u2022</span>
                <span class="hud-speed" id="speed" style="display:none;"></span>
              </div>
              <div class="hud-progress-wrap">
                <div class="hud-progress-bar" id="progress-bar"></div>
              </div>
            </div>
          </div>

          <div class="hud-accel-strip" id="accel-strip">
            <span id="accel-label">\u26A1 Multi-Link Turbo</span>
            <span id="accel-detail">8 Parallel Streams</span>
          </div>

          <div class="hud-footer">
            <div class="hud-percent" id="percent">0%</div>
            <div class="hud-actions">
              <button class="hud-btn" id="open-app-btn">Open App</button>
            </div>
          </div>
        </div>

        <!-- Mini Floating Pill -->
        <div class="hud-mini-pill" id="mini-pill" title="Click to expand">
          <span>\u26A1</span>
          <span id="pill-info">Downloading...</span>
          <span class="pill-speed" id="pill-speed"></span>
        </div>
      </div>
    `,t.getElementById("close-btn")?.addEventListener("click",()=>{if(h=!0,f?.id)try{sessionStorage.setItem("netwich_dismissed_"+f.id,"1")}catch{}E()}),t.getElementById("minimize-btn")?.addEventListener("click",()=>{v=!0,B()}),t.getElementById("mini-pill")?.addEventListener("click",()=>{v=!1,B()}),t.getElementById("open-app-btn")?.addEventListener("click",()=>{chrome.runtime.sendMessage({type:"OPEN_APP"})}),t)}function B(){if(!t)return;let e=t.getElementById("card"),n=t.getElementById("mini-pill");v?(e?.classList.add("minimized"),n?.classList.add("visible")):(e?.classList.remove("minimized"),n?.classList.remove("visible"))}function z(e,n=!1){if(h&&w===e.id)return;try{if(sessionStorage.getItem("netwich_dismissed_"+e.id)==="1")return}catch{}if(!n){if(!t)return;let a=t.getElementById("card"),D=t.getElementById("mini-pill");if(!(a?.classList.contains("visible")||D?.classList.contains("visible")))return}w!==e.id&&(h=!1,w=e.id);let i=A();f=e,m&&(clearTimeout(m),m=null);let F=i.getElementById("card"),k=i.getElementById("filename"),s=i.getElementById("status-text"),l=i.getElementById("speed"),d=i.getElementById("dot-sep"),r=i.getElementById("progress-bar"),x=i.getElementById("percent"),S=i.getElementById("file-icon"),c=i.getElementById("header-title"),p=i.getElementById("dot"),u=i.getElementById("accel-strip"),b=i.getElementById("accel-label"),y=i.getElementById("accel-detail"),_=i.getElementById("pill-info"),L=i.getElementById("pill-speed");k&&(k.textContent=e.filename),S&&(S.textContent=P(e.filename));let I=Math.min(100,Math.max(0,Math.round((e.progress||0)*100)));if(x&&(x.textContent=`${I}%`),r&&(r.style.width=`${I}%`),_){let a=g(e.downloadedBytes);_.textContent=`${a} (${I}%)`}if(L&&(L.textContent=e.speedBytesPerSec>0?C(e.speedBytesPerSec):""),e.isCompleted||e.status==="completed")c&&(c.textContent="Download Complete"),s&&(s.textContent=`Saved (${g(e.totalBytes)})`),l&&(l.style.display="none"),d&&(d.style.display="none"),u&&(u.style.display="none"),p&&(p.style.background="#30D158",p.style.boxShadow="0 0 10px #30D158"),r&&(r.classList.add("completed"),r.style.width="100%"),x&&(x.textContent="100%"),m=setTimeout(()=>{if(h=!0,f?.id)try{sessionStorage.setItem("netwich_dismissed_"+f.id,"1")}catch{}E()},4e3);else if(e.status==="failed")c&&(c.textContent="Download Failed"),s&&(s.textContent="Network connection lost"),l&&(l.style.display="none"),d&&(d.style.display="none"),u&&(u.style.display="none"),p&&(p.style.background="#FF453A",p.style.boxShadow="0 0 8px #FF453A");else{if(c&&(c.textContent="Netwich Accelerating"),r&&r.classList.remove("completed"),e.totalBytes>0){let a=g(e.downloadedBytes),D=g(e.totalBytes);s&&(s.textContent=`${a} of ${D}`)}else s&&(s.textContent="Chunking & accelerating...");if(e.speedBytesPerSec>0?(l&&(l.textContent=C(e.speedBytesPerSec),l.style.display="inline"),d&&(d.style.display="inline")):(l&&(l.style.display="none"),d&&(d.style.display="none")),u){u.style.display="flex";let a=e.linksCount||1;a>=2?(b&&(b.textContent=`\u26A1 Multi-Link (${a} Adapters \xB7 1.8x Speed)`),y&&(y.textContent="+80% Throughput")):(b&&(b.textContent="\u26A1 Turbo Multi-Stream"),y&&(y.textContent="8 Parallel Chunks"))}}F?.classList.add("visible"),B()}function E(){if(!t)return;let e=t.getElementById("card"),n=t.getElementById("mini-pill");e?.classList.remove("visible"),n?.classList.remove("visible")}chrome.runtime.onMessage.addListener((e,n,i)=>{e.type==="NETWICH_SHOW_DOWNLOAD"?e.download&&(z(e.download,!0),i({success:!0})):e.type==="NETWICH_DOWNLOAD_PROGRESS"?e.download&&(z(e.download,!1),i({success:!0})):e.type==="NETWICH_HIDE_DOWNLOAD"&&(E(),i({success:!0}))})})();})();
