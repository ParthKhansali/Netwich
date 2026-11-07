#!/usr/bin/env python3
"""
Generates Nothing Tech / Dot-Matrix styled architectural and technical diagrams
for Netwich documentation and repository presentation.

Uses embedded NDot57 (Nothing dot-matrix typeface) and NType82Mono (clean technical mono)
with smoked glass cards, LED status indicators, and precision industrial layout.
"""

import os
import base64
import subprocess
from PIL import Image

FONTS_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fonts")
ASSETS_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "docs", "assets")

def load_fonts():
    ndot_path = os.path.join(FONTS_DIR, "Ndot57-Regular.otf")
    mono_path = os.path.join(FONTS_DIR, "NType82Mono-Regular.otf")
    
    with open(ndot_path, "rb") as f:
        b64_ndot = base64.b64encode(f.read()).decode("ascii")
    with open(mono_path, "rb") as f:
        b64_mono = base64.b64encode(f.read()).decode("ascii")
        
    return b64_ndot, b64_mono

B64_NDOT, B64_MONO = load_fonts()

def shared_defs():
    return f"""<defs>
  <style>
  /* <![CDATA[ */
    @font-face {{
      font-family: 'NDot57';
      src: url('data:font/opentype;base64,{B64_NDOT}') format('opentype');
    }}
    @font-face {{
      font-family: 'NType82Mono';
      src: url('data:font/opentype;base64,{B64_MONO}') format('opentype');
    }}
    .ndot-title {{ font-family: 'NDot57', monospace; font-size: 22px; fill: #FFFFFF; letter-spacing: 1.5px; }}
    .ndot-head  {{ font-family: 'NDot57', monospace; font-size: 15px; fill: #FFFFFF; letter-spacing: 1px; }}
    .ndot-stat  {{ font-family: 'NDot57', monospace; font-size: 24px; letter-spacing: 1px; }}
    .mono-body  {{ font-family: 'NType82Mono', ui-monospace, monospace; font-size: 12px; fill: #94A3B8; letter-spacing: 0.5px; }}
    .mono-code  {{ font-family: 'NType82Mono', ui-monospace, monospace; font-size: 11px; fill: #E2E8F0; }}
    .tag        {{ font-family: 'NDot57', monospace; font-size: 10px; letter-spacing: 1px; }}
  /* ]]> */
  </style>
  <pattern id="dot-grid" width="24" height="24" patternUnits="userSpaceOnUse">
    <circle cx="12" cy="12" r="1" fill="#1E293B" opacity="0.65" />
  </pattern>
</defs>"""

def corner_crosshairs(x, y, w, h, stroke="#475569"):
    crosses = []
    for cx, cy in [(x, y), (x + w, y), (x, y + h), (x + w, y + h)]:
        crosses.append(f'<path d="M {cx-5} {cy} L {cx+5} {cy} M {cx} {cy-5} L {cx} {cy+5}" stroke="{stroke}" stroke-width="1.2" />')
    return "\n".join(crosses)

