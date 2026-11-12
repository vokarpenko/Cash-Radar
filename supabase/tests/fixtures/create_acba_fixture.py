# -*- coding: utf-8 -*-
"""Synthetic ACBA format; no customer data."""
from pathlib import Path
from xml.sax.saxutils import escape
from zipfile import ZipFile, ZIP_DEFLATED

base = Path(__file__).parent
rows = {
  2: {'C': ('s', '0')},
  17: {'D': ('inlineStr', 'ԿԱՏԱՐՎԱԾ ԳՈՐԾԱՐՔՆԵՐԻ ՎԵՐԱԲԵՐՅԱԼ ԱՄՓՈՓ ՏԵՂԵԿԱՏՎՈՒԹՅՈՒՆ (AMD )')},
  19: {k:('inlineStr',v) for k,v in {'D':'1,000.00','AJ':'1,047.50'}.items()},
  24: {k:('inlineStr',v) for k,v in {'I':'Գործարքի գումարը քարտի արժույթով','X':'Գործարքի նկարագրություն','AI':'Գործարքի միջնորդավճար'}.items()},
  25: {k:('inlineStr',v) for k,v in {'C':'Գործարքի ամսաթիվ','F':'Գործարքի գումարը','G':'Արժույթ','I':'Մուտք','K':'Ելք'}.items()},
  26: {k:('inlineStr',v) for k,v in {'C':'01.10.2026','I':'+ 100.00','S':'01.10.26','X':'Synthetic income'}.items()},
  27: {k:('inlineStr',v) for k,v in {'C':'02.10.2026','F':'50.00','G':'AMD','K':'- 50.00','S':'02.10.26','X':'Synthetic purchase','AD':'Synthetic merchant','AI':'- 2.50'}.items()},
  28: {k:('inlineStr',v) for k,v in {'V':'1,047.50','X':'Մնացորդ-Օրվա վերջի դրությամբ հաշվի վերջնական մնացորդ'}.items()},
  30: {'B':('inlineStr','OTHER SECTION')},
}
def worksheet(data):
 body=[]
 for number,cells in sorted(data.items()):
  content=[]
  for col,(kind,val) in cells.items():
   cell=f'<v>{escape(val)}</v>' if kind=='s' else f'<is><t>{escape(val)}</t></is>'
   content.append(f'<c r="{col}{number}" t="{kind}">{cell}</c>')
  body.append(f'<row r="{number}">'+''.join(content)+'</row>')
 return '<?xml version="1.0"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>'+''.join(body)+'</sheetData></worksheet>'
with ZipFile(base/'ameria_synthetic.xlsx') as z: files={name:z.read(name) for name in z.namelist()}
files['xl/sharedStrings.xml']=b'<?xml version="1.0"?><sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><si><t>ACBA Bank</t></si></sst>'
def save(name):
 files['xl/worksheets/sheet1.xml']=worksheet(rows).encode()
 with ZipFile(base/name,'w',ZIP_DEFLATED) as z:
  for name,data in files.items():z.writestr(name,data)
save('acba_synthetic.xlsx')
rows[27]['AI']=('inlineStr','- 9.50')
save('acba_unbalanced_synthetic.xlsx')

# Pending-format sample is deliberately not assumed to be importable.
rows[27]['AI']=('inlineStr','- 2.50')
rows[31]={'B':('inlineStr','Չհաստատված գործարքներ')}
save('acba_pending_synthetic.xlsx')
