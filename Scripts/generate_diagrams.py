#!/usr/bin/env python3
"""
Generates aesthetic, hand-drawn (Excalidraw / whiteboard blueprint style)
vector diagrams for Netwich documentation and repository presentation.
"""

import math
import os
import random

class Sketch:
    def __init__(self, seed=42):
        self.rng = random.Random(seed)

    def jitter(self, val, amount=1.5):
        return val + self.rng.uniform(-amount, amount)

    def rough_line(self, x1, y1, x2, y2, stroke="#F0F6FC", width=2.0, roughness=1.3, opacity=0.92, dash=""):
        paths = []
        for i in range(2):
            dx = x2 - x1
            dy = y2 - y1
            dist = math.hypot(dx, dy)
            bow = self.rng.uniform(-roughness * 2.0, roughness * 2.0)
            nx = -dy / max(dist, 1)
            ny = dx / max(dist, 1)
            mid_x = (x1 + x2) / 2 + nx * bow
            mid_y = (y1 + y2) / 2 + ny * bow
            
            overshoot = self.rng.uniform(-2, 2.5)
            sx = x1 + self.rng.uniform(-roughness, roughness)
            sy = y1 + self.rng.uniform(-roughness, roughness)
            ex = x2 + (dx / max(dist, 1)) * overshoot
            ey = y2 + (dy / max(dist, 1)) * overshoot
            paths.append(f"M {sx:.1f},{sy:.1f} Q {mid_x:.1f},{mid_y:.1f} {ex:.1f},{ey:.1f}")
        
        d = " ".join(paths)
        dash_attr = f' stroke-dasharray="{dash}"' if dash else ""
        return f'<path d="{d}" fill="none" stroke="{stroke}" stroke-width="{width}" stroke-linecap="round" stroke-linejoin="round" opacity="{opacity}"{dash_attr} />'

    def rough_rect(self, x, y, w, h, stroke="#F0F6FC", fill="rgba(255,255,255,0.04)", width=2.0, rx=10, roughness=1.4):
        bg_rect = f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{rx}" fill="{fill}" />'
        e1 = self.rough_line(x + rx, y, x + w - rx, y, stroke, width, roughness)
        e2 = self.rough_line(x + w, y + rx, x + w, y + h - rx, stroke, width, roughness)
        e3 = self.rough_line(x + w - rx, y + h, x + rx, y + h, stroke, width, roughness)
        e4 = self.rough_line(x, y + h - rx, x, y + rx, stroke, width, roughness)
        c1 = f'M {x},{y+rx} Q {x},{y} {x+rx},{y}'
        c2 = f'M {x+w-rx},{y} Q {x+w},{y} {x+w},{y+rx}'
        c3 = f'M {x+w},{y+h-rx} Q {x+w},{y+h} {x+w-rx},{y+h}'
        c4 = f'M {x+rx},{y+h} Q {x},{y+h} {x},{y+h-rx}'
        corners = f'<path d="{c1} {c2} {c3} {c4}" fill="none" stroke="{stroke}" stroke-width="{width*0.8}" stroke-linecap="round" opacity="0.85" />'
        return f"{bg_rect}\n  {e1}\n  {e2}\n  {e3}\n  {e4}\n  {corners}"

    def rough_arrow(self, x1, y1, x2, y2, stroke="#F0F6FC", width=2.0, curvature=0.0, label="", label_dy=-12):
        dx = x2 - x1
        dy = y2 - y1
        dist = math.hypot(dx, dy)
        nx = -dy / max(dist, 1)
        ny = dx / max(dist, 1)
        mid_x = (x1 + x2) / 2 + nx * curvature
        mid_y = (y1 + y2) / 2 + ny * curvature
        
        stem = f'<path d="M {x1:.1f},{y1:.1f} Q {mid_x:.1f},{mid_y:.1f} {x2:.1f},{y2:.1f}" fill="none" stroke="{stroke}" stroke-width="{width}" stroke-linecap="round" />'
        angle = math.atan2(y2 - mid_y, x2 - mid_x)
        head_len = 13
        h1_x = x2 - head_len * math.cos(angle - 0.42)
        h1_y = y2 - head_len * math.sin(angle - 0.42)
        h2_x = x2 - head_len * math.cos(angle + 0.42)
        h2_y = y2 - head_len * math.sin(angle + 0.42)
        head = f'<path d="M {h1_x:.1f},{h1_y:.1f} L {x2:.1f},{y2:.1f} L {h2_x:.1f},{h2_y:.1f}" fill="none" stroke="{stroke}" stroke-width="{width}" stroke-linecap="round" stroke-linejoin="round" />'
        
        text_markup = ""
        if label:
            tx = mid_x
            ty = mid_y + label_dy
            text_markup = f'<text x="{tx:.1f}" y="{ty:.1f}" fill="{stroke}" font-family="Caveat, cursive, sans-serif" font-size="17" font-weight="700" text-anchor="middle">{label}</text>'
        return f"{stem}\n  {head}\n  {text_markup}"