def create_architecture_diagram():
    w, h = 980, 530
    svg = []
    svg.append(f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" width="100%" height="auto" style="background: #080A0F; border-radius: 12px;">')
    svg.append(shared_defs())
    svg.append(f'<rect width="{w}" height="{h}" rx="12" fill="#080A0F" />')
    svg.append(f'<rect width="{w}" height="{h}" rx="12" fill="url(#dot-grid)" />')
    
    # Outer frame
    svg.append(f'<rect x="12" y="12" width="{w-24}" height="{h-24}" rx="10" fill="none" stroke="#1E293B" stroke-width="1.5" />')
    svg.append(corner_crosshairs(12, 12, w - 24, h - 24))
    
    # Header
    svg.append(f'<circle cx="42" cy="42" r="4" fill="#FF3B30" />')
    svg.append(f'<text x="54" y="46" class="tag" fill="#FF3B30">SPEC 01 // ARCHITECTURE</text>')
    svg.append(f'<text x="42" y="74" class="ndot-title">NETWICH SOCKET BINDING ARCHITECTURE</text>')
    svg.append(f'<text x="42" y="96" class="mono-body">DYNAMIC FLOW SCHEDULING • DUAL INTERFACE AGGREGATION • 100% LOCAL MAC KERNEL</text>')
    
    # Card 1: Applications (Left)
    svg.append(f'<rect x="42" y="120" width="225" height="245" rx="8" fill="rgba(15, 23, 42, 0.75)" stroke="#334155" stroke-width="1" />')
    svg.append(f'<rect x="42" y="120" width="225" height="30" rx="8" fill="rgba(30, 41, 59, 0.5)" />')
    svg.append(f'<circle cx="58" cy="135" r="3" fill="#38BDF8" />')
    svg.append(f'<text x="68" y="139" class="tag" fill="#93C5FD">SOURCE LAYER</text>')
    svg.append(f'<text x="58" y="174" class="ndot-head">LOCAL APPS</text>')
    svg.append(f'<text x="58" y="202" class="mono-code">[01] Safari / Chrome</text>')
    svg.append(f'<text x="58" y="224" class="mono-code">[02] curl / git / brew</text>')
    svg.append(f'<text x="58" y="246" class="mono-code">[03] Netwich Engine</text>')
    svg.append(f'<line x1="58" y1="268" x2="248" y2="268" stroke="#334155" stroke-dasharray="3,3" />')
    svg.append(f'<text x="58" y="292" class="mono-body" fill="#64748B">System SOCKS5 Proxy</text>')
    svg.append(f'<text x="58" y="314" class="ndot-head" font-size="14" fill="#38BDF8">127.0.0.1:1080</text>')
    svg.append(f'<text x="58" y="334" class="mono-body" fill="#64748B">Zero Config Handshake</text>')
    
    # Arrow 1: Apps -> Hub
    svg.append(f'<path d="M 267 242 L 348 242" stroke="#38BDF8" stroke-width="2" stroke-dasharray="4,3" />')
    svg.append(f'<polygon points="348,238 356,242 348,246" fill="#38BDF8" />')
    svg.append(f'<rect x="278" y="223" width="62" height="18" rx="4" fill="#080A0F" stroke="#38BDF8" stroke-width="1" />')
    svg.append(f'<text x="309" y="235" class="tag" fill="#38BDF8" text-anchor="middle">TCP FLOW</text>')
    
    # Card 2: Core Hub (Center)
    svg.append(f'<rect x="356" y="120" width="280" height="245" rx="8" fill="rgba(15, 23, 42, 0.85)" stroke="#38BDF8" stroke-width="1.5" />')
    svg.append(f'<rect x="356" y="120" width="280" height="30" rx="8" fill="rgba(56, 189, 248, 0.12)" />')
    svg.append(f'<circle cx="374" cy="135" r="3" fill="#38BDF8" />')
    svg.append(f'<text x="384" y="139" class="tag" fill="#38BDF8">NETWICH CORE ENGINE</text>')
    svg.append(f'<text x="374" y="174" class="ndot-head">DYNAMIC SCHEDULER</text>')
    
    stages = [
        ("WEIGHTED LEAST-CONNS", "Load balancing across active links", "#38BDF8"),
        ("EWMA LATENCY SENSING", "Real-time RTT &amp; throughput probes", "#10B981"),
        ("IP_BOUND_IF CONTROL", "Kernel-level per-socket route bind", "#A855F7")
    ]
    sy = 194
    for stitle, sdesc, scol in stages:
        svg.append(f'<rect x="374" y="{sy}" width="244" height="42" rx="5" fill="rgba(30, 41, 59, 0.6)" stroke="{scol}" stroke-width="0.8" />')
        svg.append(f'<circle cx="386" cy="{sy+15}" r="2.5" fill="{scol}" />')
        svg.append(f'<text x="395" y="{sy+18}" class="ndot-head" font-size="11" fill="{scol}">{stitle}</text>')
        svg.append(f'<text x="395" y="{sy+32}" class="mono-body" font-size="10" fill="#94A3B8">{sdesc}</text>')
        sy += 48
        
    # Flow α (to Wi-Fi)
    svg.append(f'<path d="M 636 170 C 665 170, 675 155, 706 155" fill="none" stroke="#38BDF8" stroke-width="2" />')
    svg.append(f'<polygon points="706,151 714,155 706,159" fill="#38BDF8" />')
    svg.append(f'<rect x="652" y="142" width="46" height="15" rx="3" fill="#080A0F" stroke="#38BDF8" stroke-width="0.8" />')
    svg.append(f'<text x="675" y="153" class="tag" fill="#38BDF8" text-anchor="middle">FLOW α</text>')
    
    # Flow β (to 5G)
    svg.append(f'<path d="M 636 310 C 665 310, 675 325, 706 325" fill="none" stroke="#10B981" stroke-width="2" />')
    svg.append(f'<polygon points="706,321 714,325 706,329" fill="#10B981" />')
    svg.append(f'<rect x="652" y="300" width="46" height="15" rx="3" fill="#080A0F" stroke="#10B981" stroke-width="0.8" />')
    svg.append(f'<text x="675" y="311" class="tag" fill="#10B981" text-anchor="middle">FLOW β</text>')
    
    # Card 3: Adapter 01 (Wi-Fi en0)
    svg.append(f'<rect x="714" y="120" width="224" height="110" rx="8" fill="rgba(15, 23, 42, 0.75)" stroke="#38BDF8" stroke-width="1" />')
    svg.append(f'<rect x="714" y="120" width="224" height="28" rx="8" fill="rgba(56, 189, 248, 0.15)" />')
    svg.append(f'<circle cx="730" cy="134" r="3" fill="#38BDF8" />')
    svg.append(f'<text x="740" y="138" class="tag" fill="#38BDF8">ADAPTER 01 // WI-FI</text>')
    svg.append(f'<text x="730" y="172" class="ndot-stat" fill="#38BDF8">85 MBPS</text>')
    svg.append(f'<text x="730" y="196" class="mono-code">INTERFACE: en0 • RTT: 18ms</text>')
    svg.append(f'<text x="730" y="215" class="mono-body" font-size="10">STATUS: ACTIVE (WEIGHT 1.0)</text>')
    
    # Card 4: Adapter 02 (Tether en5)
    svg.append(f'<rect x="714" y="255" width="224" height="110" rx="8" fill="rgba(15, 23, 42, 0.75)" stroke="#10B981" stroke-width="1" />')
    svg.append(f'<rect x="714" y="255" width="224" height="28" rx="8" fill="rgba(16, 185, 129, 0.15)" />')
    svg.append(f'<circle cx="730" cy="269" r="3" fill="#10B981" />')
    svg.append(f'<text x="740" y="273" class="tag" fill="#10B981">ADAPTER 02 // 5G TETHER</text>')
    svg.append(f'<text x="730" y="307" class="ndot-stat" fill="#10B981">110 MBPS</text>')
    svg.append(f'<text x="730" y="331" class="mono-code">INTERFACE: en5 • RTT: 22ms</text>')
    svg.append(f'<text x="730" y="350" class="mono-body" font-size="10">STATUS: ACTIVE (WEIGHT 1.3)</text>')
    
    # Downward route lines from Adapters to Bottom Aggregated Bar
    svg.append(f'<path d="M 826 230 L 826 385" stroke="#38BDF8" stroke-width="1.5" stroke-dasharray="3,3" opacity="0.6" />')
    svg.append(f'<path d="M 826 365 L 826 385" stroke="#10B981" stroke-width="1.5" stroke-dasharray="3,3" opacity="0.6" />')
    
    # Bottom Unified Bar
    svg.append(f'<rect x="42" y="385" width="896" height="108" rx="8" fill="rgba(15, 23, 42, 0.9)" stroke="#F59E0B" stroke-width="1.5" />')
    svg.append(f'<circle cx="62" cy="406" r="3.5" fill="#F59E0B" />')
    svg.append(f'<text x="74" y="410" class="tag" fill="#F59E0B">COMBINED AGGREGATED OUTPUT</text>')
    svg.append(f'<text x="62" y="445" class="ndot-stat" font-size="28" fill="#FBBF24">195 MBPS TOTAL BANDWIDTH</text>')
    svg.append(f'<text x="62" y="472" class="mono-body">CONCURRENT MULTI-STREAM FLOW DISPATCH • 80MS EWMA FAILOVER • ZERO INTERNET CLOUD RELAY</text>')
    
    # High-tech Badges on bottom right
    bx = 648
    svg.append(f'<rect x="{bx}" y="{425}" width="95" height="26" rx="4" fill="rgba(56, 189, 248, 0.12)" stroke="#38BDF8" stroke-width="1" />')
    svg.append(f'<text x="{bx+47}" y="{442}" class="tag" fill="#38BDF8" text-anchor="middle">100% LOCAL</text>')
    
    bx = 752
    svg.append(f'<rect x="{bx}" y="{425}" width="90" height="26" rx="4" fill="rgba(16, 185, 129, 0.12)" stroke="#10B981" stroke-width="1" />')
    svg.append(f'<text x="{bx+45}" y="{442}" class="tag" fill="#10B981" text-anchor="middle">ZERO RELAY</text>')
    
    bx = 851
    svg.append(f'<rect x="{bx}" y="{425}" width="72" height="26" rx="4" fill="rgba(245, 158, 11, 0.12)" stroke="#F59E0B" stroke-width="1" />')
    svg.append(f'<text x="{bx+36}" y="{442}" class="tag" fill="#F59E0B" text-anchor="middle">&lt;80MS</text>')
    
    svg.append('</svg>')
    return "\n".join(svg)

def create_chunked_download_diagram():
    w, h = 980, 480
    svg = []
    svg.append(f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" width="100%" height="auto" style="background: #080A0F; border-radius: 12px;">')
    svg.append(shared_defs())
    svg.append(f'<rect width="{w}" height="{h}" rx="12" fill="#080A0F" />')
    svg.append(f'<rect width="{w}" height="{h}" rx="12" fill="url(#dot-grid)" />')
    
    # Outer frame
    svg.append(f'<rect x="12" y="12" width="{w-24}" height="{h-24}" rx="10" fill="none" stroke="#1E293B" stroke-width="1.5" />')
    svg.append(corner_crosshairs(12, 12, w - 24, h - 24))
    
    # Header
    svg.append(f'<circle cx="42" cy="42" r="4" fill="#34D399" />')
    svg.append(f'<text x="54" y="46" class="tag" fill="#34D399">SPEC 02 // MULTI-LINK ACCELERATION</text>')
    svg.append(f'<text x="42" y="74" class="ndot-title">PARALLEL CHUNKED DOWNLOAD PIPELINE</text>')
    svg.append(f'<text x="42" y="96" class="mono-body">DYNAMIC BYTE-RANGE CONCURRENT STREAMS ACROSS INDEPENDENT PHYSICAL ADAPTERS</text>')
    
    # Top Panel: Standard Single Link (Slow)
    svg.append(f'<rect x="42" y="118" width="896" height="130" rx="8" fill="rgba(15, 23, 42, 0.75)" stroke="#334155" stroke-width="1" />')
    svg.append(f'<rect x="42" y="118" width="896" height="28" rx="8" fill="rgba(30, 41, 59, 0.5)" />')
    svg.append(f'<circle cx="58" cy="132" r="3" fill="#EF4444" />')
    svg.append(f'<text x="68" y="136" class="tag" fill="#FCA5A5">TRADITIONAL SINGLE LINK // BOTTLENECKED</text>')
    svg.append(f'<text x="58" y="168" class="ndot-head" font-size="14" fill="#E2E8F0">1X WI-FI ADAPTER (en0) @ 45 MBPS</text>')
    svg.append(f'<text x="58" y="188" class="mono-code">SINGLE SEQUENTIAL STREAM • 2.4 GB ARCHIVE • CONGESTION RESTRICTED</text>')
    
    # Progress Bar (Single slow stream)
    svg.append(f'<rect x="58" y="202" width="590" height="28" rx="5" fill="rgba(30, 41, 59, 0.6)" stroke="#475569" stroke-width="1" />')
    svg.append(f'<rect x="58" y="202" width="200" height="28" rx="5" fill="rgba(56, 189, 248, 0.35)" />')
    svg.append(f'<text x="158" y="221" class="tag" fill="#FFFFFF" text-anchor="middle">34% [SINGLE STREAM]</text>')
    
    # Time readout right
    svg.append(f'<text x="670" y="224" class="ndot-stat" font-size="24" fill="#F87171">11M 40S</text>')
    svg.append(f'<rect x="800" y="205" width="120" height="22" rx="4" fill="rgba(239, 68, 68, 0.15)" stroke="#EF4444" stroke-width="1" />')
    svg.append(f'<text x="860" y="220" class="tag" fill="#F87171" text-anchor="middle">BOTTLENECKED</text>')
    
    # Bottom Panel: Netwich Parallel Multi-Link
    svg.append(f'<rect x="42" y="262" width="896" height="190" rx="8" fill="rgba(15, 23, 42, 0.85)" stroke="#10B981" stroke-width="1.5" />')
    svg.append(f'<rect x="42" y="262" width="896" height="28" rx="8" fill="rgba(16, 185, 129, 0.15)" />')
    svg.append(f'<circle cx="58" cy="276" r="3" fill="#10B981" />')
    svg.append(f'<text x="68" y="280" class="tag" fill="#6EE7B7">NETWICH MULTI-LINK CHUNKING // ACCELERATED</text>')
    svg.append(f'<text x="58" y="312" class="ndot-head" font-size="14" fill="#6EE7B7">WI-FI (45 MBPS) + 5G TETHER (85 MBPS) = 130 MBPS COMBINED</text>')
    
    # 4 Parallel Chunk Boxes
    chunks = [
        ("CHUNK 01", "0000M - 0600M", "en0 [WI-FI]", "#38BDF8"),
        ("CHUNK 02", "0600M - 1200M", "en5 [5G TETHER]", "#10B981"),
        ("CHUNK 03", "1200M - 1800M", "en0 [WI-FI]", "#38BDF8"),
        ("CHUNK 04", "1800M - 2400M", "en5 [5G TETHER]", "#10B981")
    ]
    cx = 58
    c_w = 138
    c_gap = 12
    for ctitle, crange, cdev, ccolor in chunks:
        svg.append(f'<rect x="{cx}" y="328" width="{c_w}" height="56" rx="6" fill="rgba(30, 41, 59, 0.7)" stroke="{ccolor}" stroke-width="1" />')
        svg.append(f'<text x="{cx+10}" y="347" class="tag" fill="{ccolor}">{ctitle}</text>')
        svg.append(f'<text x="{cx+10}" y="362" class="mono-code" font-size="9">{crange}</text>')
        svg.append(f'<text x="{cx+10}" y="376" class="tag" font-size="9" fill="{ccolor}">{cdev}</text>')
        cx += c_w + c_gap
        
    # Time readout right
    svg.append(f'<text x="670" y="360" class="ndot-stat" font-size="26" fill="#34D399">04M 05S</text>')
    svg.append(f'<rect x="800" y="340" width="120" height="26" rx="4" fill="rgba(16, 185, 129, 0.2)" stroke="#10B981" stroke-width="1" />')
    svg.append(f'<text x="860" y="357" class="tag" fill="#34D399" text-anchor="middle">2.8X SPEEDUP</text>')
    
    # Technical footer
    svg.append(f'<line x1="58" y1="400" x2="922" y2="400" stroke="#334155" stroke-dasharray="3,3" />')
    svg.append(f'<text x="58" y="425" class="mono-body" fill="#FCD34D">[•] HTTP ACCEPT-RANGES PROBING  [•] SPARSE DISK PRE-ALLOCATION  [•] ZERO RAM SPIKES  [•] SHA-256 INTEGRITY</text>')
    
    svg.append('</svg>')
    return "\n".join(svg)

def create_failover_diagram():
    w, h = 980, 470
    svg = []
    svg.append(f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" width="100%" height="auto" style="background: #080A0F; border-radius: 12px;">')
    svg.append(shared_defs())
    svg.append(f'<rect width="{w}" height="{h}" rx="12" fill="#080A0F" />')
    svg.append(f'<rect width="{w}" height="{h}" rx="12" fill="url(#dot-grid)" />')
    
    # Outer frame
    svg.append(f'<rect x="12" y="12" width="{w-24}" height="{h-24}" rx="10" fill="none" stroke="#1E293B" stroke-width="1.5" />')
    svg.append(corner_crosshairs(12, 12, w - 24, h - 24))
    
    # Header
    svg.append(f'<circle cx="42" cy="42" r="4" fill="#FBBF24" />')
    svg.append(f'<text x="54" y="46" class="tag" fill="#FBBF24">SPEC 03 // FAULT TOLERANCE</text>')
    svg.append(f'<text x="42" y="74" class="ndot-title">ZERO-DROP RESILIENT FAILOVER TIMELINE</text>')
    svg.append(f'<text x="42" y="96" class="mono-body">SUB-100MS CONNECTION DRIFT SENSING WITHOUT TERMINATING ACTIVE TCP FLOWS</text>')
    
    col_w = 268
    col_y = 118
    col_h = 250
    
    # Phase 01: Dual Active
    p1_x = 42
    svg.append(f'<rect x="{p1_x}" y="{col_y}" width="{col_w}" height="{col_h}" rx="8" fill="rgba(15, 23, 42, 0.75)" stroke="#38BDF8" stroke-width="1.2" />')
    svg.append(f'<rect x="{p1_x}" y="{col_y}" width="{col_w}" height="28" rx="8" fill="rgba(56, 189, 248, 0.15)" />')
    svg.append(f'<circle cx="{p1_x+16}" cy="{col_y+14}" r="3" fill="#38BDF8" />')
    svg.append(f'<text x="{p1_x+26}" y="{col_y+18}" class="tag" fill="#93C5FD">PHASE 01 // DUAL ACTIVE</text>')
    svg.append(f'<text x="{p1_x+16}" y="{col_y+54}" class="ndot-stat" font-size="20" fill="#38BDF8">BALANCED 50/50</text>')
    svg.append(f'<text x="{p1_x+16}" y="{col_y+84}" class="mono-code">• Wi-Fi (en0): 18ms [OK]</text>')
    svg.append(f'<text x="{p1_x+16}" y="{col_y+108}" class="mono-code">• Tether (en5): 22ms [OK]</text>')
    svg.append(f'<line x1="{p1_x+16}" y1="{col_y+128}" x2="{p1_x+col_w-16}" y2="{col_y+128}" stroke="#334155" stroke-dasharray="3,3" />')
    svg.append(f'<text x="{p1_x+16}" y="{col_y+152}" class="mono-body">Combined: 195 Mbps Total</text>')
    svg.append(f'<text x="{p1_x+16}" y="{col_y+174}" class="mono-body">EWMA Latency: Nominal</text>')
    svg.append(f'<rect x="{p1_x+16}" y="{col_y+200}" width="{col_w-32}" height="26" rx="4" fill="rgba(56, 189, 248, 0.1)" stroke="#38BDF8" stroke-width="0.8" />')
    svg.append(f'<text x="{p1_x+col_w//2}" y="{col_y+217}" class="tag" fill="#38BDF8" text-anchor="middle">STATUS: NOMINAL</text>')
    
    # Arrow 1 -> 2
    svg.append(f'<path d="M {p1_x+col_w+4} {col_y+125} L {p1_x+col_w+40} {col_y+125}" stroke="#EF4444" stroke-width="1.8" stroke-dasharray="3,3" />')
    svg.append(f'<polygon points="{p1_x+col_w+40},{col_y+121} {p1_x+col_w+46},{col_y+125} {p1_x+col_w+40},{col_y+129}" fill="#EF4444" />')
    svg.append(f'<text x="{p1_x+col_w+23}" y="{col_y+115}" class="tag" fill="#EF4444" text-anchor="middle" font-size="9">DROP</text>')
    
    # Phase 02: Wi-Fi Drop
    p2_x = p1_x + col_w + 46
    svg.append(f'<rect x="{p2_x}" y="{col_y}" width="{col_w}" height="{col_h}" rx="8" fill="rgba(15, 23, 42, 0.75)" stroke="#EF4444" stroke-width="1.2" />')
    svg.append(f'<rect x="{p2_x}" y="{col_y}" width="{col_w}" height="28" rx="8" fill="rgba(239, 68, 68, 0.15)" />')
    svg.append(f'<circle cx="{p2_x+16}" cy="{col_y+14}" r="3" fill="#EF4444" />')
    svg.append(f'<text x="{p2_x+26}" y="{col_y+18}" class="tag" fill="#FCA5A5">PHASE 02 // SIGNAL DROP</text>')
    svg.append(f'<text x="{p2_x+16}" y="{col_y+54}" class="ndot-stat" font-size="20" fill="#EF4444">80MS SENSING</text>')
    svg.append(f'<text x="{p2_x+16}" y="{col_y+84}" class="mono-code" fill="#F87171">✕ Wi-Fi (en0): Disconnected</text>')
    svg.append(f'<text x="{p2_x+16}" y="{col_y+108}" class="mono-code">• Tether (en5): Active</text>')
    svg.append(f'<line x1="{p2_x+16}" y1="{col_y+128}" x2="{p2_x+col_w-16}" y2="{col_y+128}" stroke="#334155" stroke-dasharray="3,3" />')
    svg.append(f'<text x="{p2_x+16}" y="{col_y+152}" class="mono-body">Weight en0 reset to 0.0</text>')
    svg.append(f'<text x="{p2_x+16}" y="{col_y+174}" class="mono-body">In-flight re-routed</text>')
    svg.append(f'<rect x="{p2_x+16}" y="{col_y+200}" width="{col_w-32}" height="26" rx="4" fill="rgba(239, 68, 68, 0.1)" stroke="#EF4444" stroke-width="0.8" />')
    svg.append(f'<text x="{p2_x+col_w//2}" y="{col_y+217}" class="tag" fill="#EF4444" text-anchor="middle">ZERO SOCKET RESETS</text>')
    
    # Arrow 2 -> 3
    svg.append(f'<path d="M {p2_x+col_w+4} {col_y+125} L {p2_x+col_w+40} {col_y+125}" stroke="#10B981" stroke-width="1.8" />')
    svg.append(f'<polygon points="{p2_x+col_w+40},{col_y+121} {p2_x+col_w+46},{col_y+125} {p2_x+col_w+40},{col_y+129}" fill="#10B981" />')
    svg.append(f'<text x="{p2_x+col_w+23}" y="{col_y+115}" class="tag" fill="#10B981" text-anchor="middle" font-size="9">SHIFT</text>')
    
    # Phase 03: Seamless Recovery
    p3_x = p2_x + col_w + 46
    svg.append(f'<rect x="{p3_x}" y="{col_y}" width="{col_w}" height="{col_h}" rx="8" fill="rgba(15, 23, 42, 0.75)" stroke="#10B981" stroke-width="1.2" />')
    svg.append(f'<rect x="{p3_x}" y="{col_y}" width="{col_w}" height="28" rx="8" fill="rgba(16, 185, 129, 0.15)" />')
    svg.append(f'<circle cx="{p3_x+16}" cy="{col_y+14}" r="3" fill="#10B981" />')
    svg.append(f'<text x="{p3_x+26}" y="{col_y+18}" class="tag" fill="#6EE7B7">PHASE 03 // FULL FALLBACK</text>')
    svg.append(f'<text x="{p3_x+16}" y="{col_y+54}" class="ndot-stat" font-size="20" fill="#10B981">100% PRESERVED</text>')
    svg.append(f'<text x="{p3_x+16}" y="{col_y+84}" class="mono-code" fill="#6EE7B7">✓ Tether (en5): 100% Load</text>')
    svg.append(f'<text x="{p3_x+16}" y="{col_y+108}" class="mono-code">✓ All TCP sockets alive</text>')
    svg.append(f'<line x1="{p3_x+16}" y1="{col_y+128}" x2="{p3_x+col_w-16}" y2="{col_y+128}" stroke="#334155" stroke-dasharray="3,3" />')
    svg.append(f'<text x="{p3_x+16}" y="{col_y+152}" class="mono-body">Zero download aborts</text>')
    svg.append(f'<text x="{p3_x+16}" y="{col_y+174}" class="mono-body">Auto-resumes en0 on return</text>')
    svg.append(f'<rect x="{p3_x+16}" y="{col_y+200}" width="{col_w-32}" height="26" rx="4" fill="rgba(16, 185, 129, 0.1)" stroke="#10B981" stroke-width="0.8" />')
    svg.append(f'<text x="{p3_x+col_w//2}" y="{col_y+217}" class="tag" fill="#10B981" text-anchor="middle">ZERO SESSION DROPS</text>')
    
    # Bottom Summary Bar
    svg.append(f'<rect x="42" y="386" width="896" height="64" rx="8" fill="rgba(15, 23, 42, 0.9)" stroke="#334155" stroke-width="1.2" />')
    svg.append(f'<circle cx="62" cy="406" r="3.5" fill="#FBBF24" />')
    svg.append(f'<text x="74" y="410" class="tag" fill="#FCD34D">HIGH-RESILIENCY GUARANTEE</text>')
    svg.append(f'<text x="62" y="434" class="mono-body" fill="#E2E8F0">ACTIVE DOWNLOADS NEVER RESET • REAL-TIME CALLS NEVER TERMINATE • NO KERNEL PANICS</text>')
    
    svg.append('</svg>')
    return "\n".join(svg)

def render_png(svg_path, png_path, target_w, target_h):
    tmp_dir = "/tmp/netwich_render"
    os.makedirs(tmp_dir, exist_ok=True)
    subprocess.run(["qlmanage", "-t", "-s", "1920", "-o", tmp_dir, svg_path], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    base_name = os.path.basename(svg_path)
    rendered_png = os.path.join(tmp_dir, f"{base_name}.png")
    
    if os.path.exists(rendered_png):
        img = Image.open(rendered_png)
        # Crop letterboxing if any:
        # qlmanage produces square 1920x1920 image centered with the SVG at top
        aspect = target_w / target_h
        calc_h = int(1920 / aspect)
        cropped = img.crop((0, 0, 1920, calc_h))
        cropped.save(png_path, "PNG", optimize=True)
        print(f"Generated PNG: {png_path} ({cropped.size[0]}x{cropped.size[1]})")

def main():
    os.makedirs(ASSETS_DIR, exist_ok=True)
    
    files = [
        ("netwich-architecture.svg", "netwich-architecture.png", create_architecture_diagram(), 980, 530),
        ("netwich-chunked-downloads.svg", "netwich-chunked-downloads.png", create_chunked_download_diagram(), 980, 480),
        ("netwich-failover.svg", "netwich-failover.png", create_failover_diagram(), 980, 470)
    ]
    
    for svg_name, png_name, svg_content, tw, th in files:
        svg_path = os.path.join(ASSETS_DIR, svg_name)
        png_path = os.path.join(ASSETS_DIR, png_name)
        
        with open(svg_path, "w", encoding="utf-8") as f:
            f.write(svg_content)
        print(f"Generated SVG: {svg_path}")
        
        render_png(svg_path, png_path, tw, th)

if __name__ == "__main__":
    main()
