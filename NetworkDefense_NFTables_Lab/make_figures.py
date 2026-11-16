#!/usr/bin/env python3
"""Draw SVG charts from observed CSV results only, without plotting dependencies."""
import csv
from collections import defaultdict
from pathlib import Path
from xml.sax.saxutils import escape

root = Path(__file__).parent / 'results'
files = sorted(root.glob('tcp_*.csv'))
if not files:
    raise SystemExit('No actual experiment CSVs available.')
counts = defaultdict(lambda:[0,0])
for path in files:
    with path.open(newline='', encoding='utf-8') as handle:
        for row in csv.DictReader(handle):
            counts[row['mode'], row['target']][0] += int(row['success'])
            counts[row['mode'], row['target']][1] += 1
modes = [x for x in ['flat','routed_open','segmented_acl'] if any(m==x for m,t in counts)]
targets = ['user','web','database','admin']
colors = {'flat':'#5b8d80', 'routed_open':'#9a9c97','segmented_acl':'#bd785d'}
width, height = 860, 405
svg = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">',
       '<rect width="100%" height="100%" fill="white"/>',
       '<text x="35" y="35" font-family="DejaVu Sans" font-size="18" font-weight="bold">Keberhasilan Koneksi TCP per Target</text>',
       '<text x="35" y="55" font-family="DejaVu Sans" font-size="12" fill="#555">Dihitung dari CSV pengujian aktual, bukan data perkiraan</text>']
left, top, plot_w, plot_h = 70, 85, 755, 245
for frac in (0,.25,.5,.75,1):
    y = top+plot_h*(1-frac)
    svg.append(f'<line x1="{left}" y1="{y}" x2="{left+plot_w}" y2="{y}" stroke="#eee"/>')
    svg.append(f'<text x="{left-12}" y="{y+4}" font-size="11" text-anchor="end">{int(frac*100)}%</text>')
for i,t in enumerate(targets):
    x0 = left+plot_w*(i+.5)/len(targets)
    barw = 33
    for j,m in enumerate(modes):
        good,total = counts[m,t]
        frac = good/total if total else 0
        x = x0 + (j-(len(modes)-1)/2)*40 - barw/2
        y = top+plot_h*(1-frac)
        svg.append(f'<rect x="{x}" y="{y}" width="{barw}" height="{plot_h*frac}" fill="{colors[m]}"/>')
        svg.append(f'<text x="{x+barw/2}" y="{max(y-8,top+8)}" font-size="10" text-anchor="middle">{good}/{total}</text>')
    svg.append(f'<text x="{x0}" y="{top+plot_h+24}" text-anchor="middle" font-size="13">{escape(t.upper())}</text>')
for k,m in enumerate(modes):
    x=225+k*195
    svg.append(f'<rect x="{x}" y="{height-28}" width="13" height="13" fill="{colors[m]}"/>')
    svg.append(f'<text x="{x+18}" y="{height-17}" font-size="11">{escape(m)}</text>')
svg.append('</svg>')
(root/'figure_actual_connections.svg').write_text('\n'.join(svg),encoding='utf-8')
print('Wrote actual-evidence chart:', root/'figure_actual_connections.svg')