def create_architecture_diagram():
    s = Sketch(seed=101)
    w, h = 980, 530
    svg = []
    svg.append(f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" width="100%" height="auto" style="background: #0B0F19; border-radius: 14px;">')
    svg.append('''<defs>
  <style>
  /* <![CDATA[ */
    @import url('https://fonts.googleapis.com/css2?family=Caveat:wght@600;700&family=JetBrains+Mono:wght@500;700&family=Inter:wght@500;600;700&display=swap');
    .title { font-family: 'Inter', system-ui, -apple-system, sans-serif; font-weight: 700; fill: #F0F6FC; }
    .mono { font-family: 'JetBrains Mono', ui-monospace, monospace; font-size: 13px; fill: #94A3B8; }
    .hand { font-family: 'Caveat', cursive, sans-serif; font-size: 20px; font-weight: 700; }
    .hand-sm { font-family: 'Caveat', cursive, sans-serif; font-size: 16px; font-weight: 600; }
    .badge { font-family: 'JetBrains Mono', monospace; font-size: 11px; font-weight: 700; text-transform: uppercase; }
  /* ]]> */
  </style>
  <pattern id="blueprint-grid" width="28" height="28" patternUnits="userSpaceOnUse">
    <path d="M 28 0 L 0 0 0 28" fill="none" stroke="#1E293B" stroke-width="0.7" opacity="0.65" />
  </pattern>
</defs>''')
    
    svg.append(f'<rect width="{w}" height="{h}" rx="14" fill="#0B0F19" />')
    svg.append(f'<rect width="{w}" height="{h}" rx="14" fill="url(#blueprint-grid)" opacity="0.85" />')
    svg.append(s.rough_rect(14, 14, w - 28, h - 28, stroke="#334155", fill="none", width=1.4, rx=10))

    # Header Title
    svg.append(f'<text x="44" y="52" class="title" font-size="20">NETWICH SOCKET BINDING ARCHITECTURE</text>')
    svg.append(f'<text x="44" y="74" class="hand" fill="#60A5FA" font-size="18">How local apps stack multiple physical links simultaneously</text>')
    
    # 1. Source App Layer (Left)
    svg.append(s.rough_rect(44, 105, 215, 165, stroke="#94A3B8", fill="rgba(30, 41, 59, 0.45)", width=1.8))
    svg.append(f'<text x="64" y="136" class="title" font-size="16">Your Applications</text>')
    svg.append(f'<text x="64" y="162" class="mono">• Safari &amp; Chrome</text>')
    svg.append(f'<text x="64" y="185" class="mono">• curl, git, package CLI</text>')
    svg.append(f'<text x="64" y="208" class="mono">• Netwich Downloader</text>')
    svg.append(f'<text x="64" y="244" class="hand-sm" fill="#94A3B8">Seamless system proxy</text>')

    # Arrow from Apps to Netwich Hub
    svg.append(s.rough_arrow(260, 187, 345, 187, stroke="#F0F6FC", width=2.4, curvature=-3, label="SOCKS5 :1080", label_dy=-13))

    # 2. Netwich Core Engine Hub (Center)
    svg.append(s.rough_rect(350, 95, 265, 255, stroke="#60A5FA", fill="rgba(15, 23, 42, 0.85)", width=2.2))
    svg.append(f'<rect x="368" y="112" width="115" height="22" rx="6" fill="#1E3A8A" />')
    svg.append(f'<text x="376" y="127" class="badge" fill="#93C5FD">NETWICH CORE</text>')
    svg.append(f'<text x="368" y="160" class="title" font-size="17" fill="#F0F6FC">Dynamic Flow Engine</text>')
    
    # Hub internal features
    svg.append(s.rough_rect(368, 175, 228, 42, stroke="#3B82F6", fill="rgba(59, 130, 246, 0.12)", width=1.2, rx=6))
    svg.append(f'<text x="380" y="201" class="mono" fill="#E2E8F0" font-size="12">Weighted Least-Conns</text>')
    
    svg.append(s.rough_rect(368, 226, 228, 42, stroke="#10B981", fill="rgba(16, 185, 129, 0.12)", width=1.2, rx=6))
    svg.append(f'<text x="380" y="252" class="mono" fill="#E2E8F0" font-size="12">EWMA Latency &amp; Probing</text>')

    svg.append(s.rough_rect(368, 277, 228, 42, stroke="#A855F7", fill="rgba(168, 85, 247, 0.12)", width=1.2, rx=6))
    svg.append(f'<text x="380" y="303" class="mono" fill="#E2E8F0" font-size="12">Socket Bound: IP_BOUND_IF</text>')

    # Arrows from Netwich Hub to Adapters
    svg.append(s.rough_arrow(615, 155, 715, 145, stroke="#3B82F6", width=2.6, curvature=-10, label="flow α", label_dy=-10))
    svg.append(s.rough_arrow(615, 275, 715, 285, stroke="#10B981", width=2.6, curvature=10, label="flow β", label_dy=20))

    # 3. Physical Adapters (Right Top & Right Bottom)
    svg.append(s.rough_rect(720, 100, 215, 95, stroke="#3B82F6", fill="rgba(30, 58, 138, 0.25)", width=2.0))
    svg.append(f'<text x="738" y="128" class="title" font-size="15" fill="#93C5FD">Wi-Fi (en0)</text>')
    svg.append(f'<text x="738" y="150" class="mono" font-size="12">Rate: 85 Mbps</text>')
    svg.append(f'<text x="738" y="170" class="mono" font-size="12">RTT: 18ms (Weight 1.0)</text>')

    svg.append(s.rough_rect(720, 240, 215, 95, stroke="#10B981", fill="rgba(6, 78, 59, 0.25)", width=2.0))
    svg.append(f'<text x="738" y="268" class="title" font-size="15" fill="#6EE7B7">USB Tether (en5)</text>')
    svg.append(f'<text x="738" y="290" class="mono" font-size="12">Rate: 110 Mbps (5G)</text>')
    svg.append(f'<text x="738" y="310" class="mono" font-size="12">RTT: 22ms (Weight 1.3)</text>')

    # Downward arrows from adapters to combined pipe
    svg.append(s.rough_arrow(795, 198, 795, 385, stroke="#60A5FA", width=2.0, curvature=0))
    svg.append(s.rough_arrow(875, 338, 875, 385, stroke="#34D399", width=2.0, curvature=0))

    # 4. Merged Output Pipe (Bottom Right)
    svg.append(s.rough_rect(245, 390, 690, 95, stroke="#F59E0B", fill="rgba(245, 158, 11, 0.10)", width=2.2))
    svg.append(f'<text x="268" y="422" class="title" font-size="17" fill="#FCD34D">Unified Combined Pipe = 195 Mbps Total Throughput</text>')
    svg.append(f'<text x="268" y="446" class="mono" font-size="12" fill="#E2E8F0">Zero packet loss • Sub-100ms failover • Safe local proxy recovery</text>')
    svg.append(f'<text x="268" y="470" class="hand" font-size="18" fill="#FBBF24">All flows combined automatically without remote multi-path proxies!</text>')

    # Key callout badges (Bottom Left)
    svg.append(s.rough_rect(44, 390, 185, 95, stroke="#334155", fill="rgba(15, 23, 42, 0.6)", width=1.4))
    svg.append(f'<text x="60" y="420" class="hand" fill="#38BDF8">✓ 100% On-Mac</text>')
    svg.append(f'<text x="60" y="446" class="hand" fill="#38BDF8">✓ Zero Cloud Relay</text>')
    svg.append(f'<text x="60" y="472" class="hand" fill="#38BDF8">✓ No Root Daemons</text>')

    svg.append('</svg>')
    return "\n".join(svg)

def create_chunked_download_diagram():
    s = Sketch(seed=202)
    w, h = 980, 480
    svg = []
    svg.append(f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" width="100%" height="auto" style="background: #0B0F19; border-radius: 14px;">')
    svg.append('''<defs>
  <style>
  /* <![CDATA[ */
    @import url('https://fonts.googleapis.com/css2?family=Caveat:wght@600;700&family=JetBrains+Mono:wght@500;700&family=Inter:wght@500;600;700&display=swap');
    .title { font-family: 'Inter', system-ui, -apple-system, sans-serif; font-weight: 700; fill: #F0F6FC; }
    .mono { font-family: 'JetBrains Mono', ui-monospace, monospace; font-size: 13px; fill: #94A3B8; }
    .hand { font-family: 'Caveat', cursive, sans-serif; font-size: 20px; font-weight: 700; }
    .hand-sm { font-family: 'Caveat', cursive, sans-serif; font-size: 16px; font-weight: 600; }
  /* ]]> */
  </style>
  <pattern id="download-grid" width="28" height="28" patternUnits="userSpaceOnUse">
    <path d="M 28 0 L 0 0 0 28" fill="none" stroke="#1E293B" stroke-width="0.7" opacity="0.65" />
  </pattern>
</defs>''')
    
    svg.append(f'<rect width="{w}" height="{h}" rx="14" fill="#0B0F19" />')
    svg.append(f'<rect width="{w}" height="{h}" rx="14" fill="url(#download-grid)" opacity="0.85" />')
    svg.append(s.rough_rect(14, 14, w - 28, h - 28, stroke="#334155", fill="none", width=1.4, rx=10))

    # Header
    svg.append(f'<text x="44" y="52" class="title" font-size="20">MULTI-LINK CHUNKED DOWNLOAD ACCELERATION</text>')
    svg.append(f'<text x="44" y="74" class="hand" fill="#34D399" font-size="18">How Netwich cuts download durations in half with parallel byte-range streams</text>')

    # 1. Traditional Single Link (Top Half)
    svg.append(s.rough_rect(44, 96, 892, 135, stroke="#475569", fill="rgba(30, 41, 59, 0.3)", width=1.6))
    svg.append(f'<text x="64" y="126" class="title" font-size="16" fill="#CBD5E1">Standard Single-Connection Download (Slow)</text>')
    svg.append(f'<text x="64" y="148" class="mono" font-size="12">1x Wi-Fi Adapter (en0) @ 45 Mbps • 1 Sequential Stream • 2.4 GB Archive</text>')
    
    # Progress Bar (Single slow stream)
    svg.append(s.rough_rect(64, 162, 630, 36, stroke="#3B82F6", fill="rgba(59, 130, 246, 0.15)", width=1.6, rx=6))
    svg.append(s.rough_rect(64, 162, 210, 36, stroke="#60A5FA", fill="rgba(59, 130, 246, 0.45)", width=1.6, rx=6))
    svg.append(f'<text x="160" y="185" class="mono" font-size="12" fill="#FFFFFF">34% (Single Stream)</text>')
    svg.append(f'<text x="720" y="186" class="hand" font-size="22" fill="#F87171">⏳ Takes 11m 40s</text>')

    # 2. Netwich Parallel Chunking (Bottom Half)
    svg.append(s.rough_rect(44, 245, 892, 195, stroke="#10B981", fill="rgba(16, 185, 129, 0.08)", width=2.0))
    svg.append(f'<text x="64" y="275" class="title" font-size="16" fill="#6EE7B7">With Netwich: 4 Ranged Chunks Split Across 2 Adapters</text>')
    svg.append(f'<text x="64" y="297" class="mono" font-size="12">Wi-Fi (en0) @ 45 Mbps + USB Phone 5G (en5) @ 85 Mbps = 130 Mbps Combined!</text>')

    # 4 chunk boxes cleanly spaced
    box_w = 142
    gap = 16
    start_x = 64
    y_box = 315

    # Chunk 1: Wi-Fi
    x1 = start_x
    svg.append(s.rough_rect(x1, y_box, box_w, 44, stroke="#3B82F6", fill="rgba(59, 130, 246, 0.35)", width=1.5, rx=6))
    svg.append(f'<text x="{x1+12}" y="{y_box+20}" class="mono" font-size="11" fill="#FFFFFF">Chunk 1: 0-600M</text>')
    svg.append(f'<text x="{x1+12}" y="{y_box+36}" class="hand-sm" fill="#93C5FD">via Wi-Fi (en0)</text>')

    # Chunk 2: Phone 5G
    x2 = x1 + box_w + gap
    svg.append(s.rough_rect(x2, y_box, box_w, 44, stroke="#10B981", fill="rgba(16, 185, 129, 0.35)", width=1.5, rx=6))
    svg.append(f'<text x="{x2+12}" y="{y_box+20}" class="mono" font-size="11" fill="#FFFFFF">Chunk 2: 600M-1.2G</text>')
    svg.append(f'<text x="{x2+12}" y="{y_box+36}" class="hand-sm" fill="#6EE7B7">via Phone 5G (en5)</text>')

    # Chunk 3: Wi-Fi
    x3 = x2 + box_w + gap
    svg.append(s.rough_rect(x3, y_box, box_w, 44, stroke="#3B82F6", fill="rgba(59, 130, 246, 0.35)", width=1.5, rx=6))
    svg.append(f'<text x="{x3+12}" y="{y_box+20}" class="mono" font-size="11" fill="#FFFFFF">Chunk 3: 1.2G-1.8G</text>')
    svg.append(f'<text x="{x3+12}" y="{y_box+36}" class="hand-sm" fill="#93C5FD">via Wi-Fi (en0)</text>')

    # Chunk 4: Phone 5G
    x4 = x3 + box_w + gap
    svg.append(s.rough_rect(x4, y_box, box_w, 44, stroke="#10B981", fill="rgba(16, 185, 129, 0.35)", width=1.5, rx=6))
    svg.append(f'<text x="{x4+12}" y="{y_box+20}" class="mono" font-size="11" fill="#FFFFFF">Chunk 4: 1.8G-2.4G</text>')
    svg.append(f'<text x="{x4+12}" y="{y_box+36}" class="hand-sm" fill="#6EE7B7">via Phone 5G (en5)</text>')

    # Result tag on right
    svg.append(f'<text x="720" y="342" class="hand" font-size="24" fill="#34D399">⚡ Takes 4m 05s</text>')
    svg.append(f'<text x="720" y="365" class="mono" font-size="12" fill="#FCD34D">(2.8x faster speedup)</text>')

    # Bottom notes
    svg.append(f'<text x="64" y="415" class="hand" font-size="18" fill="#FCD34D">✓ Dynamic range chunking • Automatic reassembly • SHA-256 verification</text>')

    svg.append('</svg>')
    return "\n".join(svg)

def create_failover_diagram():
    s = Sketch(seed=303)
    w, h = 980, 460
    svg = []
    svg.append(f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" width="100%" height="auto" style="background: #0B0F19; border-radius: 14px;">')
    svg.append('''<defs>
  <style>
  /* <![CDATA[ */
    @import url('https://fonts.googleapis.com/css2?family=Caveat:wght@600;700&family=JetBrains+Mono:wght@500;700&family=Inter:wght@500;600;700&display=swap');
    .title { font-family: 'Inter', system-ui, -apple-system, sans-serif; font-weight: 700; fill: #F0F6FC; }
    .mono { font-family: 'JetBrains Mono', ui-monospace, monospace; font-size: 13px; fill: #94A3B8; }
    .hand { font-family: 'Caveat', cursive, sans-serif; font-size: 20px; font-weight: 700; }
    .hand-sm { font-family: 'Caveat', cursive, sans-serif; font-size: 16px; font-weight: 600; }
    .badge { font-family: 'JetBrains Mono', monospace; font-size: 11px; font-weight: 700; text-transform: uppercase; }
  /* ]]> */
  </style>
  <pattern id="failover-grid" width="28" height="28" patternUnits="userSpaceOnUse">
    <path d="M 28 0 L 0 0 0 28" fill="none" stroke="#1E293B" stroke-width="0.7" opacity="0.65" />
  </pattern>
</defs>''')
    
    svg.append(f'<rect width="{w}" height="{h}" rx="14" fill="#0B0F19" />')
    svg.append(f'<rect width="{w}" height="{h}" rx="14" fill="url(#failover-grid)" opacity="0.85" />')
    svg.append(s.rough_rect(14, 14, w - 28, h - 28, stroke="#334155", fill="none", width=1.4, rx=10))

    # Header
    svg.append(f'<text x="44" y="52" class="title" font-size="20">ZERO-DROP RESILIENT FAILOVER</text>')
    svg.append(f'<text x="44" y="74" class="hand" fill="#FBBF24" font-size="18">How Netwich keeps connections alive when an adapter flickers or unplugs</text>')

    col_w = 260
    col_y = 105
    col_h = 240

    # Step 1: Normal Aggregation
    c1_x = 44
    svg.append(s.rough_rect(c1_x, col_y, col_w, col_h, stroke="#3B82F6", fill="rgba(30, 41, 59, 0.4)", width=1.8))
    svg.append(f'<rect x="{c1_x+16}" y="122" width="75" height="20" rx="5" fill="#1E3A8A" />')
    svg.append(f'<text x="{c1_x+24}" y="136" class="badge" fill="#93C5FD">PHASE 1</text>')
    svg.append(f'<text x="{c1_x+16}" y="165" class="title" font-size="16" fill="#F0F6FC">Dual Active Links</text>')
    svg.append(f'<text x="{c1_x+16}" y="195" class="mono" font-size="12">• Wi-Fi (en0): OK (18ms)</text>')
    svg.append(f'<text x="{c1_x+16}" y="218" class="mono" font-size="12">• Tether (en5): OK (24ms)</text>')
    svg.append(f'<text x="{c1_x+16}" y="248" class="mono" font-size="12" fill="#34D399">Traffic balanced 50/50</text>')
    svg.append(f'<text x="{c1_x+16}" y="274" class="mono" font-size="12">195 Mbps Combined Rate</text>')
    svg.append(f'<text x="{c1_x+16}" y="315" class="hand" font-size="17" fill="#60A5FA">Both pipes healthy &amp; active</text>')

    # Arrow 1 -> 2
    svg.append(s.rough_arrow(c1_x + col_w + 6, 222, c1_x + col_w + 50, 222, stroke="#F59E0B", width=2.4, curvature=-6, label="Drop!", label_dy=-12))

    # Step 2: Signal Drop
    c2_x = c1_x + col_w + 56
    svg.append(s.rough_rect(c2_x, col_y, col_w, col_h, stroke="#EF4444", fill="rgba(239, 68, 68, 0.08)", width=2.0))
    svg.append(f'<rect x="{c2_x+16}" y="122" width="75" height="20" rx="5" fill="#7F1D1D" />')
    svg.append(f'<text x="{c2_x+24}" y="136" class="badge" fill="#FCA5A5">PHASE 2</text>')
    svg.append(f'<text x="{c2_x+16}" y="165" class="title" font-size="16" fill="#FCA5A5">Wi-Fi Sudden Drop</text>')
    svg.append(f'<text x="{c2_x+16}" y="195" class="mono" font-size="12" fill="#F87171">✕ Wi-Fi (en0): Disconnected</text>')
    svg.append(f'<text x="{c2_x+16}" y="218" class="mono" font-size="12">• Tether (en5): Active</text>')
    svg.append(f'<text x="{c2_x+16}" y="248" class="mono" font-size="12" fill="#FBBF24">EWMA trigger in 80ms</text>')
    svg.append(f'<text x="{c2_x+16}" y="274" class="mono" font-size="12">Wi-Fi unweighted</text>')
    svg.append(f'<text x="{c2_x+16}" y="315" class="hand" font-size="17" fill="#F87171">Zero socket reset thrown!</text>')

    # Arrow 2 -> 3
    svg.append(s.rough_arrow(c2_x + col_w + 6, 222, c2_x + col_w + 50, 222, stroke="#10B981", width=2.4, curvature=6, label="Shift", label_dy=-12))

    # Step 3: Zero-Interruption Recovery
    c3_x = c2_x + col_w + 56
    svg.append(s.rough_rect(c3_x, col_y, col_w, col_h, stroke="#10B981", fill="rgba(16, 185, 129, 0.12)", width=2.0))
    svg.append(f'<rect x="{c3_x+16}" y="122" width="75" height="20" rx="5" fill="#065F46" />')
    svg.append(f'<text x="{c3_x+24}" y="136" class="badge" fill="#6EE7B7">PHASE 3</text>')
    svg.append(f'<text x="{c3_x+16}" y="165" class="title" font-size="16" fill="#6EE7B7">Seamless Fallback</text>')
    svg.append(f'<text x="{c3_x+16}" y="195" class="mono" font-size="12">• Tether (en5): 100% Load</text>')
    svg.append(f'<text x="{c3_x+16}" y="218" class="mono" font-size="12" fill="#6EE7B7">✓ All streams preserved</text>')
    svg.append(f'<text x="{c3_x+16}" y="248" class="mono" font-size="12">Downloads never reset</text>')
    svg.append(f'<text x="{c3_x+16}" y="274" class="mono" font-size="12">Auto-resumes on return</text>')
    svg.append(f'<text x="{c3_x+16}" y="315" class="hand" font-size="17" fill="#34D399">Uninterrupted browsing &amp; calls</text>')

    # Bottom summary bar
    svg.append(s.rough_rect(44, 370, 892, 58, stroke="#334155", fill="rgba(15, 23, 42, 0.65)", width=1.4))
    svg.append(f'<text x="64" y="405" class="hand" font-size="18" fill="#FCD34D">Unlike traditional networking, your active transfers do not abort when one link drops.</text>')

    svg.append('</svg>')
    return "\n".join(svg)

def main():
    os.makedirs("docs/assets", exist_ok=True)
    
    with open("docs/assets/netwich-architecture.svg", "w", encoding="utf-8") as f:
        f.write(create_architecture_diagram())
    print("Generated docs/assets/netwich-architecture.svg")

    with open("docs/assets/netwich-chunked-downloads.svg", "w", encoding="utf-8") as f:
        f.write(create_chunked_download_diagram())
    print("Generated docs/assets/netwich-chunked-downloads.svg")

    with open("docs/assets/netwich-failover.svg", "w", encoding="utf-8") as f:
        f.write(create_failover_diagram())
    print("Generated docs/assets/netwich-failover.svg")

if __name__ == "__main__":
    main()
