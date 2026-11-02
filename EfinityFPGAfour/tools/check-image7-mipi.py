"""Check application of the experimental MIPI margins, not board correctness."""
from pathlib import Path
import argparse
import hashlib
import json
import re

root=Path(__file__).resolve().parents[1]
image=root/'images/image7_mocap11_a'
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--report',type=Path,default=image/'outflow/Ti60_Image7_Mocap11_A.timing.rpt')
parser.add_argument('--sdc',type=Path,default=image/'Ti60_Image7_Mocap11_A.pt.sdc')
args=parser.parse_args()
text=args.report.read_text()
sdc=args.sdc.read_text()
for kind,value in [('setup','0.500'),('hold','0.300')]:
    expected=f'set_clock_uncertainty -{kind} -from [get_clocks {{csi_rxc_i}}] -to [get_clocks {{csi_rxc_i}}] {value}'
    if sdc.count(expected)!=1:raise AssertionError('Missing or duplicated MIPI margin '+kind)
if not re.search(r'(?m)^csi_rxc_i\s+6\.000\s+',text):raise AssertionError('Camera period changed')
records=[]
for kind,title,extra in [('setup','Path Details for Max Critical Paths',.5),('hold','Path Details for Min Critical Paths',.3)]:
    # The report lists the worst paths per clock relationship. With a new
    # placement the worst CSI path can be internal rather than pad-to-FF.
    # Require observed uncertainty on actual CSI->CSI paths in BOTH analyses;
    # never infer application from SDC text alone or from an unrelated clock.
    marker=title+' (begin)'
    if marker not in text:raise AssertionError('Missing timing section '+kind)
    part=text.split(marker,1)[1]
    if kind=='setup':part=part.split('Path Details for Min Critical Paths (begin)',1)[0]
    found=[]
    for block in re.split(r'\+\+\+\+ Path \d+',part):
        if not (re.search(r'Launch Clock\s*:\s*csi_rxc_i\b',block) and re.search(r'Capture Clock\s*:\s*csi_rxc_i\b',block)):continue
        begin=re.search(r'Path Begin\s*:\s*([^\n]+)',block)
        slack=re.search(r'Slack\s*:\s*(-?\d+\.\d+)',block)
        uncertainty=re.search(r'[+-] Clock Uncertainty\s*:\s*(\d+\.\d+)',block)
        if begin is None or slack is None or uncertainty is None:raise AssertionError('Incomplete CSI path '+kind)
        row=dict(analysis=kind,begin=begin[1].strip(),slack_ns=float(slack[1]),reported_uncertainty_ns=float(uncertainty[1]))
        if row['slack_ns']<0 or row['reported_uncertainty_ns']<extra:raise AssertionError(row)
        found.append(row)
    if not found:raise AssertionError('No observed CSI timing path: '+kind)
    records.extend(found)
report=dict(experimental=True,setup_extra_ns=.5,hold_extra_ns=.3,clock_period_ns=6.,paths=records,
            report_sha256=hashlib.sha256(args.report.read_bytes()).hexdigest(),
            constraints_sha256=hashlib.sha256(args.sdc.read_bytes()).hexdigest(),
            board_jitter_measured=False,board_failure_resolved=False,
            scope='Extra engineering margin. Does not prove MIPI sampling is the physical root cause or verify the candidate on hardware.')
(args.report.parent/'image7_mipi_guard.json').write_text(json.dumps(report,indent=2)+'\n')
print('PASS image7 experimental MIPI setup and hold margins were applied:',records)
